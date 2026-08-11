import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../platform/adaptive_platform.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'app_icons.dart';
import 'app_interactive_surface.dart';
import 'ui_components.dart';

/// One value displayed by [SettingsSelectionRow].
class SettingsSelectionOption<T> {
  const SettingsSelectionOption({
    required this.id,
    required this.value,
    required this.label,
    this.icon,
    this.subtitle,
    this.enabled = true,
  });

  /// Stable identifier used for widget keys and focus restoration.
  final String id;
  final T value;
  final String label;
  final AppIconData? icon;
  final String? subtitle;
  final bool enabled;
}

/// A settings row that opens an anchored context menu on desktop and a
/// draggable selection sheet on touch layouts.
///
/// The predicate-based selection API supports both single-choice menus and
/// persistent multi-select menus without coupling this component to a
/// particular controller or value type.
class SettingsSelectionRow<T> extends StatelessWidget {
  const SettingsSelectionRow({
    super.key,
    required this.title,
    required this.value,
    required this.options,
    required this.isSelected,
    required this.onSelected,
    this.leading,
    this.subtitle,
    this.menuTitle,
    this.menuKey,
    this.dismissOnSelect = true,
    this.enabled = true,
    this.showChevron = true,
    this.height = AppMetric.settingsRowHeight,
    this.leadingInset = AppMetric.settingsLeadingInset,
    this.desktopMenuWidth = 280,
    this.desktopMenuMaxHeight = 360,
  });

  final String title;
  final String value;
  final Widget? leading;
  final String? subtitle;
  final List<SettingsSelectionOption<T>> options;
  final bool Function(T value) isSelected;
  final FutureOr<void> Function(T value) onSelected;
  final String? menuTitle;
  final Key? menuKey;
  final bool dismissOnSelect;
  final bool enabled;
  final bool showChevron;
  final double height;
  final double leadingInset;
  final double desktopMenuWidth;
  final double desktopMenuMaxHeight;

  @override
  Widget build(BuildContext context) {
    final canOpen = enabled && options.any((option) => option.enabled);
    return Builder(
      builder: (anchorContext) => SettingsRow(
        title: title,
        value: value,
        leading: leading,
        subtitle: subtitle,
        enabled: enabled,
        showChevron: showChevron,
        height: height,
        leadingInset: leadingInset,
        onTap: canOpen
            ? () => unawaited(_showSelectionMenu(anchorContext))
            : null,
      ),
    );
  }

  Future<void> _showSelectionMenu(BuildContext anchorContext) async {
    if (isDesktopTargetPlatform(Theme.of(anchorContext).platform)) {
      await _showDesktopMenu(anchorContext);
      return;
    }
    await _showTouchSheet(anchorContext);
  }

