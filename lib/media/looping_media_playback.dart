import 'dart:async';
import 'dart:collection';
import 'dart:ui' show Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:fvp/fvp.dart';
import 'package:video_player/video_player.dart';

import '../tdlib/td_client.dart';

/// Whether a permanently looping media surface is allowed to own a native
/// player right now. Hidden tabs and backgrounded apps keep their thumbnail
/// instead of retaining decoder threads.
bool loopingMediaPlaybackIsEligible({
  required bool tickerEnabled,
  required bool appIsActive,
}) => tickerEnabled && appIsActive;

/// A small, process-wide budget for muted GIF, WebM sticker, and custom-emoji
/// playback. Animated avatars intentionally use their own separate budget.
final LoopingMediaPlayerPool loopingMediaPlayerPool = LoopingMediaPlayerPool(
  maximumPlayers: 4,
);

/// Native players for video stickers (`.webm`), in the conversation and in
/// every picker.
///
/// The budget has to fit a viewport, not a fixed few: a sticker picker page
/// shows a dozen or more cells at once, and a sticker only competes for a
/// player while it is actually on screen ([loopingSurfaceIsOnScreen]), so the
/// cap is a safety valve for pathological layouts rather than the ordinary
/// case. A sticker that is scrolled out (or cached by the list) drops its
/// player and gets a fresh one when it comes back.
final LoopingMediaPlayerPool stickerPlayerPool = LoopingMediaPlayerPool(
  maximumPlayers: 24,
);

final Set<VoidCallback> _playbackContextListeners = <VoidCallback>{};
StreamSubscription<int>? _activeSlotSubscription;

/// Registers a looping-media surface for rare process-wide context changes.
///
/// Account changes use one shared TDLib subscription regardless of how many
/// animated tiles are mounted. Availability is handled separately by the
/// pool's bounded FIFO so it never wakes every waiting tile at once.
void addLoopingMediaPlaybackContextListener(VoidCallback listener) {
  _playbackContextListeners.add(listener);
  _activeSlotSubscription ??= TdClient.shared
      .subscribeActiveSlotChanges()
      .listen((_) {
        scheduleMicrotask(() {
          for (final current in List<VoidCallback>.of(
            _playbackContextListeners,
          )) {
            current();
          }
        });
      });
}

void removeLoopingMediaPlaybackContextListener(VoidCallback listener) {
  _playbackContextListeners.remove(listener);
}

/// Whether a looping media surface is worth a native player right now.
///
/// Scroll views keep a cache extent of children laid out above and below the
/// viewport; those are mounted and would otherwise hold players for content
/// nobody can see. A small [margin] keeps a sticker alive across a short
/// overscroll instead of tearing its decoder down and building it again.
bool loopingSurfaceIsOnScreen({
  required Rect rect,
  required Size screen,
  double margin = 0,
}) {
  if (screen.isEmpty || rect.isEmpty) return false;
  final visible = Rect.fromLTWH(
    -margin,
    -margin,
    screen.width + margin * 2,
    screen.height + margin * 2,
  );
  return rect.overlaps(visible);
}

/// Remembers whether a looping surface is inside the viewport, so a scroll
/// tick only triggers work when the answer actually changed.
class LoopingSurfaceVisibility {
  LoopingSurfaceVisibility({this.margin = 0});

  /// Extra room around the viewport that still counts as visible, so a short
  /// overscroll does not tear a decoder down and build it again.
  final double margin;

  bool _onScreen = true;
  bool get isOnScreen => _onScreen;

  /// Feeds a freshly measured [rect] (null while the surface has no render box
  /// yet) and reports whether visibility flipped.
  bool update({required Rect? rect, required Size screen}) {
    final next = rect == null
        ? _onScreen
        : loopingSurfaceIsOnScreen(rect: rect, screen: screen, margin: margin);
    if (next == _onScreen) return false;
    _onScreen = next;
    return true;
  }
}

/// Pure FIFO lease pool used to cap native looping-media players.
class LoopingMediaPlayerPool {
  LoopingMediaPlayerPool({required this.maximumPlayers})
    : assert(maximumPlayers > 0);

  final int maximumPlayers;
  int _activePlayers = 0;
  final Queue<_LoopingMediaLeaseRequest> _waiting =
      Queue<_LoopingMediaLeaseRequest>();

  int get activePlayers => _activePlayers;
  int get waitingRequests => _waiting.length;

  LoopingMediaPlayerLease? tryAcquire() {
    if (_activePlayers >= maximumPlayers || _waiting.isNotEmpty) return null;
    return _reserveLease();
  }

  /// Waits fairly for one lease. A released slot is reserved before its single
  /// callback is scheduled, so another widget cannot steal it or create a
  /// thundering herd of file-resolution work.
  LoopingMediaPlayerWaiter waitForLease(
    ValueChanged<LoopingMediaPlayerLease> onGranted,
  ) {
    final request = _LoopingMediaLeaseRequest(onGranted);
    _waiting.addLast(request);
    _grantWaitingLeases();
    return LoopingMediaPlayerWaiter._(this, request);
  }

