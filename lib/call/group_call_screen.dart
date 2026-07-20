import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import 'group_call_controller.dart';

class GroupCallScreen extends StatefulWidget {
  const GroupCallScreen({super.key, required this.controller});

  final GroupCallController controller;

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
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
    final session = widget.controller.session;
    if (session == null) return const SizedBox.shrink();
    final participants = widget.controller.participants;
    final hasVideo = participants.any((participant) => participant.hasVideo);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Material(
        color: const Color(0xFF101720),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _backdrop(participants),
            SafeArea(
              child: Column(
                children: [
                  _topBar(session.title, participants.length),
                  Expanded(
                    child: participants.isEmpty
                        ? _joiningState(session)
                        : _participantGrid(participants, hasVideo: hasVideo),
                  ),
                  _duration(session),
                  const SizedBox(height: 14),
                  _controls(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _backdrop(List<GroupCallParticipant> participants) {
    final photo = participants
        .where((participant) => participant.photo != null)
        .map((participant) => participant.photo)
        .firstOrNull;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (photo != null)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 42, sigmaY: 42),
            child: Transform.scale(
              scale: 1.18,
              child: TDImage(photo: photo, cornerRadius: 0),
            ),
          )
        else
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF526272), Color(0xFF111820)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0x8A22303D), Color(0xD90A0F14)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
    );
  }

  Widget _topBar(String title, int participantCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Row(
        children: [
          _GlassButton(
            icon: HeroAppIcons.pictureInPicture,
            tooltip: AppStrings.t(AppStringKeys.videoPlayerPictureInPicture),
            onTap: widget.controller.minimize,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (participantCount > 0)
                  Text(
                    '$participantCount',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.66),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _GlassButton(
            icon: HeroAppIcons.users,
            tooltip: AppStrings.t(AppStringKeys.chatInfoGroupMembers),
            onTap: _showParticipants,
          ),
          const SizedBox(width: 10),
          _GlassButton(
            key: const ValueKey('groupCallVideoToggle'),
            icon: HeroAppIcons.video,
            tooltip: AppStrings.t(
              widget.controller.isVideoEnabled
                  ? AppStringKeys.callDisableVideo
                  : AppStringKeys.callEnableVideo,
            ),
            onTap: () => widget.controller.setVideoEnabled(
              !widget.controller.isVideoEnabled,
              front: widget.controller.useFrontCamera,
            ),
          ),
          if (widget.controller.isVideoEnabled) ...[
            const SizedBox(width: 10),
            _GlassButton(
              icon: HeroAppIcons.rotate,
              tooltip: AppStrings.t(AppStringKeys.callCamera),
              onTap: widget.controller.switchCamera,
            ),
          ],
        ],
      ),
    );
  }

