//
//  call_screen.dart
//
//  Full-screen 1:1 call UI driven by a `CallManager`, styled after QQ's voice /
//  video call screens: a blurred-avatar backdrop, a large rounded-square avatar
//  with name + status, the端到端 verification emojis, and a row of frosted
//  translucent controls (mute / speaker / camera) over a red 挂断 — with
//  green 接听 / red 拒绝 for an incoming call. Video calls fill the screen with
//  the remote feed and a small local preview (PiP).
//

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../components/photo_avatar.dart'; // PhotoAvatar + TDImage
import '../components/sf_symbols.dart';
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

  /// QQ's blurred-avatar backdrop (falls back to a dark gradient). For an active
  /// video call this is the (placeholder) remote feed area.
  Widget _backdrop(ActiveCall call, bool isVideoActive) {
    final hasPhoto = call.peerPhoto != null;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasPhoto)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
            child: TDImage(
              photo: call.peerPhoto,
              cornerRadius: 0,
              fit: BoxFit.cover,
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
    return Positioned(
      top: 56,
      right: 16,
      child: Container(
        width: 96,
        height: 132,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        alignment: Alignment.center,
        child: Icon(
          sfIcon('video.fill'),
          color: Colors.white.withValues(alpha: 0.5),
          size: 26,
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
        return '正在等待对方接受邀请…';
      case CallPhase.ringingIncoming:
        return '邀请你进行${call.isVideo ? "视频" : "语音"}通话';
      case CallPhase.exchangingKeys:
        return '连接中…';
      case CallPhase.active:
        return _durationText(call.startedAt);
      case CallPhase.ending:
        return '通话结束';
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
            '端到端加密',
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
            icon: 'phone.down.fill',
            label: '拒绝',
            background: const Color(0xFFFF3B30),
            onTap: m.end,
          ),
          _CallButton(
            icon: call.isVideo ? 'video.fill' : 'phone.fill',
            label: '接听',
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
              icon: m.isMuted ? 'mic.slash.fill' : 'mic.fill',
              label: '静音',
              isOn: m.isMuted,
              onTap: m.toggleMute,
            ),
            const SizedBox(width: 26),
            if (call.isVideo) ...[
              _CallToggle(
                icon: 'video.fill',
                label: '摄像头',
                isOn: m.isVideoEnabled,
                onTap: m.toggleVideo,
              ),
              const SizedBox(width: 26),
            ],
            _CallToggle(
              icon: 'speaker.wave.2.fill',
              label: '免提',
              isOn: m.isSpeaker,
              onTap: m.toggleSpeaker,
            ),
          ],
        ),
        const SizedBox(height: 30),
        _CallButton(
          icon: 'phone.down.fill',
          label: '挂断',
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
  final String icon;
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
            child: Icon(sfIcon(icon), size: size * 0.42, color: Colors.white),
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

/// QQ-style frosted translucent toggle (white when active). `hidden` keeps the
/// row balanced by reserving the slot without drawing the control.
class _CallToggle extends StatelessWidget {
  const _CallToggle({
    required this.icon,
    required this.label,
    required this.isOn,
    required this.onTap,
  });
  final String icon;
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
              sfIcon(icon),
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