  Future<void> _showDesktopMenu(BuildContext anchorContext) async {
    final navigator = Navigator.of(anchorContext);
    final anchorBox = anchorContext.findRenderObject() as RenderBox?;
    final overlayBox =
        navigator.overlay?.context.findRenderObject() as RenderBox?;
    if (anchorBox == null ||
        overlayBox == null ||
        !anchorBox.hasSize ||
        !overlayBox.hasSize) {
      return;
    }

    final globalTopLeft = anchorBox.localToGlobal(Offset.zero);
    final globalBottomRight = anchorBox.localToGlobal(
      anchorBox.size.bottomRight(Offset.zero),
    );
    final anchor = Rect.fromPoints(
      overlayBox.globalToLocal(globalTopLeft),
      overlayBox.globalToLocal(globalBottomRight),
    );
    final duration = AppMotion.duration(anchorContext, AppMotion.quick);

    await showGeneralDialog<void>(
      context: anchorContext,
      useRootNavigator: false,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(
        anchorContext,
      ).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: duration,
      pageBuilder: (dialogContext, _, _) => _DesktopSettingsSelectionMenu<T>(
        anchor: anchor,
        options: options,
        isSelected: isSelected,
        onSelected: onSelected,
        dismissOnSelect: dismissOnSelect,
        title: menuTitle,
        menuKey: menuKey,
        width: desktopMenuWidth,
        maxHeight: desktopMenuMaxHeight,
      ),
      transitionBuilder: (context, animation, _, child) {
        if (AppMotion.isReduced(context)) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: AppMotion.emphasized,
          reverseCurve: AppMotion.accelerate,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            alignment: Alignment.topRight,
            scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _showTouchSheet(BuildContext anchorContext) =>
      showAppModalSheet<void>(
        context: anchorContext,
        backgroundColor: Colors.transparent,
        isScrollControlled: options.length > 8,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) {
            final titleOffset = menuTitle == null ? 0 : 1;
            return SafeArea(
              top: false,
              child: SettingsPanel(
                key: menuKey,
                margin: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.72,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: options.length + titleOffset,
                    separatorBuilder: (_, _) => const SettingsDivider(),
                    itemBuilder: (context, index) {
                      if (menuTitle != null && index == 0) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.xxl,
                            AppSpacing.lg,
                            AppSpacing.xxl,
                            AppSpacing.md,
                          ),
                          child: Text(
                            menuTitle!.l10n(context),
                            style: AppTextStyle.callout(
                              context.colors.textSecondary,
                            ).copyWith(fontWeight: AppTextWeight.semibold),
                          ),
                        );
                      }
                      final option = options[index - titleOffset];
                      final selected = isSelected(option.value);
                      return SettingsRow(
                        key: ValueKey(option.id),
                        title: option.label,
                        subtitle: option.subtitle,
                        leading: option.icon == null
                            ? null
                            : SettingsLeadingIcon(icon: option.icon!),
                        enabled: option.enabled,
                        showChevron: false,
                        trailing: selected
                            ? AppIcon(
                                HeroAppIcons.check,
                                size: AppIconSize.lg,
                                color: AppTheme.brand,
                              )
                            : null,
                        onTap: option.enabled
                            ? () async {
                                await Future<void>.sync(
                                  () => onSelected(option.value),
                                );
                                if (!context.mounted) return;
                                if (dismissOnSelect) {
                                  Navigator.of(context).pop();
                                } else {
                                  setSheetState(() {});
                                }
                              }
                            : null,
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      );
}

class _DesktopSettingsSelectionMenu<T> extends StatefulWidget {
  const _DesktopSettingsSelectionMenu({
    required this.anchor,
    required this.options,
    required this.isSelected,
    required this.onSelected,
    required this.dismissOnSelect,
    required this.width,
    required this.maxHeight,
    this.title,
    this.menuKey,
  });

  final Rect anchor;
  final List<SettingsSelectionOption<T>> options;
  final bool Function(T value) isSelected;
  final FutureOr<void> Function(T value) onSelected;
  final bool dismissOnSelect;
  final String? title;
  final Key? menuKey;
  final double width;
  final double maxHeight;

  @override
  State<_DesktopSettingsSelectionMenu<T>> createState() =>
      _DesktopSettingsSelectionMenuState<T>();
}

class _DesktopSettingsSelectionMenuState<T>
    extends State<_DesktopSettingsSelectionMenu<T>> {
  static const _viewportMargin = 8.0;
  static const _anchorGap = 4.0;
  static const _rowHeight = 40.0;
  static const _subtitleRowHeight = 52.0;
  static const _titleHeight = 38.0;

  late List<FocusNode> _focusNodes;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _createFocusNodes();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _focusNodes.isEmpty) return;
      final selectedIndex = widget.options.indexWhere(
        (option) => option.enabled && widget.isSelected(option.value),
      );
      final firstEnabled = widget.options.indexWhere(
        (option) => option.enabled,
      );
      final index = selectedIndex >= 0 ? selectedIndex : firstEnabled;
      if (index >= 0) _focusNodes[index].requestFocus();
    });
  }

