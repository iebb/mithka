//
//  ui_components.dart
//
//  Reusable reference-styled building blocks. People use circular avatars;
//  groups use rounded squares. Bubbles have a small tail. Port of the Swift
//  `UIComponents` (NavHeader, badges, dividers, separators, bubble shape).
//

import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import '../theme/theme_controller.dart';
import 'app_icons.dart';

/// Flat reference-style header bar: optional back chevron, leading title,
/// optional trailing icon.
class NavHeader extends StatelessWidget {
  const NavHeader({
    super.key,
    required this.title,
    this.onBack,
    this.trailingIcon,
    this.onTrailing,
    this.trailing,
  });

  final String title;
  final VoidCallback? onBack;
  final IconData? trailingIcon;
  final VoidCallback? onTrailing;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final metrics = context.watch<ThemeController>();
    final headerHeight = metrics.navHeaderHeight;
    return Container(
      height: headerHeight + MediaQuery.of(context).padding.top,
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(
          bottom: BorderSide(color: c.divider, width: AppMetric.divider),
        ),
      ),
      child: Padding(
        padding: AppInsets.navHeader,
        child: Row(
          children: [
            if (onBack != null)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onBack,
                child: Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.lg),
                  child: AppIcon(
                    HeroAppIcons.chevronLeft,
                    size: metrics.scaled(AppIconSize.nav),
                    color: c.textPrimary,
                  ),
                ),
              ),
            Expanded(
              child: Text(
                title.l10n(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.title(c.textPrimary),
              ),
            ),
            ?trailing,
            if (trailing == null && trailingIcon != null)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTrailing,
                child: Icon(
                  trailingIcon!,
                  size: metrics.scaled(AppIconSize.nav - 1),
                  color: c.textPrimary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Unread-count pill. Muted/archived chats use the neutral gray variant.
class UnreadBadge extends StatefulWidget {
  const UnreadBadge({
    super.key,
    required this.count,
    this.muted = false,
    this.onClear,
  });
  final int count;
  final bool muted;
  final VoidCallback? onClear;

  @override
  State<UnreadBadge> createState() => _UnreadBadgeState();
}

class _UnreadBadgeState extends State<UnreadBadge> {
  static const _breakDistance = 46.0;
  Offset _dragOffset = Offset.zero;
  bool _dragging = false;
  bool _broken = false;

  Color _color(BuildContext context) =>
      widget.muted ? context.colors.textTertiary : AppTheme.unreadBadge;

  void _reset() {
    if (!mounted) return;
    setState(() {
      _dragging = false;
      _broken = false;
      _dragOffset = Offset.zero;
    });
  }

  void _finishDrag() {
    if (widget.onClear != null && _dragOffset.distance >= _breakDistance) {
      setState(() {
        _dragging = false;
        _broken = true;
      });
      widget.onClear!();
      Future<void>.delayed(const Duration(milliseconds: 180), _reset);
      return;
    }
    _reset();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.count <= 0 || _broken) return const SizedBox.shrink();
    final color = _color(context);
    final overflowMode = context
        .watch<ThemeController>()
        .unreadBadgeOverflowMode;
    final label = overflowMode.format(widget.count);
    final body = _UnreadBadgeBody(label: label, color: color);
    if (widget.onClear == null) return body;
    final visualSize = _visualSize(context, label);
    final hitWidth = math.max(AppMetric.hitTarget, visualSize.width);
    final origin = Offset(
      hitWidth - visualSize.width / 2,
      visualSize.height / 2,
    );

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => setState(() => _dragging = true),
      onPointerMove: (event) => setState(() => _dragOffset += event.delta),
      onPointerCancel: (_) => _reset(),
      onPointerUp: (_) => _finishDrag(),
      child: SizedBox(
        width: hitWidth,
        height: AppMetric.hitTarget,
        child: CustomPaint(
          painter: _UnreadBadgeMorphPainter(
            color: color,
            offset: _dragOffset,
            origin: origin,
            broken: _dragOffset.distance >= _breakDistance,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                right: 0,
                top: 0,
                child: Transform.translate(
                  offset: _dragOffset,
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 100),
                    scale: _dragging ? 1.06 : 1,
                    child: body,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Size _visualSize(BuildContext context, String label) {
    const style = TextStyle(
      fontSize: AppTextSize.caption,
      fontWeight: AppTextWeight.semibold,
    );
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final horizontalPadding = label.length > 1 ? (AppSpacing.xs + 1) * 2 : 0.0;
    return Size(
      math.max(AppMetric.unreadBadgeMin, painter.width + horizontalPadding),
      AppMetric.unreadBadgeMin,
    );
  }
}

class _UnreadBadgeBody extends StatelessWidget {
  const _UnreadBadgeBody({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        minWidth: AppMetric.unreadBadgeMin,
        minHeight: AppMetric.unreadBadgeMin,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: label.length > 1 ? AppSpacing.xs + 1 : 0,
      ),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppMetric.unreadBadgeMin / 2),
      ),
      child: Text(
        label,
        style: AppTextStyle.caption(
          Colors.white,
          weight: AppTextWeight.semibold,
        ),
      ),
    );
  }
}

class _UnreadBadgeMorphPainter extends CustomPainter {
  const _UnreadBadgeMorphPainter({
    required this.color,
    required this.offset,
    required this.origin,
    required this.broken,
  });

  final Color color;
  final Offset offset;
  final Offset origin;
  final bool broken;

  @override
  void paint(Canvas canvas, Size size) {
    final distance = offset.distance;
    if (broken || distance < 3 || size.isEmpty) return;

    final target = origin + offset;
    final progress = (distance / _UnreadBadgeState._breakDistance).clamp(
      0.0,
      1.0,
    );
    final width = math.max(
      6.0,
      AppMetric.unreadBadgeMin * (0.72 - progress * 0.36),
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;

    final normal = distance == 0
        ? Offset.zero
        : Offset(-offset.dy / distance, offset.dx / distance);
    final bend = normal * math.min(7.0, distance * 0.16);
    final path = Path()
      ..moveTo(origin.dx, origin.dy)
      ..quadraticBezierTo(
        origin.dx + offset.dx * 0.5 + bend.dx,
        origin.dy + offset.dy * 0.5 + bend.dy,
        target.dx,
        target.dy,
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _UnreadBadgeMorphPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.offset != offset ||
      oldDelegate.origin != origin ||
      oldDelegate.broken != broken;
}

/// Group role tag: owner = yellow, admin = teal, member = purple.
class RoleTag extends StatelessWidget {
  const RoleTag({super.key, required this.role, this.title});
  final MemberRole role;
  final String? title;

  Color get _color => switch (role) {
    MemberRole.owner => const Color(0xFFFFB300),
    MemberRole.admin => const Color(0xFF16B0A0),
    MemberRole.member => const Color(0xFF9B7BE8),
  };

  String get _label {
    if (title != null && title!.isNotEmpty) return title!;
    return switch (role) {
      MemberRole.owner => AppStrings.t(AppStringKeys.commonUiGroupOwner),
      MemberRole.admin => AppStrings.t(AppStringKeys.groupManagementLogAdmin),
      MemberRole.member => AppStrings.t(AppStringKeys.groupManagementMembers),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs + 1,
        vertical: 1.5,
      ),
      decoration: BoxDecoration(
        color: _color,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        _label.l10n(context),
        style: AppTextStyle.tiny(Colors.white, weight: AppTextWeight.medium),
      ),
    );
  }
}

/// Small solid dot (muted unread indicator / tab markers).
class RedDot extends StatelessWidget {
  const RedDot({super.key, this.size = 9, this.muted = false});
  final double size;
  final bool muted;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: muted ? context.colors.textTertiary : AppTheme.unreadBadge,
      shape: BoxShape.circle,
    ),
  );
}

/// Thin inset list divider.
class InsetDivider extends StatelessWidget {
  const InsetDivider({super.key, this.leadingInset = 76});
  final double leadingInset;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(left: leadingInset),
    child: Container(height: AppMetric.divider, color: context.colors.divider),
  );
}

/// Standard grouped settings card. Use this for left-label/right-value rows
/// instead of duplicating per-screen private `_settingsCard` variants.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children, this.margin});

  final List<Widget> children;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
    return margin == null ? card : Padding(padding: margin!, child: card);
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.value = '',
    this.leading,
    this.onTap,
    this.showChevron = true,
    this.height = AppMetric.settingsRowHeight,
    this.leadingInset = AppMetric.settingsLeadingInset,
    this.trailing,
  });

  final String title;
  final String value;
  final Widget? leading;
  final VoidCallback? onTap;
  final bool showChevron;
  final double height;
  final double leadingInset;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: EdgeInsets.only(
            left: leadingInset,
            right: AppMetric.settingsTrailingInset,
          ),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Text(
                title.l10n(context),
                style: AppTextStyle.body(c.textPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child:
                      trailing ??
                      Text(
                        value.l10n(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: AppTextStyle.footnote(c.textTertiary),
                      ),
                ),
              ),
              if (showChevron) ...[
                const SizedBox(width: 8),
                AppIcon(
                  HeroAppIcons.chevronRight,
                  size: AppIconSize.chevron,
                  color: c.textTertiary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.leading,
    this.height = AppMetric.settingsRowHeight,
    this.leadingInset = AppMetric.settingsLeadingInset,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget? leading;
  final double height;
  final double leadingInset;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: SizedBox(
        height: height,
        child: Padding(
          padding: EdgeInsets.only(
            left: leadingInset,
            right: AppMetric.settingsTrailingInset,
          ),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Text(
                title.l10n(context),
                style: AppTextStyle.body(c.textPrimary),
              ),
              const Spacer(),
              IgnorePointer(
                child: CupertinoSwitch(
                  value: value,
                  activeTrackColor: AppTheme.brand,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Centered gray timestamp separator in a conversation.
class TimeSeparator extends StatelessWidget {
  const TimeSeparator({super.key, required this.unix});
  final int unix;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Center(
      child: Text(
        DateText.separatorLabel(unix),
        style: AppTextStyle.caption(context.colors.textSecondary),
      ),
    ),
  );
}

/// Centered system/service banner (joins, pins, friendship notes).
class SystemBanner extends StatelessWidget {
  const SystemBanner({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: AppMetric.maxBannerWidth),
          padding: AppInsets.pill,
          decoration: BoxDecoration(
            color: c.textPrimary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: AppTextStyle.caption(c.textSecondary),
          ),
        ),
      ),
    );
  }
}

/// Chat-list preview: optional gray sender prefix + message, with a few "alert"
/// tags colored red.
class ChatPreviewText extends StatelessWidget {
  const ChatPreviewText({
    super.key,
    this.sender,
    required this.message,
    this.draft = false,
  });
  final String? sender;
  final String message;
  final bool draft; // render a red "[草稿]" prefix and ignore sender

  static const _redTags = [
    AppStringKeys.commonUiNewFileBadge,
    AppStringKeys.commonUiMentionedBySomeoneBadge,
    AppStringKeys.commonUiDraftBadge,
    AppStringKeys.commonUiMentionMeBadge,
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isRed = _redTags.any(message.startsWith);
    final baseStyle = DefaultTextStyle.of(
      context,
    ).style.merge(const TextStyle(fontSize: AppTextSize.footnote));
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: baseStyle,
        children: [
          if (draft)
            TextSpan(
              text: '${AppStringKeys.commonUiDraftBadge.l10n(context)} ',
              style: TextStyle(color: AppTheme.tagRed),
            )
          else if (sender != null && sender!.isNotEmpty)
            TextSpan(
              text: '$sender: ',
              style: TextStyle(color: c.textSecondary),
            ),
          TextSpan(
            text: _previewMessage(context),
            style: TextStyle(
              color: !draft && isRed ? AppTheme.tagRed : c.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  String _previewMessage(BuildContext context) {
    var text = message.replaceAll('\n', ' ');
    for (final tag in _redTags) {
      if (!text.startsWith(tag)) continue;
      text = text.replaceFirst(tag, tag.l10n(context));
      break;
    }
    return text;
  }
}
