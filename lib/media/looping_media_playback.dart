import 'dart:async';
import 'dart:collection';

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
