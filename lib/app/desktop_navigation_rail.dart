import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth/account_store.dart';
import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/ui_components.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'adaptive_split_layout.dart';

class DesktopNavigationDestination {
  const DesktopNavigationDestination({
    required this.label,
    required this.icon,
    this.bottom = false,
  });

  final String label;
  final AppIconData icon;
  final bool bottom;
}

class DesktopNavigationAction {
  const DesktopNavigationAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String id;
  final String label;
  final AppIconData icon;
  final VoidCallback onTap;
}

class DesktopMenuChoice {
  const DesktopMenuChoice({
    required this.id,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String id;
  final String label;
  final bool selected;
  final VoidCallback onTap;
}

/// Project-owned desktop navigation chrome. The compact icon rail replaces the
/// phone tab bar without changing the tab state or its nested navigators.
class DesktopNavigationRail extends StatefulWidget {
  const DesktopNavigationRail({
    super.key,
    required this.destinations,
    required this.selection,
    required this.onSelect,
    required this.unread,
    required this.onClearUnread,
    this.folders,
    this.accounts = const [],
    this.activeAccountSlot,
    this.onSelectAccount,
    this.onAddAccount,
    this.switchAccountLabel = 'Switch account',
    this.addAccountLabel = 'Add account',
    this.themeToggleLabel = 'Toggle day or night mode',
    this.darkMode = false,
    this.onToggleThemeMode,
    this.proxyButton,
    this.ghostModeLabel,
    this.ghostModeActive = false,
    this.onOpenGhostMode,
    this.showAccountPhone = true,
    this.actions = const [],
    this.applicationMenuLabel = 'Menu',
    this.languageMenuLabel = 'Language',
    this.languageOptions = const [],
    this.themeMenuLabel = 'Theme',
    this.themeOptions = const [],
    this.applicationMenuPrimaryActions = const [],
    this.applicationMenuActions = const [],
  });

  final List<DesktopNavigationDestination> destinations;
  final int selection;
  final ValueChanged<int> onSelect;
  final int unread;
  final VoidCallback onClearUnread;
  final Widget? folders;
  final List<AccountSummary> accounts;
  final int? activeAccountSlot;
  final ValueChanged<int>? onSelectAccount;
  final VoidCallback? onAddAccount;
  final String switchAccountLabel;
  final String addAccountLabel;
  final String themeToggleLabel;
  final bool darkMode;
  final VoidCallback? onToggleThemeMode;

  /// The 代理 shortcut (the drawer sidebar's ProfileProxyButton, re-hosted
  /// for the rail). Caller owns the widget so the compile-time gate and the
  /// navigation stay outside this chrome file.
  final Widget? proxyButton;

  final String? ghostModeLabel;
  final bool ghostModeActive;
  final VoidCallback? onOpenGhostMode;
  final bool showAccountPhone;
  final List<DesktopNavigationAction> actions;
  final String applicationMenuLabel;
  final String languageMenuLabel;
  final List<DesktopMenuChoice> languageOptions;
  final String themeMenuLabel;
  final List<DesktopMenuChoice> themeOptions;
  final List<DesktopNavigationAction> applicationMenuPrimaryActions;
  final List<DesktopNavigationAction> applicationMenuActions;

  @override
  State<DesktopNavigationRail> createState() => _DesktopNavigationRailState();
}

class _DesktopNavigationRailState extends State<DesktopNavigationRail> {
  final GlobalKey _accountButtonKey = GlobalKey();
  final GlobalKey _applicationMenuButtonKey = GlobalKey();
  OverlayEntry? _accountSwitcher;
  OverlayEntry? _applicationMenu;

  @override
  void dispose() {
    _accountSwitcher?.remove();
    _accountSwitcher = null;
    _applicationMenu?.remove();
    _applicationMenu = null;
    super.dispose();
  }

  void _toggleAccountSwitcher() {
    if (_accountSwitcher != null) {
      _closeAccountSwitcher();
      return;
    }
    _closeApplicationMenu();
    final buttonContext = _accountButtonKey.currentContext;
    final overlay = Overlay.of(context);
    final renderBox = buttonContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final viewport = MediaQuery.sizeOf(context);
    final left = (position.dx + size.width + AppSpacing.sm).clamp(
      AppSpacing.sm,
      (viewport.width - 224 - AppSpacing.sm).clamp(
        AppSpacing.sm,
        viewport.width,
      ),
    );
    final bottom = (viewport.height - position.dy - size.height).clamp(
      AppSpacing.sm,
      viewport.height,
    );
    final entry = OverlayEntry(
      builder: (context) => _DesktopAccountSwitcherOverlay(
        left: left.toDouble(),
        bottom: bottom.toDouble(),
        accounts: widget.accounts,
        activeAccountSlot: widget.activeAccountSlot,
        onDismiss: _closeAccountSwitcher,
        onSelect: (slot) {
          _closeAccountSwitcher();
          widget.onSelectAccount?.call(slot);
        },
        onAdd: widget.onAddAccount == null
            ? null
            : () {
                _closeAccountSwitcher();
                widget.onAddAccount?.call();
              },
        addAccountLabel: widget.addAccountLabel,
        showAccountPhone: widget.showAccountPhone,
      ),
    );
    _accountSwitcher = entry;
    overlay.insert(entry);
  }

  void _closeAccountSwitcher() {
    _accountSwitcher?.remove();
    _accountSwitcher = null;
  }

  void _toggleApplicationMenu() {
    if (_applicationMenu != null) {
      _closeApplicationMenu();
      return;
    }
    _closeAccountSwitcher();
    final buttonContext = _applicationMenuButtonKey.currentContext;
    final overlay = Overlay.of(context);
    final renderBox = buttonContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final viewport = MediaQuery.sizeOf(context);
    const panelWidth = 284.0;
    final left = (position.dx + size.width + AppSpacing.sm).clamp(
      AppSpacing.sm,
      (viewport.width - panelWidth - AppSpacing.sm).clamp(
        AppSpacing.sm,
        viewport.width,
      ),
    );
    final bottom = (viewport.height - position.dy - size.height).clamp(
      AppSpacing.sm,
      viewport.height,
    );
    final entry = OverlayEntry(
      builder: (context) => _DesktopApplicationMenuOverlay(
        left: left.toDouble(),
        bottom: bottom.toDouble(),
        label: widget.applicationMenuLabel,
        languageMenuLabel: widget.languageMenuLabel,
        languageOptions: widget.languageOptions,
        themeMenuLabel: widget.themeMenuLabel,
        themeOptions: widget.themeOptions,
        primaryActions: widget.applicationMenuPrimaryActions,
        actions: widget.applicationMenuActions,
        onDismiss: _closeApplicationMenu,
      ),
    );
    _applicationMenu = entry;
    overlay.insert(entry);
  }

  void _closeApplicationMenu() {
    _applicationMenu?.remove();
    _applicationMenu = null;
  }

  Widget _destination(int index) => _DesktopNavigationButton(
    key: ValueKey('desktop-navigation-item-$index'),
    destination: widget.destinations[index],
    selected: widget.selection == index,
    unread: index == 0 ? widget.unread : 0,
    onClearUnread: widget.onClearUnread,
    onTap: () => widget.onSelect(index),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      key: const ValueKey('desktop-navigation-rail'),
      width: desktopNavigationRailWidth,
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(
          right: BorderSide(color: c.divider, width: AppMetric.divider),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.sm),
          for (var index = 0; index < widget.destinations.length; index++)
            if (!widget.destinations[index].bottom) _destination(index),
          Expanded(child: widget.folders ?? const SizedBox.shrink()),
          for (final action in widget.actions)
            _DesktopNavigationActionButton(action: action),
          for (var index = 0; index < widget.destinations.length; index++)
            if (widget.destinations[index].bottom) _destination(index),
          if (widget.onSelectAccount != null ||
              widget.onAddAccount != null ||
              widget.onToggleThemeMode != null ||
              widget.proxyButton != null ||
              widget.onOpenGhostMode != null ||
              widget.languageOptions.isNotEmpty ||
              widget.applicationMenuPrimaryActions.isNotEmpty ||
              widget.applicationMenuActions.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Divider(height: 1, thickness: 1, color: c.divider),
            ),
            Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.xs,
                bottom: AppSpacing.sm,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.onSelectAccount != null ||
                      widget.onAddAccount != null)
                    _DesktopAccountSwitchButton(
                      key: _accountButtonKey,
                      label: widget.switchAccountLabel,
                      onTap: _toggleAccountSwitcher,
                    ),
                  if (widget.onToggleThemeMode != null)
                    _DesktopThemeToggleButton(
                      label: widget.themeToggleLabel,
                      darkMode: widget.darkMode,
                      onTap: widget.onToggleThemeMode!,
                    ),
                  // 代理 and ghost-mode shortcuts sit right after the
                  // theme toggle, mirroring the drawer sidebar's bottom-bar
                  // order (代理 → ghost → day/night reads right-to-left as
                  // night → ghost → 代理 here). Both double as status lights
                  // (proxy dot / brand-coloured eyeSlash).
                  if (widget.proxyButton != null)
                    SizedBox(
                      height: 42,
                      child: Center(child: widget.proxyButton),
                    ),
                  if (widget.onOpenGhostMode != null)
                    _DesktopGhostModeButton(
                      label: widget.ghostModeLabel ?? '',
                      active: widget.ghostModeActive,
                      onTap: widget.onOpenGhostMode!,
                    ),
                  if (widget.applicationMenuPrimaryActions.isNotEmpty ||
                      widget.languageOptions.isNotEmpty ||
                      widget.applicationMenuActions.isNotEmpty)
                    _DesktopApplicationMenuButton(
                      key: _applicationMenuButtonKey,
                      label: widget.applicationMenuLabel,
                      onTap: _toggleApplicationMenu,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The rail's ghost-mode shortcut: eyeSlash glyph, brand-coloured while
/// ghost mode is intercepting. Present only in opted-in builds (the caller
/// passes the callback behind the compile-time gate).
class _DesktopGhostModeButton extends StatelessWidget {
  const _DesktopGhostModeButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      key: const ValueKey('desktop-ghost-mode-button'),
      height: 42,
      child: Tooltip(
        message: label,
        waitDuration: const Duration(milliseconds: 450),
        child: AppInteractiveSurface(
          semanticLabel: label,
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Center(
              child: AppIcon(
                HeroAppIcons.eyeSlash,
                key: const ValueKey('desktop-ghost-mode-icon'),
                size: 19,
                color: active ? AppTheme.brand : c.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopApplicationMenuButton extends StatelessWidget {
  const _DesktopApplicationMenuButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      key: const ValueKey('desktop-application-menu-button'),
      height: 42,
      child: Tooltip(
        message: label,
        waitDuration: const Duration(milliseconds: 450),
        child: AppInteractiveSurface(
          semanticLabel: label,
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Center(
              child: AppIcon(
                HeroAppIcons.bars,
                key: const ValueKey('desktop-application-menu-icon'),
                size: 20,
                color: c.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopThemeToggleButton extends StatelessWidget {
  const _DesktopThemeToggleButton({
    required this.label,
    required this.darkMode,
    required this.onTap,
  });

  final String label;
  final bool darkMode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      key: const ValueKey('desktop-theme-toggle-button'),
      height: 42,
      child: Tooltip(
        message: label,
        waitDuration: const Duration(milliseconds: 450),
        child: AppInteractiveSurface(
          semanticLabel: label,
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Center(
              child: AppIcon(
                darkMode ? HeroAppIcons.sun : HeroAppIcons.moon,
                key: const ValueKey('desktop-theme-toggle-icon'),
                size: 19,
                color: c.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopApplicationMenuOverlay extends StatefulWidget {
  const _DesktopApplicationMenuOverlay({
    required this.left,
    required this.bottom,
    required this.label,
    required this.languageMenuLabel,
    required this.languageOptions,
    required this.themeMenuLabel,
    required this.themeOptions,
    required this.primaryActions,
    required this.actions,
    required this.onDismiss,
  });

  final double left;
  final double bottom;
  final String label;
  final String languageMenuLabel;
  final List<DesktopMenuChoice> languageOptions;
  final String themeMenuLabel;
  final List<DesktopMenuChoice> themeOptions;
  final List<DesktopNavigationAction> primaryActions;
  final List<DesktopNavigationAction> actions;
  final VoidCallback onDismiss;

  @override
  State<_DesktopApplicationMenuOverlay> createState() =>
      _DesktopApplicationMenuOverlayState();
}

class _DesktopApplicationMenuOverlayState
    extends State<_DesktopApplicationMenuOverlay> {
  /// The submenu currently replacing the menu body, if any. Language and
  /// theme are the same shape, so they share one slot rather than one flag
  /// each.
  ({String label, List<DesktopMenuChoice> options})? _submenu;

  void _run(DesktopNavigationAction action) {
    widget.onDismiss();
    action.onTap();
  }

  void _runChoice(DesktopMenuChoice option) {
    widget.onDismiss();
    option.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final submenu = _submenu;
    final maximumHeight =
        MediaQuery.sizeOf(context).height - widget.bottom - 16;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onDismiss,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: widget.left,
          bottom: widget.bottom,
          child: Material(
            type: MaterialType.transparency,
            child: CallbackShortcuts(
              bindings: <ShortcutActivator, VoidCallback>{
                const SingleActivator(LogicalKeyboardKey.escape):
                    widget.onDismiss,
              },
              child: Focus(
                autofocus: true,
                child: Container(
                  key: const ValueKey('desktop-application-menu-panel'),
                  width: 284,
                  constraints: BoxConstraints(
                    maxHeight: maximumHeight.clamp(180, 540).toDouble(),
                  ),
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: c.divider),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: submenu != null
                          ? [
                              _DesktopApplicationLanguageHeader(
                                label: submenu.label,
                                onBack: () => setState(() => _submenu = null),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.lg,
                                ),
                                child: Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: c.divider,
                                ),
                              ),
                              for (final option in submenu.options)
                                _DesktopApplicationLanguageOptionRow(
                                  option: option,
                                  onTap: () => _runChoice(option),
                                ),
                            ]
                          : [
                              for (final action in widget.primaryActions)
                                _DesktopApplicationMenuRow(
                                  action: action,
                                  onTap: () => _run(action),
                                ),
                              if (widget.primaryActions.isNotEmpty &&
                                  (widget.languageOptions.isNotEmpty ||
                                      widget.themeOptions.isNotEmpty ||
                                      widget.actions.isNotEmpty))
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    AppSpacing.lg,
                                    AppSpacing.sm,
                                    AppSpacing.lg,
                                    AppSpacing.xs,
                                  ),
                                  child: Divider(
                                    height: 1,
                                    thickness: 1,
                                    color: c.divider,
                                  ),
                                ),
                              if (widget.languageOptions.isNotEmpty)
                                _DesktopApplicationSubmenuRow(
                                  key: const ValueKey(
                                    'desktop-application-language',
                                  ),
                                  label: widget.languageMenuLabel,
                                  icon: HeroAppIcons.language,
                                  onTap: () => setState(
                                    () => _submenu = (
                                      label: widget.languageMenuLabel,
                                      options: widget.languageOptions,
                                    ),
                                  ),
                                ),
                              if (widget.themeOptions.isNotEmpty)
                                _DesktopApplicationSubmenuRow(
                                  key: const ValueKey(
                                    'desktop-application-theme',
                                  ),
                                  label: widget.themeMenuLabel,
                                  icon: HeroAppIcons.palette,
                                  onTap: () => setState(
                                    () => _submenu = (
                                      label: widget.themeMenuLabel,
                                      options: widget.themeOptions,
                                    ),
                                  ),
                                ),
                              for (final action in widget.actions)
                                _DesktopApplicationMenuRow(
                                  action: action,
                                  onTap: () => _run(action),
                                ),
                            ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DesktopApplicationLanguageHeader extends StatelessWidget {
  const _DesktopApplicationLanguageHeader({
    required this.label,
    required this.onBack,
  });

  final String label;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppInteractiveSurface(
      key: const ValueKey('desktop-application-language-back'),
      semanticLabel: label,
      onTap: onBack,
      child: SizedBox(
        height: 40,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            children: [
              AppIcon(
                HeroAppIcons.chevronLeft,
                size: 15,
                color: c.textSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                label,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopApplicationSubmenuRow extends StatelessWidget {
  const _DesktopApplicationSubmenuRow({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final AppIconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppInteractiveSurface(
      semanticLabel: label,
      onTap: onTap,
      child: SizedBox(
        height: 40,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            children: [
              AppIcon(icon, size: 17, color: c.textSecondary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              AppIcon(
                HeroAppIcons.chevronRight,
                size: 14,
                color: c.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopApplicationLanguageOptionRow extends StatelessWidget {
  const _DesktopApplicationLanguageOptionRow({
    required this.option,
    required this.onTap,
  });

  final DesktopMenuChoice option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppInteractiveSurface(
      key: ValueKey('desktop-application-language-${option.id}'),
      semanticLabel: option.label,
      onTap: onTap,
      child: SizedBox(
        height: 36,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: option.selected ? c.linkBlue : c.textPrimary,
                    fontSize: 13,
                    fontWeight: option.selected
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
              if (option.selected)
                AppIcon(HeroAppIcons.check, size: 15, color: c.linkBlue),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopApplicationMenuRow extends StatelessWidget {
  const _DesktopApplicationMenuRow({required this.action, required this.onTap});

  final DesktopNavigationAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppInteractiveSurface(
      key: ValueKey('desktop-application-action-${action.id}'),
      semanticLabel: action.label,
      onTap: onTap,
      child: SizedBox(
        height: 40,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            children: [
              AppIcon(action.icon, size: 17, color: c.textSecondary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
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

class _DesktopAccountSwitchButton extends StatelessWidget {
  const _DesktopAccountSwitchButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      key: const ValueKey('desktop-account-switcher'),
      height: 42,
      child: Tooltip(
        message: label,
        waitDuration: const Duration(milliseconds: 450),
        child: AppInteractiveSurface(
          semanticLabel: label,
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Center(
              child: AppIcon(
                HeroAppIcons.arrowsRightLeft,
                key: const ValueKey('desktop-account-switch-icon'),
                size: 19,
                color: c.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopAccountSwitcherOverlay extends StatelessWidget {
  const _DesktopAccountSwitcherOverlay({
    required this.left,
    required this.bottom,
    required this.accounts,
    required this.activeAccountSlot,
    required this.onDismiss,
    required this.onSelect,
    required this.addAccountLabel,
    required this.showAccountPhone,
    this.onAdd,
  });

  final double left;
  final double bottom;
  final List<AccountSummary> accounts;
  final int? activeAccountSlot;
  final VoidCallback onDismiss;
  final ValueChanged<int> onSelect;
  final String addAccountLabel;
  final bool showAccountPhone;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final maximumHeight = MediaQuery.sizeOf(context).height - bottom - 16;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onDismiss,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: left,
          bottom: bottom,
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              key: const ValueKey('desktop-account-switcher-panel'),
              width: 224,
              constraints: BoxConstraints(
                maxHeight: maximumHeight.clamp(160, 520).toDouble(),
              ),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: c.divider),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                children: [
                  for (final account in accounts)
                    _DesktopAccountSwitcherRow(
                      account: account,
                      selected: account.slot == activeAccountSlot,
                      showPhone: showAccountPhone,
                      onTap: () => onSelect(account.slot),
                    ),
                  if (onAdd != null)
                    _DesktopAddAccountRow(
                      label: addAccountLabel,
                      onTap: onAdd!,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DesktopAccountSwitcherRow extends StatelessWidget {
  const _DesktopAccountSwitcherRow({
    required this.account,
    required this.selected,
    required this.showPhone,
    required this.onTap,
  });

  final AccountSummary account;
  final bool selected;
  final bool showPhone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppInteractiveSurface(
      semanticLabel: account.name,
      selected: selected,
      onTap: onTap,
      child: Container(
        key: ValueKey('desktop-account-${account.slot}'),
        height: 50,
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.brand.withValues(alpha: 0.12)
              : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: selected ? AppTheme.brand : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        padding: const EdgeInsetsDirectional.only(start: 10, end: 12),
        child: Row(
          children: [
            _DesktopAccountAvatar(account: account, size: 34),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  if (showPhone && account.phone.isNotEmpty)
                    Text(
                      account.phone,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.textSecondary, fontSize: 11),
                    ),
                ],
              ),
            ),
            if (selected)
              AppIcon(HeroAppIcons.check, size: 14, color: AppTheme.brand),
          ],
        ),
      ),
    );
  }
}

class _DesktopAddAccountRow extends StatelessWidget {
  const _DesktopAddAccountRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppInteractiveSurface(
      semanticLabel: label,
      onTap: onTap,
      child: SizedBox(
        key: const ValueKey('desktop-add-account'),
        height: 44,
        child: Row(
          children: [
            const SizedBox(width: 12),
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.brand.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: AppIcon(
                HeroAppIcons.plus,
                size: 15,
                color: AppTheme.brand,
              ),
            ),
            const SizedBox(width: 9),
            Text(
              label,
              style: TextStyle(
                color: AppTheme.brand,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopAccountAvatar extends StatelessWidget {
  const _DesktopAccountAvatar({required this.account, required this.size});

  final AccountSummary? account;
  final double size;

  @override
  Widget build(BuildContext context) {
    final path = account?.avatarPath;
    final name = account?.name.trim() ?? '';
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: AppTheme.brand, shape: BoxShape.circle),
      child: name.isEmpty
          ? const AppIcon(HeroAppIcons.plus, size: 17, color: Colors.white)
          : Text(
              name.characters.first.toUpperCase(),
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.4,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
    if (path == null || path.isEmpty) return fallback;
    final cacheSize = (size * MediaQuery.devicePixelRatioOf(context)).ceil();
    return ClipOval(
      child: Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: cacheSize,
        cacheHeight: cacheSize,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

class _DesktopNavigationActionButton extends StatelessWidget {
  const _DesktopNavigationActionButton({required this.action});

  final DesktopNavigationAction action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      key: ValueKey('desktop-navigation-action-${action.id}'),
      height: 42,
      child: Tooltip(
        message: action.label,
        waitDuration: const Duration(milliseconds: 450),
        child: AppInteractiveSurface(
          semanticLabel: action.label,
          onTap: action.onTap,
          borderRadius: BorderRadius.circular(9),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Center(
              child: AppIcon(action.icon, size: 19, color: c.textSecondary),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopNavigationButton extends StatelessWidget {
  const _DesktopNavigationButton({
    super.key,
    required this.destination,
    required this.selected,
    required this.unread,
    required this.onClearUnread,
    required this.onTap,
  });

  final DesktopNavigationDestination destination;
  final bool selected;
  final int unread;
  final VoidCallback onClearUnread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 46,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedPositionedDirectional(
            duration: AppMotion.duration(context, AppMotion.responsive),
            curve: AppMotion.standard,
            start: 0,
            top: selected ? 12 : 21,
            bottom: selected ? 12 : 21,
            width: 3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: selected ? AppTheme.brand : Colors.transparent,
                borderRadius: const BorderRadiusDirectional.horizontal(
                  end: Radius.circular(3),
                ),
              ),
            ),
          ),
          Tooltip(
            message: destination.label,
            waitDuration: const Duration(milliseconds: 450),
            child: AppInteractiveSurface(
              semanticLabel: destination.label,
              selected: selected,
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: AnimatedContainer(
                duration: AppMotion.duration(context, AppMotion.responsive),
                curve: AppMotion.standard,
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: selected
                      ? AppTheme.brand.withValues(alpha: 0.13)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    AppIcon(
                      destination.icon,
                      size: 20,
                      color: selected ? AppTheme.brand : c.textSecondary,
                    ),
                    if (unread > 0)
                      PositionedDirectional(
                        top: 2,
                        end: 2,
                        child: UnreadBadge(
                          count: unread,
                          onClear: onClearUnread,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