  @override
  void didUpdateWidget(_DesktopSettingsSelectionMenu<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.options.length != widget.options.length) {
      for (final node in _focusNodes) {
        node.dispose();
      }
      _createFocusNodes();
    }
  }

  void _createFocusNodes() {
    _focusNodes = [
      for (final option in widget.options)
        FocusNode(debugLabel: 'Settings selection ${option.id}'),
    ];
  }

  @override
  void dispose() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _moveFocus(int delta) {
    if (_focusNodes.isEmpty) return;
    var index = _focusNodes.indexWhere((node) => node.hasFocus);
    if (index < 0) index = delta > 0 ? -1 : 0;
    for (var step = 0; step < widget.options.length; step++) {
      index = (index + delta) % widget.options.length;
      if (index < 0) index += widget.options.length;
      if (widget.options[index].enabled) {
        _focusNodes[index].requestFocus();
        return;
      }
    }
  }

  Future<void> _select(SettingsSelectionOption<T> option) async {
    if (!option.enabled) return;
    await Future<void>.sync(() => widget.onSelected(option.value));
    if (!mounted) return;
    if (widget.dismissOnSelect) {
      Navigator.of(context).pop();
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final width = math
            .min(
              widget.width,
              math.max(0, viewport.width - _viewportMargin * 2),
            )
            .toDouble();
        final contentHeight =
            (widget.title == null ? 0 : _titleHeight) +
            AppSpacing.sm * 2 +
            widget.options.fold<double>(
              0,
              (height, option) =>
                  height +
                  (option.subtitle == null ? _rowHeight : _subtitleRowHeight),
            );
        final resolvedHeight = math
            .min(
              contentHeight,
              math.min(
                widget.maxHeight,
                math.max(0, viewport.height - _viewportMargin * 2),
              ),
            )
            .toDouble();
        final left = (widget.anchor.right - width)
            .clamp(
              _viewportMargin,
              math.max(
                _viewportMargin,
                viewport.width - width - _viewportMargin,
              ),
            )
            .toDouble();
        final spaceBelow =
            viewport.height -
            widget.anchor.bottom -
            _anchorGap -
            _viewportMargin;
        final spaceAbove = widget.anchor.top - _anchorGap - _viewportMargin;
        final opensBelow =
            spaceBelow >= resolvedHeight || spaceBelow >= spaceAbove;
        final requestedTop = opensBelow
            ? widget.anchor.bottom + _anchorGap
            : widget.anchor.top - _anchorGap - resolvedHeight;
        final top = requestedTop
            .clamp(
              _viewportMargin,
              math.max(
                _viewportMargin,
                viewport.height - resolvedHeight - _viewportMargin,
              ),
            )
            .toDouble();

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: left,
              top: top,
              width: width,
              child: CallbackShortcuts(
                bindings: <ShortcutActivator, VoidCallback>{
                  const SingleActivator(LogicalKeyboardKey.escape): () =>
                      Navigator.of(context).maybePop(),
                  const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                      _moveFocus(1),
                  const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                      _moveFocus(-1),
                },
                child: FocusTraversalGroup(
                  child: Container(
                    key:
                        widget.menuKey ??
                        const ValueKey('desktop-settings-selection-menu'),
                    constraints: BoxConstraints(maxHeight: resolvedHeight),
                    decoration: BoxDecoration(
                      color: context.colors.card,
                      border: Border.all(
                        color: context.colors.divider,
                        width: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.title != null)
                          SizedBox(
                            height: _titleHeight,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.lg,
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  widget.title!.l10n(context),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      AppTextStyle.caption(
                                        context.colors.textSecondary,
                                      ).copyWith(
                                        fontWeight: AppTextWeight.semibold,
                                      ),
                                ),
                              ),
                            ),
                          ),
                        if (widget.title != null) const SettingsDivider.text(),
                        Flexible(
                          child: Scrollbar(
                            controller: _scrollController,
                            thumbVisibility: widget.options.length > 8,
                            // The thumb is informational here. Keeping it
                            // non-interactive prevents the desktop scrollbar
                            // hit region from swallowing clicks on the trailing
                            // checkmarks of long multi-select menus.
                            interactive: false,
                            child: ListView.builder(
                              controller: _scrollController,
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.sm,
                              ),
                              itemCount: widget.options.length,
                              itemBuilder: (context, index) {
                                final option = widget.options[index];
                                return _DesktopSettingsSelectionItem<T>(
                                  key: ValueKey(option.id),
                                  option: option,
                                  selected: widget.isSelected(option.value),
                                  focusNode: _focusNodes[index],
                                  onTap: () => unawaited(_select(option)),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DesktopSettingsSelectionItem<T> extends StatelessWidget {
  const _DesktopSettingsSelectionItem({
    super.key,
    required this.option,
    required this.selected,
    required this.focusNode,
    required this.onTap,
  });

  final SettingsSelectionOption<T> option;
  final bool selected;
  final FocusNode focusNode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = !option.enabled
        ? colors.textTertiary
        : selected
        ? colors.linkBlue
        : colors.textPrimary;
    final height = option.subtitle == null ? 40.0 : 52.0;
    return AppInteractiveSurface(
      semanticLabel: option.label.l10n(context),
      checked: selected,
      enabled: option.enabled,
      focusNode: focusNode,
      onTap: option.enabled ? onTap : null,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        height: height,
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: selected
              ? colors.linkBlue.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          children: [
            if (option.icon != null) ...[
              SizedBox(
                width: AppMetric.menuIconSlot,
                child: AppIcon(
                  option.icon!,
                  size: AppIconSize.md,
                  color: selected ? colors.linkBlue : colors.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.label.l10n(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.callout(foreground).copyWith(
                      fontWeight: selected
                          ? AppTextWeight.semibold
                          : AppTextWeight.regular,
                    ),
                  ),
                  if (option.subtitle case final subtitle?) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      subtitle.l10n(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.caption(colors.textTertiary),
                    ),
                  ],
                ],
              ),
            ),
            if (selected) ...[
              const SizedBox(width: AppSpacing.sm),
              AppIcon(
                HeroAppIcons.check,
                size: AppIconSize.md,
                color: colors.linkBlue,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
