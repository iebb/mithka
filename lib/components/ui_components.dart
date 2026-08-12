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
import 'desktop_content_constraint.dart';

/// Marks only the first route hosted by the settings split-detail pane.
///
/// Its first route is selected by the sidebar rather than pushed by history,
/// so a back control is invalid there. Routes subsequently pushed inside the
/// same navigator do not inherit this route-local marker and retain normal
/// back navigation. Keeping the marker inside the route also avoids mistaking
/// the Settings window's outer navigation history for detail-pane history.
class SettingsSplitPaneScope extends InheritedWidget {
  const SettingsSplitPaneScope({super.key, required super.child});

  static bool isRootRoute(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<SettingsSplitPaneScope>() !=
        null;
  }

  @override
  bool updateShouldNotify(SettingsSplitPaneScope oldWidget) => false;
}

/// Shared shell for every settings destination.
///
/// The header, grouped background and readable content lane are deliberately
/// owned here so a page cannot drift by rebuilding those three pieces. The
/// content lane is full-width on touch platforms and capped at 720 px on
/// native desktop; the child supplies its scroll behavior.
class SettingsPageScaffold extends StatelessWidget {
  const SettingsPageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.onBack,
    this.trailingIcon,
    this.onTrailing,
    this.trailing,
    this.constrainContent = true,
    this.showBackButton = true,
    this.resizeToAvoidBottomInset = true,
    this.bottomNavigationBar,
  });

  final String title;
  final Widget child;
  final VoidCallback? onBack;
  final AppIconData? trailingIcon;
  final VoidCallback? onTrailing;
  final Widget? trailing;

  /// Full-canvas utilities such as a camera scanner can opt out explicitly.
  final bool constrainContent;

  /// The shell still verifies navigator history before it renders the control.
  /// A settings destination embedded in the desktop split pane therefore has
  /// a title but no dead back chevron, while the same widget on a pushed mobile
  /// route gets its back action automatically.
  final bool showBackButton;
  final bool resizeToAvoidBottomInset;
  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) {
    final navigator = Navigator.maybeOf(context);
    final effectiveOnBack =
        showBackButton &&
            !SettingsSplitPaneScope.isRootRoute(context) &&
            (navigator?.canPop() ?? false)
        ? onBack ?? () => navigator!.pop()
        : null;
    final content = constrainContent
        ? DesktopContentConstraint(child: child)
        : child;
    return Scaffold(
      backgroundColor: context.colors.groupedBackground,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      bottomNavigationBar: bottomNavigationBar,
      body: Column(
        children: [
          NavHeader(
            title: title,
            onBack: effectiveOnBack,
            trailingIcon: trailingIcon,
            onTrailing: onTrailing,
            trailing: trailing,
          ),
          Expanded(child: content),
        ],
      ),
    );
  }
}

/// Canonical scrolling body for settings pages on every platform.
///
/// Page inset is intentionally not adaptive: mobile and desktop destinations
/// share the same 12 / 14 / 12 / 24 outer rhythm. Desktop adaptation happens
/// at the content-lane level in [SettingsPageScaffold].
class SettingsListView extends StatelessWidget {
  const SettingsListView({
    super.key,
    required this.children,
    this.controller,
    this.physics,
    this.padding = AppInsets.screen,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
  });

  final List<Widget> children;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final EdgeInsetsGeometry padding;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;

  @override
  Widget build(BuildContext context) => ListView(
    controller: controller,
    physics: physics,
    padding: padding,
    keyboardDismissBehavior: keyboardDismissBehavior,
    children: children,
  );
}

/// Project-owned search control shared by settings indexes and selectors.
///
/// It intentionally owns the glyphs, fill, radius, height and clear affordance
/// so platform search widgets cannot introduce a second icon set or padding.
class SettingsSearchField extends StatelessWidget {
  const SettingsSearchField({
    super.key,
    required this.hintText,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction = TextInputAction.search,
    this.compact = false,
  });

