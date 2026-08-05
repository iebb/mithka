import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../theme/app_theme.dart';
import 'notification_controller.dart';

class InAppNotificationBannerHost extends StatelessWidget {
  const InAppNotificationBannerHost({super.key, required this.controller});

  final NotificationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final banner = controller.inAppBanner;
        final media = MediaQuery.of(context);
        final width = math.min(media.size.width - 20, 560.0);
        return IgnorePointer(
          ignoring: banner == null,
          child: Stack(
            children: [
              Positioned(
                top: media.padding.top + 7,
                left: (media.size.width - width) / 2,
                width: width,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 210),
                  reverseDuration: const Duration(milliseconds: 170),
                  transitionBuilder: (child, animation) {
                    final curved = CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                      reverseCurve: Curves.easeInCubic,
                    );
                    return FadeTransition(
                      opacity: curved,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, -0.35),
                          end: Offset.zero,
                        ).animate(curved),
                        child: child,
                      ),
                    );
                  },
                  child: banner == null
                      ? const SizedBox.shrink(key: ValueKey('empty'))
                      : _InAppNotificationCard(
                          key: ValueKey(banner.key),
                          banner: banner,
                          onOpen: controller.openInAppBanner,
                          onDismiss: controller.dismissInAppBanner,
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InAppNotificationCard extends StatefulWidget {
  const _InAppNotificationCard({
    super.key,
    required this.banner,
    required this.onOpen,
    required this.onDismiss,
  });

  final InAppNotificationBannerData banner;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  State<_InAppNotificationCard> createState() => _InAppNotificationCardState();
}

class _InAppNotificationCardState extends State<_InAppNotificationCard> {
  double _dragY = 0;

  void _updateDrag(DragUpdateDetails details) {
    setState(() => _dragY = math.min(0, _dragY + details.delta.dy));
  }

  void _finishDrag(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_dragY <= -30 || velocity <= -260) {
      widget.onDismiss();
      return;
    }
    setState(() => _dragY = 0);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final banner = widget.banner;
    return Semantics(
      button: true,
      label: '${banner.title}. ${banner.body}',
      onTap: widget.onOpen,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onOpen,
        onVerticalDragUpdate: _updateDrag,
        onVerticalDragEnd: _finishDrag,
        onVerticalDragCancel: () => setState(() => _dragY = 0),
        child: AnimatedContainer(
          duration: _dragY == 0
              ? const Duration(milliseconds: 150)
              : Duration.zero,
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _dragY, 0),
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
            color: c.card.withValues(alpha: 0.97),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: c.divider.withValues(alpha: 0.8)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x35000000),
                blurRadius: 18,
                offset: Offset(0, 7),
              ),
            ],
          ),
          child: Row(
            children: [
              PhotoAvatar(
                title: banner.title,
                photo: banner.photo,
                size: 44,
                square: banner.squarePhoto,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      banner.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 15,
                        height: 1.18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      banner.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 13,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              AppIcon(
                HeroAppIcons.chevronRight,
                size: 16,
                color: c.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