  Widget _joiningState(ActiveGroupCall session) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            AppStrings.t(AppStringKeys.callConnecting),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _participantGrid(
    List<GroupCallParticipant> participants, {
    required bool hasVideo,
  }) {
    if (!hasVideo) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430, maxHeight: 500),
          child: GridView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 12),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: participants.length == 1 ? 1 : 2,
              mainAxisExtent: 154,
              crossAxisSpacing: 22,
              mainAxisSpacing: 12,
            ),
            itemCount: participants.length,
            itemBuilder: (_, index) => _draggableParticipant(
              participants[index],
              compactVoiceTile: true,
            ),
          ),
        ),
      );
    }

    final columns = participants.length <= 2 ? 1 : 2;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: columns == 1 ? 1.18 : 0.78,
      ),
      itemCount: participants.length,
      itemBuilder: (_, index) => _draggableParticipant(participants[index]),
    );
  }

  Widget _draggableParticipant(
    GroupCallParticipant participant, {
    bool compactVoiceTile = false,
  }) {
    final tile = _ParticipantTile(
      participant: participant,
      controller: widget.controller,
      compactVoiceTile: compactVoiceTile,
    );
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != participant.key,
      onAcceptWithDetails: (details) {
        widget.controller.moveParticipant(details.data, participant.key);
      },
      builder: (context, candidates, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: candidates.isEmpty
              ? null
              : Border.all(color: Colors.white, width: 2),
        ),
        child: LongPressDraggable<String>(
          data: participant.key,
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(width: 170, height: 210, child: tile),
          ),
          childWhenDragging: Opacity(opacity: 0.34, child: tile),
          child: tile,
        ),
      ),
    );
  }

  Widget _duration(ActiveGroupCall session) {
    final startedAt = session.startedAt;
    final seconds = startedAt == null
        ? 0
        : DateTime.now().difference(startedAt).inSeconds.clamp(0, 359999);
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainder = seconds % 60;
    final text = hours > 0
        ? '${hours.toString().padLeft(2, '0')}:'
              '${minutes.toString().padLeft(2, '0')}:'
              '${remainder.toString().padLeft(2, '0')}'
        : '${minutes.toString().padLeft(2, '0')}:'
              '${remainder.toString().padLeft(2, '0')}';
    return Text(
      text,
      style: const TextStyle(color: Colors.white, fontSize: 17),
    );
  }

  Widget _controls() {
    final controller = widget.controller;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _SquareCallButton(
            icon: HeroAppIcons.bars,
            background: Colors.white.withValues(alpha: 0.26),
            onTap: _showParticipants,
          ),
          _SquareCallButton(
            icon: controller.isMuted
                ? HeroAppIcons.microphoneSlash
                : HeroAppIcons.microphone,
            background: controller.isMuted
                ? Colors.white.withValues(alpha: 0.28)
                : Colors.white,
            foreground: controller.isMuted ? Colors.white : Colors.black,
            onTap: controller.toggleMute,
          ),
          _SquareCallButton(
            icon: controller.isSpeaker
                ? HeroAppIcons.volumeHigh
                : HeroAppIcons.volumeXmark,
            background: controller.isSpeaker
                ? Colors.white
                : Colors.white.withValues(alpha: 0.28),
            foreground: controller.isSpeaker ? Colors.black : Colors.white,
            onTap: controller.toggleSpeaker,
          ),
          _SquareCallButton(
            icon: HeroAppIcons.phoneSlash,
            background: const Color(0xFFFF3851),
            onTap: controller.end,
          ),
        ],
      ),
    );
  }

  void _showParticipants() {
    final participants = widget.controller.participants;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF202A34),
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
          itemCount: participants.length,
          separatorBuilder: (_, _) =>
              Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
          itemBuilder: (_, index) {
            final participant = participants[index];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: PhotoAvatar(
                title: participant.name,
                photo: participant.photo,
                size: 42,
              ),
              title: Text(
                participant.name,
                style: const TextStyle(color: Colors.white),
              ),
              trailing: AppIcon(
                participant.isMuted
                    ? HeroAppIcons.microphoneSlash
                    : HeroAppIcons.microphone,
                size: 19,
                color: participant.isSpeaking
                    ? const Color(0xFF31D17C)
                    : Colors.white.withValues(alpha: 0.55),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({
    required this.participant,
    required this.controller,
    required this.compactVoiceTile,
  });

  final GroupCallParticipant participant;
  final GroupCallController controller;
  final bool compactVoiceTile;

  @override
  Widget build(BuildContext context) {
    if (compactVoiceTile || !participant.hasVideo) {
      return _voiceTile();
    }
    final role = participant.isCurrentUser
        ? 'group:local'
        : 'group:${participant.videoEndpointId}';
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          if (Platform.isAndroid)
            AndroidView(
              viewType: 'mithka/video_view',
              creationParams: {'role': role},
              creationParamsCodec: const StandardMessageCodec(),
            )
          else if (Platform.isIOS)
            UiKitView(
              viewType: 'mithka/group_video_view',
              creationParams: {'role': role},
              creationParamsCodec: const StandardMessageCodec(),
            )
          else
            _voiceTile(),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.64),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.56, 1],
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 44,
            bottom: 11,
            child: Text(
              participant.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Positioned(right: 10, bottom: 9, child: _micBadge()),
        ],
      ),
    );
  }

  Widget _voiceTile() {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: compactVoiceTile
            ? Colors.transparent
            : Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: EdgeInsets.all(participant.isSpeaking ? 3 : 0),
                decoration: const BoxDecoration(
                  color: Color(0xFF31D17C),
                  shape: BoxShape.circle,
                ),
                child: PhotoAvatar(
                  title: participant.name,
                  photo: participant.photo,
                  size: compactVoiceTile ? 78 : 92,
                ),
              ),
              Positioned(right: -3, bottom: -3, child: _micBadge()),
            ],
          ),
          const SizedBox(height: 11),
          Text(
            participant.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _micBadge() {
    final active = participant.isSpeaking && !participant.isMuted;
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? const Color(0xFF31D17C) : const Color(0xFFFF5570),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
      ),
      child: AppIcon(
        participant.isMuted
            ? HeroAppIcons.microphoneSlash
            : HeroAppIcons.microphone,
        size: 15,
        color: Colors.white,
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final AppIconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(14),
          ),
          child: AppIcon(icon, size: 23, color: Colors.white),
        ),
      ),
    );
  }
}

class _SquareCallButton extends StatelessWidget {
  const _SquareCallButton({
    required this.icon,
    required this.background,
    required this.onTap,
    this.foreground = Colors.white,
  });

  final AppIconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 66,
        height: 66,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(21),
        ),
        child: AppIcon(icon, size: 29, color: foreground),
      ),
    );
  }
}