  final String hintText;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction textInputAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fontSize = compact ? 13.0 : AppTextSize.callout;
    final iconSize = compact ? 16.0 : AppMetric.searchIcon;
    final scaledLineHeight =
        MediaQuery.textScalerOf(context).scale(fontSize) * 1.25;
    final height = math.max(
      compact ? 34.0 : AppMetric.searchHeight,
      scaledLineHeight + AppSpacing.xxl,
    );
    final field = Container(
      key: const ValueKey('settings-search-container'),
      height: height,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.md : AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: c.searchFill,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        children: [
          AppIcon(
            HeroAppIcons.magnifyingGlass,
            size: iconSize,
            color: c.textTertiary,
          ),
          SizedBox(width: compact ? AppSpacing.sm : AppSpacing.md),
          Expanded(
            child: TextField(
              key: const ValueKey('settings-search-field'),
              controller: controller,
              focusNode: focusNode,
              textInputAction: textInputAction,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              style: TextStyle(fontSize: fontSize, color: c.textPrimary),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: hintText.l10n(context),
                hintStyle: TextStyle(fontSize: fontSize, color: c.textTertiary),
              ),
            ),
          ),
          if (controller != null)
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller!,
              builder: (context, value, _) => value.text.isEmpty
                  ? const SizedBox.shrink()
                  : AppInteractiveSurface(
                      semanticLabel: AppStringKeys.countryPickerCancel.l10n(
                        context,
                      ),
                      onTap: () {
                        controller!.clear();
                        onChanged?.call('');
                      },
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xs),
                        child: AppIcon(
                          HeroAppIcons.xmark,
                          size: AppIconSize.md,
                          color: c.textTertiary,
                        ),
                      ),
                    ),
            ),
        ],
      ),
    );
    return field;
  }
}

/// Text action for the trailing side of [SettingsPageScaffold]'s header.
class SettingsHeaderAction extends StatelessWidget {
  const SettingsHeaderAction({
    super.key,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.working = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final bool working;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppInteractiveSurface(
      semanticLabel: label.l10n(context),
      enabled: enabled && !working,
      onTap: enabled && !working ? onTap : null,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.md,
        ),
        child: working
            ? const AppActivityIndicator(size: 18)
            : Text(
                label.l10n(context),
                style: AppTextStyle.body(
                  enabled ? AppTheme.brand : c.textTertiary,
                  weight: AppTextWeight.semibold,
                ),
              ),
      ),
    );
  }
}

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
    final effectiveOnBack = SettingsSplitPaneScope.isRootRoute(context)
        ? null
        : onBack;
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
              if (effectiveOnBack != null)
                AppInteractiveSurface(
                  semanticLabel: AppStringKeys.navigationBack.l10n(context),
                  onTap: effectiveOnBack,
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

  // The badge width needs a text measurement, and every unread row asks for one
  // on every rebuild. The label set is tiny ('1'..'99+') and the painter does no
  // scaling, so the layout result is bit-identical per (label, direction).
  static final Map<(String, TextDirection), Size> _sizeCache = {};

  Size _visualSize(BuildContext context, String label) {
    final key = (label, Directionality.of(context));
    final cached = _sizeCache[key];
    if (cached != null) return cached;
    const style = TextStyle(
      fontSize: AppTextSize.caption,
      fontWeight: AppTextWeight.semibold,
    );
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: key.$2,
      maxLines: 1,
    )..layout();
    final horizontalPadding = label.length > 1 ? (AppSpacing.xs + 1) * 2 : 0.0;
    final size = Size(
      math.max(AppMetric.unreadBadgeMin, painter.width + horizontalPadding),
      AppMetric.unreadBadgeMin,
    );
    painter.dispose();
    if (_sizeCache.length >= 256) _sizeCache.clear();
    _sizeCache[key] = size;
    return size;
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
          // Telegram stores the counter's label colour alongside its fill
          // (chats_unreadCounterText), so a theme can darken it for a pale
          // badge instead of being stuck with white.
          context.colors.badgeText,
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

/// Divider aligned with the title column of a canonical settings row.
///
/// Use [SettingsDivider.text] for a text-only selection list. Keeping these
/// two alignments named prevents pages from inventing nearly-identical magic
/// numbers such as 47, 48, 52, 54, 58, or 62.
class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key})
    : leadingInset = AppMetric.settingsIconDividerInset;

  const SettingsDivider.text({super.key})
    : leadingInset = AppMetric.settingsTextDividerInset;

  final double leadingInset;

  @override
  Widget build(BuildContext context) =>
      InsetDivider(leadingInset: leadingInset);
}

/// Standard grouped settings card. Use this for left-label/right-value rows
/// instead of duplicating per-screen private `_settingsCard` variants.
/// Label above a group of settings rows.
///
/// Every settings screen used to define its own: sixteen private copies under
/// five names, with three paddings, two sizes, two colours, and one that
/// uppercased its text. This is the one shape they all share.
class SettingsSectionHeader extends StatelessWidget {
  /// [titleKey] is an `AppStringKeys` constant.
  const SettingsSectionHeader(this.titleKey, {super.key, this.text, this.color})
    : assert(
        titleKey != null || text != null,
        'a section header needs a key or literal text',
      );

  /// For a label that is data rather than copy — a folder name, say.
  const SettingsSectionHeader.text(String this.text, {super.key, this.color})
    : titleKey = null;

