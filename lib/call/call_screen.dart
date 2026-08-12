//
//  call_screen.dart
//
//  Full-screen 1:1 call UI driven by a `CallManager`, styled after the reference app's voice /
//  video call screens: a blurred-avatar backdrop, a large rounded-square avatar
//  with name + status, the端到端 verification emojis, and a row of frosted
//  translucent controls (mute / speaker / camera) over a red 挂断 — with
//  green 接听 / red 拒绝 for an incoming call. Video calls fill the screen with
//  the remote feed and a small local preview (PiP).
//

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/photo_avatar.dart'; // PhotoAvatar + TDImage
import '../theme/app_theme.dart';
import 'call_manager.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.manager});
  final CallManager manager;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  Timer? _overlayTimer;
  bool _videoWasActive = false;
  bool _overlayVisible = true;

  bool get _isActiveVideo {
    final call = widget.manager.call;
    return call != null &&
        call.phase == CallPhase.active &&
        widget.manager.isVideoEnabled;
  }

  @override
  void initState() {
    super.initState();
    widget.manager.addListener(_handleManagerChanged);
    _videoWasActive = _isActiveVideo;
    if (_videoWasActive) _scheduleOverlayHide();
  }

  @override
  void didUpdateWidget(covariant CallScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.manager == widget.manager) return;
    oldWidget.manager.removeListener(_handleManagerChanged);
    widget.manager.addListener(_handleManagerChanged);
    _videoWasActive = _isActiveVideo;
    _overlayVisible = true;
    _overlayTimer?.cancel();
    if (_videoWasActive) _scheduleOverlayHide();
  }

  @override
  void dispose() {
    widget.manager.removeListener(_handleManagerChanged);
    _overlayTimer?.cancel();
    super.dispose();
  }

  void _handleManagerChanged() {
    final activeVideo = _isActiveVideo;
    if (activeVideo == _videoWasActive) return;
    _videoWasActive = activeVideo;
    _overlayTimer?.cancel();
    _overlayVisible = true;
    if (activeVideo) _scheduleOverlayHide();
    if (mounted) setState(() {});
  }

  void _scheduleOverlayHide() {
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || !_isActiveVideo) return;
      setState(() => _overlayVisible = false);
    });
  }

  void _keepOverlayVisible() {
    if (!_isActiveVideo) return;
    if (!_overlayVisible) setState(() => _overlayVisible = true);
    _scheduleOverlayHide();
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.manager.call;
    if (call == null) return const SizedBox.shrink();
    final isVideoActive =
        widget.manager.isVideoEnabled && call.phase == CallPhase.active;
    final showLocalPreview =
        widget.manager.isVideoEnabled &&
        call.phase != CallPhase.ringingIncoming &&
        call.phase != CallPhase.ending;
    return Material(
      color: const Color(0xFF0B0F14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isLandscape = constraints.maxWidth > constraints.maxHeight;
          final showOverlay = !isVideoActive || _overlayVisible;
          return Stack(
            fit: StackFit.expand,
            children: [
              _backdrop(call, isVideoActive),
              GestureDetector(
                key: const Key('callSurfaceTap'),
                behavior: HitTestBehavior.opaque,
                onTap: _keepOverlayVisible,
              ),
              IgnorePointer(
                ignoring: !showOverlay,
                child: AnimatedOpacity(
                  key: const Key('callControlsOverlay'),
                  opacity: showOverlay ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _overlayScrim(isVideoActive),
                      if (showLocalPreview) _localPreview(isLandscape),
                      if (showLocalPreview &&
                          (Platform.isAndroid || Platform.isIOS))
                        Positioned(
                          top: isLandscape ? 16 : 54,
                          left: isLandscape ? 24 : 16,
                          child: _flipCameraButton(),
                        ),
                      _callChrome(call, isVideoActive, isLandscape),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _callChrome(ActiveCall call, bool isVideoActive, bool isLandscape) {
    if (isLandscape && !isVideoActive) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Expanded(
                key: const Key('callIdentityPanel'),
                flex: 6,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _header(call, compact: false),
                      if (call.phase == CallPhase.active &&
                          call.emojis.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 18),
                          child: _secureRow(call.emojis),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                key: const Key('callControlsPanel'),
                flex: 5,
                child: Center(child: _controls(call, horizontal: true)),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: Column(
        children: [
          SizedBox(height: isVideoActive ? (isLandscape ? 8 : 12) : 56),
          _header(call, compact: isVideoActive),
          if (!isVideoActive &&
              call.phase == CallPhase.active &&
              call.emojis.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: _secureRow(call.emojis),
            ),
          const Spacer(),
          Padding(
            padding: EdgeInsets.only(bottom: isLandscape ? 12 : 40, top: 12),
            child: _controls(call, horizontal: isLandscape),
          ),
        ],
      ),
    );
  }

  /// the reference app's blurred-avatar backdrop (falls back to a dark gradient). For an active
  /// video call this is the (placeholder) remote feed area.
  Widget _backdrop(ActiveCall call, bool isVideoActive) {
    final hasPhoto = call.peerPhoto != null;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasPhoto)
          // Boundary outside the filter: every manager notification repaints
          // this screen, and without it the full-viewport gaussian is rastered
          // again on each one instead of being re-composited.
          RepaintBoundary(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
              child: TDImage(photo: call.peerPhoto, cornerRadius: 0),
            ),
          )
        else
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF20303F), Color(0xFF0B0F14)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        // Remote camera feed — fills the screen over the
        // blurred-avatar fallback once decoded frames arrive (black until then).
        if (isVideoActive && (Platform.isAndroid || Platform.isIOS))
          _nativeVideoView('remote'),
      ],
    );
  }

  Widget _overlayScrim(bool isVideoActive) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.black.withValues(alpha: isVideoActive ? 0.35 : 0.45),
            Colors.black.withValues(alpha: isVideoActive ? 0.55 : 0.7),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    );
  }

  Widget _localPreview(bool isLandscape) {
    // Show our own camera feed when it's on; otherwise a placeholder glyph.
    final showVideo =
        (Platform.isAndroid || Platform.isIOS) && widget.manager.isVideoEnabled;
    return Positioned(
      top: 56,
      right: isLandscape ? 24 : 16,
      child: Container(
        key: const Key('callLocalPreview'),
        width: isLandscape ? 132 : 96,
        height: isLandscape ? 96 : 132,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: showVideo
            ? _nativeVideoView('local')
            : Center(
                child: AppIcon(
                  HeroAppIcons.video,
                  color: Colors.white.withValues(alpha: 0.5),
                  size: 26,
                ),
              ),
      ),
    );
  }

  Widget _nativeVideoView(String role) {
    const creationParamsCodec = StandardMessageCodec();
    final creationParams = {'role': role};
    if (Platform.isIOS) {
      return UiKitView(
        viewType: 'mithka/video_view',
        creationParams: creationParams,
        creationParamsCodec: creationParamsCodec,
      );
    }
    return AndroidView(
      viewType: 'mithka/video_view',
      creationParams: creationParams,
      creationParamsCodec: creationParamsCodec,
    );
  }

  Widget _flipCameraButton() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _keepOverlayVisible();
        widget.manager.switchCamera();
      },
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: const AppIcon(
          HeroAppIcons.rotate,
          size: 22,
          color: Colors.white,
        ),
      ),
    );
  }

  /// Transform the current call between voice and video without reconnecting.
  /// Re-enabling video keeps the lens the user last selected; the adjacent
  /// rotate control remains available while video is active.
  void _onCameraToggle() {
    _keepOverlayVisible();
    final m = widget.manager;
    if (m.isVideoEnabled) {
      m.disableVideo();
    } else {
      m.enableVideo(m.useFrontCamera);
    }
  }

  Widget _header(ActiveCall call, {required bool compact}) {
    final name = Text(
      call.peerName.isEmpty ? ' ' : call.peerName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: compact ? 18 : 26,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    );
    final status = _statusLine(
      call,
      TextStyle(
        fontSize: compact ? 13 : 15,
        color: Colors.white.withValues(alpha: 0.75),
      ),
    );
    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(children: [name, const SizedBox(height: 4), status]),
      );
    }
    return Column(
      children: [
        PhotoAvatar(
          title: call.peerName,
          photo: call.peerPhoto,
          size: 104,
          square: true,
        ),
        const SizedBox(height: 18),
        name,
        const SizedBox(height: 8),
        status,
      ],
    );
  }

  Widget _statusLine(ActiveCall call, TextStyle style) {
    final text = switch (call.phase) {
      CallPhase.requesting || CallPhase.ringingOutgoing => AppStrings.t(
        AppStringKeys.callWaitingForInviteAccept,
      ),
      CallPhase.ringingIncoming =>
        AppStrings.t(AppStringKeys.callIncomingCallInvite, {
          'value1': AppStrings.t(
            call.isVideo
                ? AppStringKeys.sharedMediaVideos
                : AppStringKeys.sharedMediaVoice,
          ),
        }),
      CallPhase.exchangingKeys => AppStrings.t(AppStringKeys.callConnecting),
      // The elapsed time is the only line that changes on its own; it owns the
      // 1 Hz tick so the rest of the call screen isn't relaid out every second.
      CallPhase.active => null,
      CallPhase.ending => AppStrings.t(AppStringKeys.callEnded),
    };
    if (text == null) {
      return _CallDuration(startedAt: call.startedAt, style: style);
    }
    return Text(text, style: style);
  }

  Widget _secureRow(List<String> emojis) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in emojis.take(4))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Text(e, style: const TextStyle(fontSize: 22)),
            ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              AppStrings.t(AppStringKeys.callEndToEndEncrypted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls(ActiveCall call, {bool horizontal = false}) {
    final m = widget.manager;
    if (call.phase == CallPhase.ringingIncoming) {
      if (!m.supportsMediaCalls) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                AppStrings.t(AppStringKeys.callsUnavailableOnDesktop),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: Colors.white.withValues(alpha: 0.72),
                ),
              ),
            ),
            const SizedBox(height: 18),
            _CallButton(
              icon: HeroAppIcons.phoneSlash,
              label: AppStrings.t(AppStringKeys.callDecline),
              background: const Color(0xFFFF3B30),
              onTap: m.end,
            ),
          ],
        );
      }
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _CallButton(
            icon: HeroAppIcons.phoneSlash,
            label: AppStrings.t(AppStringKeys.callDecline),
            background: const Color(0xFFFF3B30),
            onTap: m.end,
          ),
          _CallButton(
            icon: call.isVideo ? HeroAppIcons.video : HeroAppIcons.phone,
            label: AppStrings.t(AppStringKeys.callAccept),
            background: const Color(0xFF07C160),
            onTap: m.accept,
          ),
        ],
      );
    }
    List<Widget> buildToggles(double slotWidth, {required bool compact}) {
      return [
        _CallControlSlot(
          key: const Key('callControlMute'),
          width: slotWidth,
          child: _CallToggle(
            icon: m.isMuted
                ? HeroAppIcons.microphoneSlash
                : HeroAppIcons.microphone,
            label: AppStrings.t(AppStringKeys.callMute),
            isOn: m.isMuted,
            compact: compact,
            onTap: () {
              _keepOverlayVisible();
              m.toggleMute();
            },
          ),
        ),
        _CallControlSlot(
          key: const Key('callControlCamera'),
          width: slotWidth,
          child: _CallToggle(
            icon: HeroAppIcons.video,
            label: AppStrings.t(
              m.isVideoEnabled
                  ? AppStringKeys.callDisableVideo
                  : AppStringKeys.callEnableVideo,
            ),
            isOn: m.isVideoEnabled,
            compact: compact,
            onTap: _onCameraToggle,
          ),
        ),
        _CallControlSlot(
          key: const Key('callControlSpeaker'),
          width: slotWidth,
          child: _CallToggle(
            icon: HeroAppIcons.volumeHigh,
            label: AppStrings.t(AppStringKeys.callSpeakerphone),
            isOn: m.isSpeaker,
            compact: compact,
            onTap: () {
              _keepOverlayVisible();
              m.toggleSpeaker();
            },
          ),
        ),
      ];
    }

    Widget buildHangUp({required bool compact}) => _CallButton(
      key: const Key('callControlHangup'),
      icon: HeroAppIcons.phoneSlash,
      label: AppStrings.t(AppStringKeys.callHangUp),
      background: const Color(0xFFFF3B30),
      size: compact ? 56 : 66,
      compact: compact,
      onTap: m.end,
    );

    if (horizontal) {
      const itemCount = 4;
      return LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : itemCount * 80.0;
          final slotWidth = (availableWidth / itemCount)
              .clamp(64.0, 80.0)
              .toDouble();
          return Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ...buildToggles(slotWidth, compact: true),
                SizedBox(
                  width: slotWidth,
                  child: Center(child: buildHangUp(compact: true)),
                ),
              ],
            ),
          );
        },
      );
    }

    final toggles = buildToggles(104, compact: false);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: toggles,
        ),
        const SizedBox(height: 30),
        buildHangUp(compact: false),
      ],
    );
  }
}

