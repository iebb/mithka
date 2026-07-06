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

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.manager.call;
    if (call == null) return const SizedBox.shrink();
    final isVideoActive = call.isVideo && call.phase == CallPhase.active;
    return Material(
      color: const Color(0xFF0B0F14),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _backdrop(call, isVideoActive),
          // Local camera preview (PiP) during a video call.
          if (isVideoActive) _localPreview(),
          // Flip front/back camera while the camera is on.
          if (isVideoActive &&
              widget.manager.isVideoEnabled &&
              Platform.isAndroid)
            Positioned(top: 54, left: 16, child: _flipCameraButton()),
          SafeArea(
            child: Column(
              children: [
                SizedBox(height: isVideoActive ? 12 : 56),
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
                  padding: const EdgeInsets.only(bottom: 40, top: 12),
                  child: _controls(call),
                ),
              ],
            ),
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
        // Remote camera feed (Android/ntgcalls) — fills the screen over the
        // blurred-avatar fallback once decoded frames arrive (black until then).
        if (isVideoActive && Platform.isAndroid)
          const AndroidView(
            viewType: 'mithka/video_view',
            creationParams: {'role': 'remote'},
            creationParamsCodec: StandardMessageCodec(),
          ),
        // Darkening scrim so white text/controls stay legible.
        DecoratedBox(
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
        ),
      ],
    );
  }

  Widget _localPreview() {
    // Show our own camera feed when it's on; otherwise a placeholder glyph.
    final showVideo = Platform.isAndroid && widget.manager.isVideoEnabled;
    return Positioned(
      top: 56,
      right: 16,
      child: Container(
        width: 96,
        height: 132,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: showVideo
            ? const AndroidView(
                viewType: 'mithka/video_view',
                creationParams: {'role': 'local'},
                creationParamsCodec: StandardMessageCodec(),
              )
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

  Widget _flipCameraButton() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.manager.switchCamera,
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
  void _onCameraToggle() {
    final m = widget.manager;
    if (m.isVideoEnabled) {
      m.disableVideo();
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
          Text(
            AppStrings.t(AppStringKeys.callEndToEndEncrypted),
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls(ActiveCall call) {
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _CallToggle(
              icon: m.isMuted
                  ? HeroAppIcons.microphoneSlash.data
                  : HeroAppIcons.microphone.data,
              label: AppStrings.t(AppStringKeys.callMute),
              isOn: m.isMuted,
              onTap: m.toggleMute,
            ),
            const SizedBox(width: 26),
            if (call.isVideo) ...[
              _CallToggle(
                icon: HeroAppIcons.video.data,
                label: AppStrings.t(AppStringKeys.callCamera),
                isOn: m.isVideoEnabled,
                onTap: _onCameraToggle,
              ),
              const SizedBox(width: 26),
            ],
            _CallToggle(
              icon: HeroAppIcons.volumeHigh.data,
              label: AppStrings.t(AppStringKeys.callSpeakerphone),
              isOn: m.isSpeaker,
              onTap: m.toggleSpeaker,
            ),
          ],
        ),
        const SizedBox(height: 30),
        _CallButton(
          icon: HeroAppIcons.phoneSlash.data,
          label: AppStrings.t(AppStringKeys.callHangUp),
          background: const Color(0xFFFF3B30),
          size: 66,
          onTap: m.end,
        ),
      ],
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.icon,
    required this.label,
    required this.background,
    this.size = 68,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color background;
  final double size;
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
          style: TextStyle(
            fontSize: 13,
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
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool isOn;
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
            width: 60,
            height: 60,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isOn ? Colors.white : Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 24,
              color: isOn ? Colors.black : Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }
}