  final String? titleKey;
  final String? text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        AppSpacing.lg,
        AppSpacing.xxl,
        AppSpacing.sm,
      ),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          text ?? AppStrings.t(titleKey!),
          style: TextStyle(
            fontSize: AppTextSize.footnote,
            color: color ?? context.colors.textTertiary,
          ),
        ),
      ),
    );
  }
}

class SettingsCard extends StatelessWidget {
  const SettingsCard({
    super.key,
    required this.children,
    this.margin,
    this.addDividers = false,
    this.dividerInset = AppMetric.settingsIconDividerInset,
  });

  /// A grouped row card that owns divider placement as well as its surface.
  const SettingsCard.rows({
    super.key,
    required List<Widget> rows,
    this.margin,
    this.dividerInset = AppMetric.settingsIconDividerInset,
  }) : children = rows,
       addDividers = true;

  final List<Widget> children;
  final EdgeInsetsGeometry? margin;
  final bool addDividers;
  final double dividerInset;

  @override
  Widget build(BuildContext context) {
    final effectiveChildren = addDividers && children.length > 1
        ? <Widget>[
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0) InsetDivider(leadingInset: dividerInset),
              children[index],
            ],
          ]
        : children;
    final card = Container(
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: effectiveChildren,
      ),
    );
    return margin == null ? card : Padding(padding: margin!, child: card);
  }
}

/// A complete settings section: optional label, canonical card, canonical
/// row dividers. This is the preferred unit inside [SettingsListView].
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.rows,
    this.titleKey,
    this.title,
    this.headerColor,
    this.dividerInset = AppMetric.settingsIconDividerInset,
  }) : assert(
         titleKey == null || title == null,
         'use either a localization key or literal section title',
       );

  final String? titleKey;
  final String? title;
  final Color? headerColor;
  final List<Widget> rows;
  final double dividerInset;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (titleKey != null)
        SettingsSectionHeader(titleKey, color: headerColor)
      else if (title != null)
        SettingsSectionHeader.text(title!, color: headerColor),
      SettingsCard.rows(rows: rows, dividerInset: dividerInset),
    ],
  );
}

/// Explanatory copy associated with the settings section immediately above.
class SettingsNote extends StatelessWidget {
  const SettingsNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(
      AppSpacing.xs,
      AppSpacing.sm,
      AppSpacing.xs,
      0,
    ),
    child: Text(
      text.l10n(context),
      style: AppTextStyle.footnote(
        context.colors.textTertiary,
      ).copyWith(height: 1.35),
    ),
  );
}

/// Card surface holding arbitrary content rather than a list of rows.
///
/// [SettingsCard] is a column of rows and clips to its own corners, which is
/// wrong for a chart, a paragraph, a slider or a wrap of chips. Those used to
/// hand-roll the same BoxDecoration, which is how the corner radius drifted
/// across seven values in the first place.
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.clipBehavior = Clip.none,
  });

  final Widget child;

  /// Null leaves the child to manage its own insets, which several panels do.
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  /// Set when the child paints into the corners — a list or an image.
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final panel = Container(
      padding: padding,
      clipBehavior: clipBehavior,
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: child,
    );
    return margin == null ? panel : Padding(padding: margin!, child: panel);
  }
}

/// Standard line icon for a settings row.
///
/// Detail screens use one accent-coloured glyph treatment. The coloured tile
/// remains available for the top-level settings index, where it distinguishes
/// destinations rather than controls within one screen.
class SettingsLeadingIcon extends StatelessWidget {
  const SettingsLeadingIcon({super.key, required this.icon, this.color});

  final AppIconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) =>
      AppIcon(icon, size: AppIconSize.xl, color: color ?? AppTheme.brand);
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
    this.titleColor,
    this.subtitle,
    this.enabled = true,
  });

  final String title;
  final String value;
  final Widget? leading;
  final VoidCallback? onTap;
  final bool showChevron;
  final double height;
  final double leadingInset;
  final Widget? trailing;
  final Color? titleColor;
  final String? subtitle;
  final bool enabled;

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
      enabled: enabled,
      onTap: enabled ? onTap : null,
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.l10n(context),
                      style: pointerDense
                          ? AppTextStyle.callout(
                              enabled
                                  ? titleColor ?? c.textPrimary
                                  : c.textTertiary,
                            )
                          : AppTextStyle.body(
                              enabled
                                  ? titleColor ?? c.textPrimary
                                  : c.textTertiary,
                            ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        subtitle!.l10n(context),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.footnote(c.textTertiary),
                      ),
                    ],
                  ],
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
    // The active handle sits on the accent, so it follows the theme's own
    // on-accent token rather than the page brightness — a light accent needs a
    // dark handle whatever the rest of the theme is doing. Off, the handle
    // sits on the neutral track and stays white.
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
      borderRadius: BorderRadius.circular(AppRadius.md),
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
            borderRadius: BorderRadius.circular(AppRadius.md),
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