  LoopingMediaPlayerLease _reserveLease() {
    _activePlayers++;
    return LoopingMediaPlayerLease._(this);
  }

  void _cancel(_LoopingMediaLeaseRequest request) {
    if (request.delivered) return;
    request.canceled = true;
    _waiting.remove(request);
    _grantWaitingLeases();
  }

  void _release() {
    if (_activePlayers == 0) return;
    _activePlayers--;
    _grantWaitingLeases();
  }

  void _grantWaitingLeases() {
    while (_activePlayers < maximumPlayers && _waiting.isNotEmpty) {
      final request = _waiting.removeFirst();
      if (request.canceled) continue;
      final lease = _reserveLease();
      scheduleMicrotask(() {
        if (request.canceled) {
          lease.release();
          return;
        }
        request.delivered = true;
        try {
          request.onGranted(lease);
        } catch (_) {
          lease.release();
          rethrow;
        }
      });
    }
  }
}

class _LoopingMediaLeaseRequest {
  _LoopingMediaLeaseRequest(this.onGranted);

  final ValueChanged<LoopingMediaPlayerLease> onGranted;
  bool delivered = false;
  bool canceled = false;
}

class LoopingMediaPlayerWaiter {
  LoopingMediaPlayerWaiter._(this._pool, this._request);

  final LoopingMediaPlayerPool _pool;
  final _LoopingMediaLeaseRequest _request;
  bool _canceled = false;

  void cancel() {
    if (_canceled) return;
    _canceled = true;
    _pool._cancel(_request);
  }
}

class LoopingMediaPlayerLease {
  LoopingMediaPlayerLease._(this._pool);

  final LoopingMediaPlayerPool _pool;
  bool _released = false;

  bool get isReleased => _released;

  void release() {
    if (_released) return;
    _released = true;
    _pool._release();
  }
}

/// Muted looping media never needs an audio decoder. FVP exposes track
/// selection beyond video_player's portable API; official platform players
/// throw here and safely retain the volume-zero fallback.
///
/// Android's [video_player] backend otherwise enables audio focus for every
/// player, including a muted avatar or sticker. That pauses music from another
/// app as soon as a chat containing one of these surfaces is opened.
VideoPlayerOptions mutedLoopingVideoPlayerOptions() =>
    VideoPlayerOptions(mixWithOthers: true);

void disableLoopingMediaAudioTracks(VideoPlayerController controller) {
  try {
    controller.setAudioTracks(const <int>[]);
  } catch (_) {
    // The active video_player backend is not FVP.
  }
}

/// Video decoder override for muted looping WebM (Telegram video stickers),
/// by [platform].
///
/// MDK's hardware decoders run the alpha-enhanced VP9 WebM Telegram encodes
/// stickers as ahead of the media clock: its VT path on Apple platforms, and
/// AMediaCodec's VP9 path on Android. The clip then visibly loops too fast
/// while H.264 GIF animations and audio-bearing videos keep their pacing.
/// Android's alpha-WebM registration asks FVP for FFmpeg, but that global
/// option only reaches players constructed after it — FVP's auto-registration
/// and the primary-backend route can build one before it lands, which is why
/// the per-player override has to be re-asserted after `initialize()`. Plain
/// FFmpeg decodes these clips with correct pacing and still outputs yuva420p
/// through MDK's enhancement-layer merge.
///
/// Returns null when the platform's default decoder order is fine.
@visibleForTesting
List<String>? webmLoopingDecoderOverride(TargetPlatform platform) {
  return switch (platform) {
    TargetPlatform.iOS || TargetPlatform.android => const <String>['FFmpeg'],
    _ => null,
  };
}

/// Applies [webmLoopingDecoderOverride] to a looping WebM controller before
/// playback starts. Must run after `initialize()` so FVP has registered the
/// player. MDK permits decoder-priority updates after preparation as well;
/// keep this before the view's first playback request. Other
/// video_player backends (and platform fakes in tests) reject the call and
/// keep their own decoder selection.
void applyWebmLoopingDecoderOverride(VideoPlayerController controller) {
  final decoders = webmLoopingDecoderOverride(defaultTargetPlatform);
  if (decoders == null) return;
  try {
    controller.setVideoDecoders(decoders);
  } catch (_) {
    // The active video_player backend is not FVP.
  }
}

/// Process-wide FVP decoder order for [platform], or empty to keep FVP's
/// default. FVP applies it when each player is created, before MDK opens the
/// first frame; [applyWebmLoopingDecoderOverride] runs too late to avoid it.
///
/// On Windows FVP's default prefers Media Foundation over Direct3D 11. Decoding
/// the VP9 WebM stickers and custom emoji that load right after sign-in
/// through that path makes NVIDIA's D3D11 driver abort the process (seen on a
/// GTX 1650 beside an AMD iGPU; the app is stable when forced onto the iGPU).
/// Software decoding keeps rendering through D3D11 but skips the hardware
/// decoder that aborts.
List<String> fvpVideoDecoders(TargetPlatform platform) {
  return switch (platform) {
    TargetPlatform.windows => const <String>['FFmpeg', 'dav1d'],
    _ => const <String>[],
  };
}
