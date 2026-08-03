//
//  ui_components.dart
//
//  Reusable reference-styled building blocks. People use circular avatars;
//  groups use rounded squares. Bubbles have a small tail. Port of the Swift
//  `UIComponents` (NavHeader, badges, dividers, separators, bubble shape).
//

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../platform/adaptive_platform.dart';
import '../platform/system_ui.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import '../theme/theme_controller.dart';
import 'app_icons.dart';
import 'app_interactive_surface.dart';

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
  final AppIconData? trailingIcon;
  final VoidCallback? onTrailing;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final metrics = context.watch<ThemeController>();
    final pointerDense = isDesktopTargetPlatform();
    final headerHeight = metrics.navHeaderHeight;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemUiOverlayStyleForSurface(c.navBar),
      child: Container(
        constraints: BoxConstraints(
          minHeight: headerHeight + MediaQuery.of(context).padding.top,
        ),
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
                AppInteractiveSurface(
                  semanticLabel: AppStringKeys.navigationBack.l10n(context),
                  onTap: onBack,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: pointerDense ? AppSpacing.md : AppSpacing.lg,
                    ),
                    child: AppIcon(
                      HeroAppIcons.chevronLeft,
                      size: metrics.scaled(
                        pointerDense ? AppIconSize.lg : AppIconSize.nav,
                      ),
                      color: c.textPrimary,
                    ),
                  ),
                ),
              Expanded(
                child: Text(
                  title.l10n(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: pointerDense
                      ? AppTextStyle.bodyLarge(
                          c.textPrimary,
                          weight: AppTextWeight.medium,
                        )
                      : AppTextStyle.title(c.textPrimary),
                ),
              ),
              ?trailing,
              if (trailing == null && trailingIcon != null)
                AppInteractiveSurface(
                  semanticLabel: title.l10n(context),
                  onTap: onTrailing,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    child: AppIcon(
                      trailingIcon!,
                      size: metrics.scaled(
                        pointerDense ? AppIconSize.lg : AppIconSize.nav - 1,
                      ),
                      color: c.textPrimary,
                    ),
                  ),
                ),
            ],
          ),
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
    final onClear = widget.onClear;
    if (onClear != null && _dragOffset.distance >= _breakDistance) {
      setState(() {
        _dragging = false;
        _broken = true;
      });
      onClear();
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

/// Group role tag: owner = yellow, admin = teal, member = purple, channel = pink.
class RoleTag extends StatelessWidget {
  const RoleTag({
    super.key,
    required this.role,
    this.title,
    this.connectedToTrailing = false,
    this.fontSize,
  });
  final MemberRole role;
  final String? title;
  final bool connectedToTrailing;
  final double? fontSize;

  Color get _color => switch (role) {
    MemberRole.owner => const Color(0xFFFFB300),
    MemberRole.admin => const Color(0xFF16B0A0),
    MemberRole.member => const Color(0xFF9B7BE8),
    MemberRole.channel => const Color(0xFFE85D9E),
  };

  String get _label {
    if (title != null && title!.isNotEmpty) return title!;
    return switch (role) {
      MemberRole.owner => AppStrings.t(AppStringKeys.commonUiGroupOwner),
      MemberRole.admin => AppStrings.t(AppStringKeys.groupManagementLogAdmin),
      MemberRole.member => AppStrings.t(AppStringKeys.groupManagementMembers),
      MemberRole.channel => AppStrings.t(AppStringKeys.tabChannels),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: connectedToTrailing
          ? const ValueKey('connectedSenderRoleTag')
          : null,
      padding: connectedToTrailing
          ? const EdgeInsets.symmetric(horizontal: 5, vertical: 2)
          : const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs + 1,
              vertical: 1.5,
            ),
      decoration: BoxDecoration(
        color: _color,
        borderRadius: connectedToTrailing
            ? const BorderRadiusDirectional.only(
                topStart: Radius.circular(8),
                bottomStart: Radius.circular(8),
              )
            : BorderRadius.circular(AppRadius.sm),
        boxShadow: connectedToTrailing
            ? const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 5,
                  offset: Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Text(
        _label.l10n(context),
        style: AppTextStyle.tiny(
          Colors.white,
          weight: AppTextWeight.medium,
        ).copyWith(fontSize: fontSize),
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

/// Colored settings glyph tile used by the main settings list and nested
/// settings menus. The 28 px tile has a 7 px radius and a centered 15 px white
/// glyph, including on yellow and other light backgrounds.
class SettingsIconTile extends StatelessWidget {
  const SettingsIconTile({
    super.key,
    required this.icon,
    required this.backgroundColor,
    this.size = 28,
    this.iconSize = 15,
    this.radius = 7,
  });

  final AppIconData icon;
  final Color backgroundColor;
  final double size;
  final double iconSize;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final pointerDense = isDesktopTargetPlatform();
    final effectiveSize = pointerDense && size == 28 ? 24.0 : size;
    final effectiveIconSize = pointerDense && iconSize == 15 ? 13.0 : iconSize;
    final effectiveRadius = pointerDense && radius == 7 ? 6.0 : radius;
    return Container(
      width: effectiveSize,
      height: effectiveSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(effectiveRadius),
      ),
      child: AppIcon(
        icon,
        size: effectiveIconSize,
        color: const Color(0xFFFFFFFF),
      ),
    );
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
    final pointerDense = isDesktopTargetPlatform();
    final effectiveHeight =
        pointerDense && height >= AppMetric.compactSettingsRowHeight
        ? 42.0
        : height;
    final effectiveLeadingInset =
        pointerDense && leadingInset == AppMetric.settingsLeadingInset
        ? AppSpacing.lg
        : leadingInset;
    final horizontalGap = pointerDense ? AppSpacing.md : AppSpacing.lg;
    final verticalPadding = pointerDense ? AppSpacing.sm : AppSpacing.md;
    final trailingSwitch = trailing is AppSwitch
        ? trailing! as AppSwitch
        : null;
    return AppInteractiveSurface(
      onTap: onTap,
      toggled: onTap == null ? null : trailingSwitch?.value,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: effectiveHeight),
        child: Padding(
          padding: EdgeInsets.only(
            left: effectiveLeadingInset,
            top: verticalPadding,
            right: pointerDense
                ? AppSpacing.lg
                : AppMetric.settingsTrailingInset,
            bottom: verticalPadding,
          ),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                SizedBox(width: horizontalGap),
              ],
              Expanded(
                flex: trailing == null && value.isNotEmpty ? 3 : 1,
                child: Text(
                  title.l10n(context),
                  style: pointerDense
                      ? AppTextStyle.callout(c.textPrimary)
                      : AppTextStyle.body(c.textPrimary),
                ),
              ),
              if (trailing != null || value.isNotEmpty) ...[
                SizedBox(width: horizontalGap),
                if (trailing != null)
                  onTap == null
                      ? trailing!
                      : ExcludeSemantics(
                          child: ExcludeFocus(
                            child: IgnorePointer(child: trailing!),
                          ),
                        )
                else
                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 190),
                        child: Text(
                          value.l10n(context),
                          textAlign: TextAlign.right,
                          style: pointerDense
                              ? AppTextStyle.caption(c.textTertiary)
                              : AppTextStyle.footnote(c.textTertiary),
                        ),
                      ),
                    ),
                  ),
              ],
              if (showChevron) ...[
                SizedBox(width: pointerDense ? AppSpacing.sm : AppSpacing.md),
                AppIcon(
                  HeroAppIcons.chevronRight,
                  size: pointerDense ? AppIconSize.sm : AppIconSize.chevron,
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

/// Project-native switch used instead of Material/Cupertino controls.
class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pointerDense = isDesktopTargetPlatform();
    final width = pointerDense ? 38.0 : 50.0;
    final height = pointerDense ? 22.0 : 30.0;
    final padding = pointerDense ? 2.0 : 2.0;
    final handleSize = pointerDense ? 18.0 : 26.0;
    final trackColor = value ? c.linkBlue : c.textTertiary;
    final handleColor = value ? c.onAccent : const Color(0xFFFFFFFF);
    return AppInteractiveSurface(
      semanticLabel:
          semanticLabel ??
          AppStrings.t(
            value
                ? AppStringKeys.privacyEnabled
                : AppStringKeys.privacyDisabled,
          ),
      toggled: value,
      onTap: enabled ? () => onChanged(!value) : null,
      enabled: enabled,
      borderRadius: BorderRadius.circular(height / 2),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: enabled ? 1 : 0.45,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: width,
          height: height,
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: trackColor,
            borderRadius: BorderRadius.circular(height / 2),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: handleSize,
              height: handleSize,
              decoration: BoxDecoration(
                color: handleColor,
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x30000000),
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Owned square selection control used where a persistent opt-in must be
/// explicit. It intentionally does not inherit platform checkbox styling.
class AppCheckbox extends StatelessWidget {
  const AppCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.size = 22,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final foreground = enabled ? c.textPrimary : c.textTertiary;
    return AppInteractiveSurface(
      checked: value,
      onTap: enabled ? () => onChanged(!value) : null,
      enabled: enabled,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1 : 0.42,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: value ? AppTheme.brand : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: value ? AppTheme.brand : foreground,
              width: 1.6,
            ),
          ),
          child: value
              ? AppIcon(
                  HeroAppIcons.check,
                  size: size * 0.62,
                  color: const Color(0xFFFFFFFF),
                )
              : null,
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
    final pointerDense = isDesktopTargetPlatform();
    final effectiveHeight =
        pointerDense && height >= AppMetric.compactSettingsRowHeight
        ? 42.0
        : height;
    final effectiveLeadingInset =
        pointerDense && leadingInset == AppMetric.settingsLeadingInset
        ? AppSpacing.lg
        : leadingInset;
    final horizontalGap = pointerDense ? AppSpacing.md : AppSpacing.lg;
    final verticalPadding = pointerDense ? AppSpacing.sm : AppSpacing.md;
    return AppInteractiveSurface(
      toggled: value,
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: effectiveHeight),
        child: Padding(
          padding: EdgeInsets.only(
            left: effectiveLeadingInset,
            top: verticalPadding,
            right: pointerDense
                ? AppSpacing.lg
                : AppMetric.settingsTrailingInset,
            bottom: verticalPadding,
          ),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                SizedBox(width: horizontalGap),
              ],
              Expanded(
                child: Text(
                  title.l10n(context),
                  style: pointerDense
                      ? AppTextStyle.callout(c.textPrimary)
                      : AppTextStyle.body(c.textPrimary),
                ),
              ),
              SizedBox(width: horizontalGap),
              ExcludeSemantics(
                child: ExcludeFocus(
                  child: IgnorePointer(
                    child: AppSwitch(value: value, onChanged: onChanged),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Project-owned activity glyph used instead of platform-styled progress
/// indicators.
class AppActivityIndicator extends StatefulWidget {
  const AppActivityIndicator({super.key, this.size = 26, this.color});

  final double size;
  final Color? color;

  @override
  State<AppActivityIndicator> createState() => _AppActivityIndicatorState();
}

class _AppActivityIndicatorState extends State<AppActivityIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: AppStrings.t(AppStringKeys.topicChatLoading),
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.rotate(
        angle: _controller.value * math.pi * 2,
        child: child,
      ),
      child: AppIcon(
        HeroAppIcons.arrowsRotate,
        size: widget.size,
        color: widget.color ?? context.colors.linkBlue,
      ),
    ),
  );
}

/// Project-owned determinate progress track.
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({super.key, required this.value, this.height = 3});

  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    final progress = value.clamp(0.0, 1.0);
    return Semantics(
      value: '${(progress * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(color: context.colors.divider),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  width: constraints.maxWidth * progress,
                  color: context.colors.linkBlue,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Project-owned single-value scrubber.
class AppValueScrubber extends StatelessWidget {
  const AppValueScrubber({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final range = math.max(0.000001, max - min);
      final progress = ((value - min) / range).clamp(0.0, 1.0);
      void update(double dx) =>
          onChanged(min + (dx / constraints.maxWidth).clamp(0.0, 1.0) * range);
      return Semantics(
        slider: true,
        value: '${(progress * 100).round()}%',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (event) => update(event.localPosition.dx),
          onHorizontalDragUpdate: (event) => update(event.localPosition.dx),
          child: SizedBox(
            height: 34,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.colors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  width: constraints.maxWidth * progress,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.colors.linkBlue,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Positioned(
                  left: constraints.maxWidth * progress - 9,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: context.colors.linkBlue,
                      shape: BoxShape.circle,
                      border: Border.all(color: context.colors.card, width: 2),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x28000000),
                          blurRadius: 4,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Project-owned two-thumb scrubber for lossless trim bounds.
class AppRangeScrubber extends StatefulWidget {
  const AppRangeScrubber({
    super.key,
    required this.start,
    required this.end,
    required this.min,
    required this.max,
    required this.onChanged,
    this.minimumGap = 0,
  });

  final double start;
  final double end;
  final double min;
  final double max;
  final double minimumGap;
  final void Function(double start, double end) onChanged;

  @override
  State<AppRangeScrubber> createState() => _AppRangeScrubberState();
}

class _AppRangeScrubberState extends State<AppRangeScrubber> {
  bool _movesStart = false;

  void _selectThumb(double value) {
    _movesStart = (value - widget.start).abs() <= (value - widget.end).abs();
  }

  void _update(double value) {
    if (_movesStart) {
      widget.onChanged(
        value.clamp(widget.min, widget.end - widget.minimumGap),
        widget.end,
      );
    } else {
      widget.onChanged(
        widget.start,
        value.clamp(widget.start + widget.minimumGap, widget.max),
      );
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final range = math.max(0.000001, widget.max - widget.min);
      final start = ((widget.start - widget.min) / range).clamp(0.0, 1.0);
      final end = ((widget.end - widget.min) / range).clamp(0.0, 1.0);
      double valueAt(double dx) =>
          widget.min + (dx / constraints.maxWidth).clamp(0.0, 1.0) * range;
      return Semantics(
        slider: true,
        value: '${(start * 100).round()}%–${(end * 100).round()}%',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (event) {
            final value = valueAt(event.localPosition.dx);
            _selectThumb(value);
            _update(value);
          },
          onHorizontalDragStart: (event) =>
              _selectThumb(valueAt(event.localPosition.dx)),
          onHorizontalDragUpdate: (event) =>
              _update(valueAt(event.localPosition.dx)),
          child: SizedBox(
            height: 36,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.colors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Positioned(
                  left: constraints.maxWidth * start,
                  width: constraints.maxWidth * (end - start),
                  child: Container(height: 4, color: context.colors.linkBlue),
                ),
                for (final progress in [start, end])
                  Positioned(
                    left: constraints.maxWidth * progress - 9,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: context.colors.linkBlue,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: context.colors.card,
                          width: 2,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x28000000),
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Centered gray timestamp separator in a conversation.
class TimeSeparator extends StatelessWidget {
  const TimeSeparator({super.key, required this.unix});
  final int unix;
  @override
  Widget build(BuildContext context) {
    final plate = servicePlateBackground(context.colors);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: plate,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Text(
            DateText.separatorLabel(unix),
            style: AppTextStyle.caption(servicePlateForeground(plate)),
          ),
        ),
      ),
    );
  }
}

/// Centered system/service banner (joins, pins, friendship notes).
class SystemBanner extends StatelessWidget {
  const SystemBanner({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final plate = servicePlateBackground(c);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: AppMetric.maxBannerWidth),
          padding: AppInsets.pill,
          decoration: BoxDecoration(
            color: plate,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: AppTextStyle.caption(servicePlateForeground(plate)),
          ),
        ),
      ),
    );
  }
}

/// Opaque semantic plate used for service events and date separators. Keeping
/// the plate opaque makes contrast deterministic even over bright or detailed
/// wallpapers.
Color servicePlateBackground(AppColors colors) =>
    colors.bubbleIncoming.withValues(alpha: 1);

Color servicePlateForeground(Color plate) => readableForeground(plate);

/// Chat-list preview: optional gray sender prefix + message, with a few "alert"
/// tags colored red.
class ChatPreviewText extends StatelessWidget {
  const ChatPreviewText({
    super.key,
    this.sender,
    required this.message,
    this.draft = false,
    this.alertPrefix,
    this.fontSize = AppTextSize.footnote,
  });
  final String? sender;
  final String message;
  final bool draft; // render a red "[草稿]" prefix and ignore sender
  final String? alertPrefix;
  final double fontSize;

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
    ).style.merge(TextStyle(fontSize: fontSize));
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: baseStyle,
        children: [
          if (!draft && alertPrefix != null && alertPrefix!.isNotEmpty)
            TextSpan(
              text: '${alertPrefix!.l10n(context)} ',
              style: TextStyle(color: AppTheme.tagRed),
            ),
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