/// Pill-shaped filter chip for a settings list's segmented header.
///
/// Data & Storage and Downloads each grew their own: different radii (8/18 vs
/// 16), different selected fills (a neutral wash vs an accent tint), one
/// density-aware and one not, one reachable by keyboard and screen reader and
/// one a bare GestureDetector. This is the union of the better halves, so a
/// new filter strip does not start a third dialect.
class SettingsFilterChip extends StatelessWidget {
  const SettingsFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.trailingLabel,
    this.expand = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final AppIconData? icon;

  /// Quiet secondary value after the label — a size, a count.
  final String? trailingLabel;

  /// Fills the available width, for a strip that divides a row evenly rather
  /// than sitting inline.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dense = isDesktopTargetPlatform();
    final radius = BorderRadius.circular(dense ? 8 : 18);
    // Selected reads as the accent, not a grey wash, and takes it from the
    // palette so an imported theme moves it.
    final foreground = selected ? c.linkBlue : c.textSecondary;
    final label$ = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: foreground,
        fontSize: dense ? AppTextSize.footnote : AppTextSize.callout,
        fontWeight: selected ? AppTextWeight.semibold : AppTextWeight.medium,
      ),
    );
    return AppInteractiveSurface(
      onTap: onTap,
      selected: selected,
      semanticLabel: label,
      borderRadius: radius,
      child: Container(
        constraints: BoxConstraints(minHeight: dense ? 36 : 42),
        padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 13),
        decoration: BoxDecoration(
          color: selected ? c.linkBlue.withValues(alpha: 0.13) : c.card,
          borderRadius: radius,
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          // A vertical rail wants its glyphs on one straight edge to scan;
          // an inline chip centres its own content.
          mainAxisAlignment: expand
              ? MainAxisAlignment.start
              : MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              AppIcon(icon!, size: dense ? 15 : 18, color: foreground),
              const SizedBox(width: AppSpacing.sm),
            ],
            if (expand) Flexible(child: label$) else label$,
            if (trailingLabel != null && !expand) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(
                trailingLabel!,
                style: TextStyle(
                  color: c.textTertiary,
                  fontSize: AppTextSize.tiny + 1,
                ),
              ),
            ],
          ],
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
    this.subtitle,
    this.enabled = true,
    this.height = AppMetric.settingsRowHeight,
    this.leadingInset = AppMetric.settingsLeadingInset,
    this.titleColor,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget? leading;

  /// Explanatory line under the title, for a switch whose effect is not
  /// obvious from its label alone.
  final String? subtitle;

  /// A disabled row still reads, but dims and stops responding — used where
  /// the platform, not the user, decides.
  final bool enabled;

  final double height;
  final double leadingInset;
  final Color? titleColor;

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
      enabled: enabled,
      onTap: enabled ? () => onChanged(!value) : null,
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.l10n(context),
                      style: pointerDense
                          ? AppTextStyle.callout(
                              enabled
                                  ? titleColor ?? c.textPrimary
                                  : c.textTertiary,
                            )
                          : AppTextStyle.body(
                              enabled
                                  ? titleColor ?? c.textPrimary
                                  : c.textTertiary,
                            ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        subtitle!.l10n(context),
                        style: AppTextStyle.footnote(c.textTertiary),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: horizontalGap),
              ExcludeSemantics(
                child: ExcludeFocus(
                  child: IgnorePointer(
                    child: AppSwitch(
                      value: value,
                      onChanged: onChanged,
                      enabled: enabled,
                    ),
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
    // Own layer, or the 60 Hz spin repaints whatever list or button hosts it.
    child: RepaintBoundary(
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
    this.compact = false,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  /// Slimmer track and thumb, for a scrubber sitting inline in a toolbar
  /// rather than owning a settings row.
  final bool compact;

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
            height: compact ? 22 : 34,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  child: Container(
                    height: compact ? 3 : 4,
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
                    height: compact ? 3 : 4,
                    decoration: BoxDecoration(
                      color: context.colors.linkBlue,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Positioned(
                  left: constraints.maxWidth * progress - (compact ? 6 : 9),
                  child: Container(
                    width: compact ? 12 : 18,
                    height: compact ? 12 : 18,
                    decoration: BoxDecoration(
                      color: context.colors.linkBlue,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: context.colors.card,
                        width: compact ? 1.5 : 2,
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