/// Elapsed call time, ticking on its own. Keeping the timer here instead of on
/// the screen state is what stops the 1 Hz tick from rebuilding the video
/// platform views, the scrim and every control once a second for the whole call.
class _CallDuration extends StatefulWidget {
  const _CallDuration({required this.startedAt, required this.style});

  final DateTime? startedAt;
  final TextStyle style;

  @override
  State<_CallDuration> createState() => _CallDurationState();
}

class _CallDurationState extends State<_CallDuration> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _CallDuration oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startedAt != widget.startedAt) _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _syncTicker() {
    _ticker?.cancel();
    _ticker = null;
    if (widget.startedAt == null) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final startedAt = widget.startedAt;
    final elapsed = startedAt == null
        ? 0
        : DateTime.now().difference(startedAt).inSeconds;
    final s = elapsed < 0 ? 0 : elapsed;
    return Text(
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}',
      style: widget.style,
    );
  }
}

class _CallControlSlot extends StatelessWidget {
  const _CallControlSlot({super.key, required this.child, this.width = 104});

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Center(child: child),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    super.key,
    required this.icon,
    required this.label,
    required this.background,
    this.size = 68,
    this.compact = false,
    required this.onTap,
  });
  final AppIconData icon;
  final String label;
  final Color background;
  final double size;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppInteractiveSurface(
          semanticLabel: label,
          onTap: onTap,
          borderRadius: BorderRadius.circular(size / 2),
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
            ),
            child: AppIcon(icon, size: size * 0.42, color: Colors.white),
          ),
        ),
        const SizedBox(height: 10),
        ExcludeSemantics(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 11 : 13,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ),
      ],
    );
  }
}

/// custom frosted translucent toggle (white when active). `hidden` keeps the
/// row balanced by reserving the slot without drawing the control.
class _CallToggle extends StatelessWidget {
  const _CallToggle({
    required this.icon,
    required this.label,
    required this.isOn,
    this.compact = false,
    required this.onTap,
  });
  final AppIconData icon;
  final String label;
  final bool isOn;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppInteractiveSurface(
          semanticLabel: label,
          toggled: isOn,
          onTap: onTap,
          borderRadius: BorderRadius.circular((compact ? 52 : 60) / 2),
          child: Container(
            width: compact ? 52 : 60,
            height: compact ? 52 : 60,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isOn ? Colors.white : Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: AppIcon(
              icon,
              size: compact ? 22 : 24,
              color: isOn ? Colors.black : Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 10),
        ExcludeSemantics(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 11 : 13,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ),
      ],
    );
  }
}
