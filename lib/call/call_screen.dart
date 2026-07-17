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

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/photo_avatar.dart'; // PhotoAvatar + TDImage
import 'call_manager.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.manager});
  final CallManager manager;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  Timer? _ticker;
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
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
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
    _ticker?.cancel();
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
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
            child: TDImage(photo: call.peerPhoto, cornerRadius: 0),
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
          borderRadius: BorderRadius.circular(12),
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

  /// 摄像头 toggle: turning the camera ON first asks which lens to use;
  /// turning it OFF is immediate.
  void _onCameraToggle({bool selectCamera = true}) {
    _keepOverlayVisible();
    final m = widget.manager;
    if (m.isVideoEnabled) {
      m.disableVideo();
    } else if (!selectCamera) {
      m.enableVideo(true);
    } else {
      _showCameraSelector();
    }
  }

  void _showCameraSelector() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheet) => CupertinoActionSheet(
        title: Text(AppStrings.t(AppStringKeys.callSelectCamera)),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(sheet).pop();
              widget.manager.enableVideo(true);
            },
            child: Text(AppStrings.t(AppStringKeys.callFrontCamera)),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(sheet).pop();
              widget.manager.enableVideo(false);
            },
            child: Text(AppStrings.t(AppStringKeys.callRearCamera)),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(sheet).pop(),
          child: Text(AppStrings.t(AppStringKeys.countryPickerCancel)),
        ),
      ),
    );
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
    final status = Text(
      _statusLine(call),
      style: TextStyle(
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

  String _statusLine(ActiveCall call) {
    switch (call.phase) {
      case CallPhase.requesting:
      case CallPhase.ringingOutgoing:
        return AppStrings.t(AppStringKeys.callWaitingForInviteAccept);
      case CallPhase.ringingIncoming:
        return AppStrings.t(AppStringKeys.callIncomingCallInvite, {
          'value1': AppStrings.t(
            call.isVideo
                ? AppStringKeys.sharedMediaVideos
                : AppStringKeys.sharedMediaVoice,
          ),
        });
      case CallPhase.exchangingKeys:
        return AppStrings.t(AppStringKeys.callConnecting);
      case CallPhase.active:
        return _durationText(call.startedAt);
      case CallPhase.ending:
        return AppStrings.t(AppStringKeys.callEnded);
    }
  }

  String _durationText(DateTime? startedAt) {
    if (startedAt == null) return '00:00';
    final e = DateTime.now().difference(startedAt).inSeconds;
    final s = e < 0 ? 0 : e;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Widget _secureRow(List<String> emojis) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
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
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _CallButton(
            icon: HeroAppIcons.phoneSlash.data,
            label: AppStrings.t(AppStringKeys.callDecline),
            background: const Color(0xFFFF3B30),
            onTap: m.end,
          ),
          _CallButton(
            icon: call.isVideo
                ? HeroAppIcons.video.data
                : HeroAppIcons.phone.data,
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
                ? HeroAppIcons.microphoneSlash.data
                : HeroAppIcons.microphone.data,
            label: AppStrings.t(AppStringKeys.callMute),
            isOn: m.isMuted,
            compact: compact,
            onTap: () {
              _keepOverlayVisible();
              m.toggleMute();
            },
          ),
        ),
        if (call.phase == CallPhase.active || call.isVideo)
          _CallControlSlot(
            key: const Key('callControlCamera'),
            width: slotWidth,
            child: _CallToggle(
              icon: HeroAppIcons.video.data,
              label: AppStrings.t(AppStringKeys.callCamera),
              isOn: m.isVideoEnabled,
              compact: compact,
              onTap: () => _onCameraToggle(selectCamera: !horizontal),
            ),
          ),
        _CallControlSlot(
          key: const Key('callControlSpeaker'),
          width: slotWidth,
          child: _CallToggle(
            icon: HeroAppIcons.volumeHigh.data,
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
      icon: HeroAppIcons.phoneSlash.data,
      label: AppStrings.t(AppStringKeys.callHangUp),
      background: const Color(0xFFFF3B30),
      size: compact ? 56 : 66,
      compact: compact,
      onTap: m.end,
    );

    if (horizontal) {
      final itemCount = (call.phase == CallPhase.active || call.isVideo)
          ? 4
          : 3;
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
  final IconData icon;
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
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: size * 0.42, color: Colors.white),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact ? 11 : 13,
            color: Colors.white.withValues(alpha: 0.85),
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
  final IconData icon;
  final String label;
  final bool isOn;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: compact ? 52 : 60,
            height: compact ? 52 : 60,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isOn ? Colors.white : Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: compact ? 22 : 24,
              color: isOn ? Colors.black : Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact ? 11 : 13,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }
}
