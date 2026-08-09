//
//  settings_view.dart
//
//  Settings are ordered by the task the user wants to complete. Telegram
//  account controls and Mithka preferences keep direct, distinct destinations
//  without making their implementation owner the top-level navigation.
//

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app/adaptive_split_layout.dart';
import '../app/app_version.dart';
import '../auth/account_store.dart';
import '../auth/auth_manager.dart';
import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../pro/mithka_pro_service.dart';
import '../pro/mithka_pro_view.dart';
import '../security/local_app_lock_views.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'about_view.dart';
import 'account_backup_view.dart';
import 'advanced_settings_view.dart';
import 'ai_settings_view.dart';
import 'appearance_view.dart';
import 'blocking_settings_view.dart';
import 'chat_folder_management_view.dart';
import 'desktop_hotkey_settings_view.dart';
import 'developer_mode_controller.dart';
import 'developer_settings_view.dart';
import 'feature_settings_view.dart';
import 'general_settings_view.dart';
import 'language_settings_view.dart';
import 'notification_settings_view.dart';
import 'privacy_detail_views.dart';
import 'privacy_security_view.dart';
import 'proxy_view.dart';
import 'storage_usage_view.dart';
import 'translation_settings_view.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({
    super.key,
    this.focusSearch = false,
    this.showBackButton = true,
    this.allowSessionLifecycleActions = true,
    this.initialCategoryId,
  });

  /// Used by Telegram's `settingsSectionSearch` internal link.
  final bool focusSearch;

  /// Hides only the root Settings back affordance when Settings owns a native
  /// desktop window. Detail pages keep their local back navigation.
  final bool showBackButton;

  /// Account-slot backup/restore and logout own TDLib database lifecycle.
  /// Independent desktop engine windows must disable them and use the primary
  /// engine's query/update proxy for all remaining live settings.
  final bool allowSessionLifecycleActions;

  /// Optional initial category for native desktop shortcuts such as the
  /// system app menu's Appearance action. Unknown IDs fall back to General.
  final String? initialCategoryId;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late final Future<AppVersion> _versionFuture = AppVersion.load();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late String _selectedCategoryId;

  /// The destination shown in the detail pane, once one has been chosen.
  ///
  /// Null means the category was selected but none of its children yet, which
  /// only happens for a category the user just expanded.
  String? _selectedDestinationId;

  /// Categories expanded in the sidebar. The selected one is always open.
  final Set<String> _expandedCategoryIds = <String>{};

  @override
  void initState() {
    super.initState();
    final initialCategoryId = widget.initialCategoryId;
    _selectedCategoryId =
        _settingsCategoryDefinitions.any(
          (category) => category.id == initialCategoryId,
        )
        ? initialCategoryId!
        : 'general';
    _expandedCategoryIds.add(_selectedCategoryId);
    _searchController.addListener(_searchChanged);
    if (widget.focusSearch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_searchChanged)
      ..dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _searchChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final destinations =
        _destinations(context)
            .where(
              (destination) =>
                  widget.allowSessionLifecycleActions ||
                  destination.id != 'mithka-account-backup',
            )
            .toList()
          ..sort((a, b) {
            final groupOrder = a.group.compareTo(b.group);
            return groupOrder != 0 ? groupOrder : a.order.compareTo(b.order);
          });
    final query = _searchController.text.trim().toLowerCase();
    final matches = query.isEmpty
        ? const <_SettingsDestination>[]
        : destinations.where((item) => item.matches(context, query)).toList();

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
            _searchFocusNode.requestFocus,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _searchFocusNode.requestFocus,
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final useSplit = size.isFinite && usesAdaptiveSplitLayout(size);
          if (useSplit) {
            return _splitSettings(
              context,
              destinations: destinations,
              query: query,
              matches: matches,
            );
          }
          return _compactSettings(
            context,
            destinations: destinations,
            query: query,
            matches: matches,
          );
        },
      ),
    );
  }

  Widget _compactSettings(
    BuildContext context, {
    required List<_SettingsDestination> destinations,
    required String query,
    required List<_SettingsDestination> matches,
  }) {
    return SettingsPageScaffold(
      key: const ValueKey('settings-compact-layout'),
      title: AppStrings.t(AppStringKeys.profileSettings),
      showBackButton: widget.showBackButton,
      onBack: () => Navigator.of(context).pop(),
      child: Column(
        children: [
          _searchField(context),
          Expanded(
            child: query.isEmpty
                ? _settingsList(context, destinations)
                : _searchResults(context, matches),
          ),
        ],
      ),
    );
  }

  Widget _splitSettings(
    BuildContext context, {
    required List<_SettingsDestination> destinations,
    required String query,
    required List<_SettingsDestination> matches,
  }) {
    final c = context.colors;
    final categories = _settingsCategories(destinations);
    final selected = categories.firstWhere(
      (category) => category.id == _selectedCategoryId,
      orElse: () => categories.first,
    );
    final sidebarWidth = MediaQuery.sizeOf(context).width >= 1180
        ? 312.0
        : 280.0;
    final sidebarColor = Color.alphaBlend(
      c.linkBlue.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? 0.055 : 0.035,
      ),
      c.panelBackground,
    );

    return Scaffold(
      key: const ValueKey('settings-split-layout'),
      backgroundColor: c.groupedBackground,
      body: SafeArea(
        bottom: false,
        child: Row(
          children: [
            SizedBox(
              key: const ValueKey('settings-category-sidebar'),
              width: sidebarWidth,
              child: ColoredBox(
                color: sidebarColor,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _splitSidebarHeader(context),
                    _searchField(context, compact: true),
                    Expanded(
                      child: ListView(
                        key: const PageStorageKey<String>(
                          'settings-category-list',
                        ),
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.sm,
                          AppSpacing.md,
                          AppSpacing.xl,
                        ),
                        children: query.isEmpty
                            ? _sidebarTree(context, categories, selected)
                            : _sidebarMatches(context, matches),
                      ),
                    ),
                    // Signing out belongs to the account, not to any one
                    // section, so it sits under the tree rather than inside a
                    // category's screen.
                    if (widget.allowSessionLifecycleActions)
                      _sidebarLogOut(context),
                  ],
                ),
              ),
            ),
            Container(width: AppMetric.divider, color: c.divider),
            Expanded(
              child: ColoredBox(
                color: c.groupedBackground,
                child: _splitDetailNavigator(
                  context,
                  selected: selected,
                  query: query,
                  matches: matches,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _splitSidebarHeader(BuildContext context) {
    final c = context.colors;
    final desktopDense = !kIsWeb && isDesktopTargetPlatform();
    return Container(
      constraints: BoxConstraints(minHeight: desktopDense ? 48 : 58),
      padding: EdgeInsets.fromLTRB(
        desktopDense ? 14 : AppSpacing.lg,
        desktopDense ? 8 : AppSpacing.md,
        desktopDense ? 14 : AppSpacing.lg,
        desktopDense ? 4 : AppSpacing.xs,
      ),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          if (widget.showBackButton && Navigator.of(context).canPop()) ...[
            AppInteractiveSurface(
              key: const ValueKey('settings-root-back'),
              semanticLabel: AppStringKeys.navigationBack.l10n(context),
              onTap: () => Navigator.of(context).pop(),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: AppIcon(
                  HeroAppIcons.chevronLeft,
                  size: AppIconSize.nav,
                  color: c.textPrimary,
                ),
              ),
            ),
            SizedBox(width: desktopDense ? 4 : AppSpacing.xs),
          ],
          Expanded(
            child: Text(
              AppStringKeys.profileSettings.l10n(context),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: desktopDense
                  ? TextStyle(
                      color: c.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    )
                  : AppTextStyle.title(c.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  /// The sidebar as a nested list: categories, each expanding in place to show
  /// its own screens.
  ///
  /// A category holding a single screen is a leaf — expanding to reveal one
  /// child that repeats its parent's name would be noise.
  List<Widget> _sidebarTree(
    BuildContext context,
    List<_SettingsCategory> categories,
    _SettingsCategory selected,
  ) {
    final rows = <Widget>[];
    for (final category in categories) {
      final isLeaf = category.destinations.length == 1;
      final isSelectedCategory = category.id == selected.id;
      final expanded = !isLeaf && _expandedCategoryIds.contains(category.id);

      rows.add(
        _sidebarRow(
          context,
          key: ValueKey('settings-category-${category.id}'),
          label: category.titleKey.l10n(context),
          icon: category.icon,
          // A leaf highlights only while its screen is the one on show.
          selected:
              isLeaf &&
              isSelectedCategory &&
              _selectedDestinationId == category.destinations.single.id,
          expanded: isLeaf ? null : expanded,
          onTap: () => isLeaf
              ? _selectDestination(category, category.destinations.single)
              : _toggleCategory(category),
        ),
      );

      if (!expanded) continue;
      for (final destination in category.destinations) {
        rows.add(
          _sidebarRow(
            context,
            key: ValueKey('settings-child-${destination.id}'),
            label: destination.titleKey.l10n(context),
            icon: destination.icon,
            selected: _selectedDestinationId == destination.id,
            indented: true,
            onTap: () => _selectDestination(category, destination),
          ),
        );
      }
    }
    return rows;
  }

  /// Search replaces the tree with its matches; the grouping is not what the
  /// user is navigating by at that point.
  List<Widget> _sidebarMatches(
    BuildContext context,
    List<_SettingsDestination> matches,
  ) {
    if (matches.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xl,
          ),
          child: Text(
            AppStringKeys.settingsNoResults.l10n(context),
            style: AppTextStyle.footnote(context.colors.textTertiary),
          ),
        ),
      ];
    }
    return [
      for (final destination in matches)
        _sidebarRow(
          context,
          key: ValueKey('settings-match-${destination.id}'),
          label: destination.titleKey.l10n(context),
          icon: destination.icon,
          selected: _selectedDestinationId == destination.id,
          onTap: () => _selectDestination(
            _categoryFor(destination) ??
                _settingsCategories([destination]).first,
            destination,
          ),
        ),
    ];
  }

  /// One sidebar row, at either level.
  ///
  /// [expanded] non-null draws a disclosure chevron, which is what separates a
  /// category from a screen.
  Widget _sidebarRow(
    BuildContext context, {
    required Key key,
    required String label,
    required AppIconData icon,
    required bool selected,
    required VoidCallback onTap,
    bool? expanded,
    bool indented = false,
  }) {
    final c = context.colors;
    final desktopDense = !kIsWeb && isDesktopTargetPlatform();
    final foreground = selected ? c.linkBlue : c.textSecondary;
    final radius = BorderRadius.circular(desktopDense ? 7 : 9);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: AppInteractiveSurface(
        key: key,
        semanticLabel: label,
        selected: selected,
        onTap: onTap,
        borderRadius: radius,
        child: AnimatedContainer(
          duration: AppMotion.duration(context, AppMotion.responsive),
          curve: AppMotion.standard,
          constraints: BoxConstraints(minHeight: desktopDense ? 34 : 42),
          padding: EdgeInsets.fromLTRB(
            (desktopDense ? 10 : AppSpacing.lg) + (indented ? 18 : 0),
            desktopDense ? 6 : AppSpacing.md,
            desktopDense ? 8 : AppSpacing.lg,
            desktopDense ? 6 : AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: selected
                ? c.linkBlue.withValues(alpha: 0.13)
                : Colors.transparent,
            borderRadius: radius,
          ),
          child: Row(
            children: [
              AppIcon(icon, size: desktopDense ? 16 : 19, color: foreground),
              SizedBox(width: desktopDense ? 9 : AppSpacing.lg),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? c.textPrimary : foreground,
                    fontSize: desktopDense ? 13.5 : AppTextSize.body,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              if (expanded != null) ...[
                const SizedBox(width: AppSpacing.sm),
                AnimatedRotation(
                  duration: AppMotion.duration(context, AppMotion.quick),
                  curve: AppMotion.standard,
                  turns: expanded ? 0.25 : 0,
                  child: AppIcon(
                    HeroAppIcons.chevronRight,
                    size: desktopDense ? 12 : 14,
                    color: c.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sidebarLogOut(BuildContext context) {
    final c = context.colors;
    final desktopDense = !kIsWeb && isDesktopTargetPlatform();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(height: AppMetric.divider, color: c.divider),
          const SizedBox(height: AppSpacing.md),
          AppInteractiveSurface(
            key: const ValueKey('settings-log-out'),
            semanticLabel: AppStrings.t(AppStringKeys.settingsLogOut),
            onTap: () => unawaited(
              context.read<AccountStore>().logOutActive(
                context.read<AuthManager>(),
              ),
            ),
            borderRadius: BorderRadius.circular(desktopDense ? 7 : 9),
            child: Container(
              constraints: BoxConstraints(minHeight: desktopDense ? 34 : 42),
              padding: EdgeInsets.symmetric(
                horizontal: desktopDense ? 10 : AppSpacing.lg,
                vertical: desktopDense ? 6 : AppSpacing.md,
              ),
              child: Row(
                children: [
                  AppIcon(
                    HeroAppIcons.rightFromBracket,
                    size: desktopDense ? 16 : 19,
                    color: AppTheme.tagRed,
                  ),
                  SizedBox(width: desktopDense ? 9 : AppSpacing.lg),
                  Expanded(
                    child: Text(
                      AppStrings.t(AppStringKeys.settingsLogOut),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.tagRed,
                        fontSize: desktopDense ? 13.5 : AppTextSize.body,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  _SettingsCategory? _categoryFor(_SettingsDestination destination) {
    for (final definition in _settingsCategoryDefinitions) {
      if (!definition.destinationIds.contains(destination.id)) continue;
      return _SettingsCategory(
        id: definition.id,
        titleKey: definition.titleKey,
        icon: definition.icon,
        destinations: [destination],
      );
    }
    return null;
  }

  void _toggleCategory(_SettingsCategory category) {
    setState(() {
      if (!_expandedCategoryIds.remove(category.id)) {
        _expandedCategoryIds.add(category.id);
      }
      _selectedCategoryId = category.id;
    });
  }

  void _selectDestination(
    _SettingsCategory category,
    _SettingsDestination destination,
  ) {
    setState(() {
      _selectedCategoryId = category.id;
      _selectedDestinationId = destination.id;
      _expandedCategoryIds.add(category.id);
    });
  }

  Widget _splitDetailNavigator(
    BuildContext context, {
    required _SettingsCategory selected,
    required String query,
    required List<_SettingsDestination> matches,
  }) {
    // The sidebar now names every screen, so the detail pane shows the chosen
    // one rather than a list that repeats what is already on the left.
    final chosen = _resolveSelected(selected, query: query, matches: matches);
    // The placeholder stays outside the Navigator: its identity used to carry
    // the raw search query, so every keystroke deactivated and re-inflated a
    // whole nested Navigator + route subtree.
    if (chosen == null) {
      return KeyedSubtree(
        key: const ValueKey('settings-detail-empty'),
        child: _splitPlaceholder(
          context,
          titleKey: query.isEmpty
              ? selected.titleKey
              : AppStringKeys.settingsSearchHint,
          messageKey: query.isEmpty
              ? AppStringKeys.settingsChooseSection
              : AppStringKeys.settingsNoResults,
        ),
      );
    }
    return KeyedSubtree(
      key: ValueKey('settings-detail-${chosen.id}'),
      child: Navigator(
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (_) => SettingsSplitPaneScope(
            child: (chosen.splitDestination ?? chosen.destination)(),
          ),
        ),
      ),
    );
  }

  /// The destination the detail pane should show, if any.
  _SettingsDestination? _resolveSelected(
    _SettingsCategory selected, {
    required String query,
    required List<_SettingsDestination> matches,
  }) {
    final pool = query.isEmpty ? selected.destinations : matches;
    if (pool.isEmpty) return null;
    for (final destination in pool) {
      if (destination.id == _selectedDestinationId) return destination;
    }
    // A single-screen category needs no explicit pick to show its screen.
    if (query.isEmpty && pool.length == 1) return pool.single;
    return null;
  }

  Widget _splitPlaceholder(
    BuildContext context, {
    required String titleKey,
    required String messageKey,
  }) {
    final c = context.colors;
    return SettingsPageScaffold(
      key: const ValueKey('settings-split-placeholder'),
      title: titleKey,
      showBackButton: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.section),
          child: Text(
            messageKey.l10n(context),
            textAlign: TextAlign.center,
            style: AppTextStyle.body(c.textSecondary),
          ),
        ),
      ),
    );
  }

  List<_SettingsDestination> _destinations(BuildContext context) {
    final developer = context.watch<DeveloperModeController>();
    final pro = context.watch<MithkaProService>();
    return [
      _SettingsDestination(
        id: 'notifications',
        group: 2,
        order: 0,
        titleKey: AppStringKeys.notificationNotifications,
        icon: HeroAppIcons.solidBell,
        color: const Color(0xFFF5A623),
        destination: () => const NotificationSettingsView(),
        splitDestination: () =>
            const NotificationSettingsView(showBackButton: false),
        searchTerms: const [
          'alerts',
          'private messages',
          'groups',
          'channels',
          'stories',
          'reactions',
          'in-app notifications',
          'this device',
          'on-device',
          'vibrate',
          'preview',
          'lock screen',
          'accounts',
          'telegram account',
        ],
      ),
      _SettingsDestination(
        id: 'telegram-privacy',
        owner: _SettingsOwner.telegram,
        group: 2,
        order: 20,
        titleKey: AppStringKeys.privacySecurityTitle,
        icon: HeroAppIcons.shieldHalved,
        color: const Color(0xFF16B05A),
        destination: () => const PrivacySecurityView(),
        searchTerms: const [
          'privacy',
          'security',
          '2fa',
          'password',
          'sessions',
          'devices',
          'passkeys',
          'delete account',
        ],
      ),
      _SettingsDestination(
        id: 'telegram-blocked-users',
        owner: _SettingsOwner.telegram,
        group: 2,
        order: 30,
        titleKey: AppStringKeys.blockingBlocklist,
        icon: HeroAppIcons.ban,
        color: const Color(0xFFDA405B),
        destination: () => const BlockedUsersView(),
        searchTerms: const ['blocked users', 'blocklist', 'unblock'],
      ),
      _SettingsDestination(
        id: 'telegram-chat-folders',
        owner: _SettingsOwner.telegram,
        group: 3,
        order: 10,
        titleKey: AppStringKeys.appearanceChatFolders,
        icon: HeroAppIcons.solidFolder,
        color: const Color(0xFF34A2DF),
        destination: () => const ChatFolderManagementView(),
        searchTerms: const ['folders', 'tabs', 'chat lists', 'organize'],
      ),
      _SettingsDestination(
        id: 'telegram-language',
        owner: _SettingsOwner.telegram,
        group: 4,
        order: 10,
        titleKey: AppStringKeys.languageMithkaLanguage,
        icon: HeroAppIcons.globe,
        color: const Color(0xFF34A2DF),
        destination: () => const AppLanguageSettingsView(),
        searchTerms: const [
          'language pack',
          'telegram text',
          'app language',
          'interface language',
          'locale',
        ],
      ),
      if (pro.storeAvailable)
        _SettingsDestination(
          id: 'mithka-pro',
          owner: _SettingsOwner.mithka,
          group: 1,
          order: 0,
          titleKey: AppStringKeys.mithkaProTitle,
          icon: HeroAppIcons.solidStar,
          color: const Color(0xFF7C5CFC),
          destination: () => const MithkaProView(),
          trailingKey: pro.isPro ? AppStringKeys.mithkaProActive : null,
          platformNeutralRoute: true,
          searchTerms: const ['pro', 'support', 'subscription'],
        ),
      _SettingsDestination(
        id: 'mithka-theme',
        owner: _SettingsOwner.mithka,
        group: 3,
        order: 0,
        titleKey: AppStringKeys.appearanceTheme,
        icon: HeroAppIcons.palette,
        color: const Color(0xFF6C5CE7),
        destination: () => const ThemeSettingsView(),
        searchTerms: const ['theme', 'colors', 'wallpaper', 'background'],
      ),
      _SettingsDestination(
        id: 'mithka-appearance',
        owner: _SettingsOwner.mithka,
        group: 3,
        order: 5,
        titleKey: AppStringKeys.appearanceSize,
        icon: HeroAppIcons.wandMagicSparkles,
        color: const Color(0xFF8E7BFF),
        destination: () => const AppearanceView(),
        searchTerms: const [
          'theme',
          'font',
          'icon',
          'wallpaper',
          'bubbles',
          'message bubbles',
          'show message bubbles',
          'disable message bubbles',
          'interface',
        ],
      ),
      _SettingsDestination(
        id: 'mithka-translation',
        owner: _SettingsOwner.mithka,
        group: 4,
        order: 20,
        titleKey: AppStringKeys.translationSettingsTitle,
        icon: HeroAppIcons.comment,
        color: const Color(0xFF16B0A0),
        destination: () => const TranslationSettingsView(),
        searchTerms: const ['translate', 'languages', 'automatic translation'],
      ),
      _SettingsDestination(
        id: 'mithka-data-storage',
        owner: _SettingsOwner.mithka,
        group: 3,
        order: 30,
        titleKey: AppStringKeys.settingsDataAndStorage,
        icon: HeroAppIcons.compactDisc,
        color: const Color(0xFF16B0A0),
        destination: () => const StorageUsageView(),
        splitDestination: () => const StorageUsageView(showBackButton: false),
        searchTerms: const [
          'data',
          'storage',
          'cache',
          'downloads',
          'network',
          'auto download',
        ],
      ),
      if (!kIsWeb && isDesktopTargetPlatform())
        _SettingsDestination(
          id: 'mithka-hotkeys',
          owner: _SettingsOwner.mithka,
          group: 3,
          order: 40,
          titleKey: AppStringKeys.desktopHotkeysTitle,
          icon: HeroAppIcons.key,
          color: const Color(0xFF7467F0),
          destination: () => const DesktopHotkeySettingsView(),
          splitDestination: () =>
              const DesktopHotkeySettingsView(showBackButton: false),
          searchTerms: const [
            'keyboard',
            'shortcut',
            'hotkey',
            'screenshot',
            'new chat',
            'search',
            'send with enter',
          ],
        ),
      _SettingsDestination(
        id: 'mithka-chat-behavior',
        owner: _SettingsOwner.mithka,
        group: 3,
        order: 20,
        titleKey: AppStringKeys.settingsChatBehavior,
        icon: HeroAppIcons.solidMessage,
        color: const Color(0xFF3C8CF0),
        destination: () => const ChatBehaviorSettingsView(),
        searchTerms: const [
          'chat controls',
          'send with enter',
          'open latest',
          'repeat sender',
          'quick replies',
          'video playback',
        ],
      ),
      _SettingsDestination(
        id: 'mithka-content-filters',
        owner: _SettingsOwner.mithka,
        group: 2,
        order: 40,
        titleKey: AppStringKeys.settingsContentFilters,
        icon: HeroAppIcons.filter,
        color: const Color(0xFFDA405B),
        destination: () => const BlockingSettingsView(),
        searchTerms: const [
          'filter',
          'keywords',
          'countries',
          'hide blocked messages',
        ],
      ),
      _SettingsDestination(
        id: 'mithka-app-lock',
        owner: _SettingsOwner.mithka,
        group: 2,
        order: 50,
        titleKey: AppStringKeys.appLockTitle,
        icon: HeroAppIcons.lock,
        color: const Color(0xFF16B05A),
        destination: () => const AppLockSettingsView(),
        searchTerms: const ['app lock', 'pin', 'gesture', 'biometrics'],
      ),
      _SettingsDestination(
        id: 'mithka-account-backup',
        owner: _SettingsOwner.mithka,
        group: 2,
        order: 60,
        titleKey: AppStringKeys.accountBackupTitle,
        icon: HeroAppIcons.cloudArrowDown,
        color: const Color(0xFF7467F0),
        destination: () => const AccountBackupView(),
        searchTerms: const ['backup', 'restore', 'session', 'export', 'import'],
      ),
      _SettingsDestination(
        id: 'mithka-features',
        owner: _SettingsOwner.mithka,
        group: 5,
        order: 0,
        titleKey: AppStringKeys.featureTitle,
        icon: HeroAppIcons.grip,
        color: const Color(0xFF3C8CF0),
        destination: () => const FeatureSettingsView(),
        searchTerms: const [
          'tabs',
          'channels',
          'moments',
          'community',
          'safety',
        ],
      ),
      _SettingsDestination(
        id: 'mithka-ai',
        owner: _SettingsOwner.mithka,
        group: 5,
        order: 10,
        titleKey: AppStringKeys.aiSettingsTitle,
        icon: HeroAppIcons.cpuChip,
        color: const Color(0xFF7467F0),
        destination: () => const AiSettingsView(),
        searchTerms: const [
          'ai',
          'providers',
          'models',
          'prompts',
          'summary',
          'replies',
        ],
      ),
      _SettingsDestination(
        id: 'mithka-proxy',
        owner: _SettingsOwner.mithka,
        group: 5,
        order: 20,
        titleKey: AppStringKeys.proxyTitle,
        icon: HeroAppIcons.globe,
        color: const Color(0xFF34A2DF),
        destination: () => const ProxyView(),
        searchTerms: const ['proxy', 'socks5', 'http', 'mtproto', 'connection'],
      ),
      _SettingsDestination(
        id: 'mithka-advanced',
        owner: _SettingsOwner.mithka,
        group: 5,
        order: 30,
        titleKey: AppStringKeys.advancedTitle,
        icon: HeroAppIcons.objectGroup,
        color: const Color(0xFF16B0A0),
        destination: () => const AdvancedSettingsView(),
        searchTerms: const [
          'advanced',
          'relay',
          'transfer boost',
          'bot api',
          'telegram api endpoint',
        ],
      ),
      if (developer.unlocked)
        _SettingsDestination(
          id: 'mithka-developer',
          owner: _SettingsOwner.mithka,
          group: 5,
          order: 40,
          titleKey: AppStringKeys.developerModeTitle,
          icon: HeroAppIcons.code,
          color: const Color(0xFFFF5A5F),
          destination: () => const DeveloperSettingsView(),
          searchTerms: const [
            'developer',
            'api credentials',
            'tdlib identity',
            'performance',
          ],
        ),
      _SettingsDestination(
        id: 'mithka-about',
        owner: _SettingsOwner.mithka,
        group: 5,
        order: 50,
        titleKey: AppStringKeys.settingsAboutMithka,
        icon: HeroAppIcons.circleInfo,
        color: const Color(0xFF8E8E93),
        destination: () => const AboutView(),
        splitDestination: () => const AboutView(showBackButton: false),
        showsVersion: true,
        searchTerms: const ['about', 'version', 'feedback', 'github'],
      ),
    ];
  }

  Widget _searchField(BuildContext context, {bool compact = false}) {
    final desktopDense = compact && !kIsWeb && isDesktopTargetPlatform();
    return Padding(
      padding: compact
          ? EdgeInsets.fromLTRB(
              desktopDense ? 12 : AppSpacing.lg,
              desktopDense ? 6 : AppSpacing.sm,
              desktopDense ? 12 : AppSpacing.lg,
              desktopDense ? 8 : AppSpacing.md,
            )
          : const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
      child: SettingsSearchField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        hintText: AppStringKeys.settingsSearchHint,
        compact: desktopDense,
      ),
    );
  }

  Widget _settingsList(
    BuildContext context,
    List<_SettingsDestination> destinations,
  ) {
    return ListView(
      key: const PageStorageKey<String>('settings-list'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.section,
      ),
      children: [
        ..._groupCards(context, destinations),
        if (widget.allowSessionLifecycleActions) ...[
          const SizedBox(height: AppSpacing.xl),
          _logoutCard(context),
        ],
      ],
    );
  }

  List<Widget> _groupCards(
    BuildContext context,
    List<_SettingsDestination> destinations,
  ) {
    final groups = <int, List<_SettingsDestination>>{};
    for (final destination in destinations) {
      groups.putIfAbsent(destination.group, () => []).add(destination);
    }
    final widgets = <Widget>[];
    final groupIds = groups.keys.toList()..sort();
    for (final groupId in groupIds) {
      if (widgets.isNotEmpty) {
        widgets.add(const SizedBox(height: AppSpacing.xl));
      }
      widgets.add(_destinationCard(context, groups[groupId]!));
    }
    return widgets;
  }

  Widget _searchResults(
    BuildContext context,
    List<_SettingsDestination> matches,
  ) {
    if (matches.isEmpty) {
      return Center(
        key: const ValueKey('settings-search-empty'),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.section),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                HeroAppIcons.magnifyingGlass,
                size: 28,
                color: context.colors.textTertiary,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                AppStringKeys.settingsNoResults.l10n(context),
                textAlign: TextAlign.center,
                style: AppTextStyle.body(context.colors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      key: const PageStorageKey<String>('settings-search-results'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.section,
      ),
      children: [_destinationCard(context, matches, showOwner: true)],
    );
  }

  Widget _destinationCard(
    BuildContext context,
    List<_SettingsDestination> destinations, {
    bool showOwner = false,
    ValueChanged<_SettingsDestination>? onOpen,
  }) {
    final children = <Widget>[];
    for (var i = 0; i < destinations.length; i++) {
      if (i > 0) {
        children.add(
          const InsetDivider(leadingInset: AppMetric.settingsIconDividerInset),
        );
      }
      children.add(
        _destinationRow(
          context,
          destinations[i],
          showOwner: showOwner,
          onOpen: onOpen,
        ),
      );
    }
    return SettingsCard(children: children);
  }

  Widget _destinationRow(
    BuildContext context,
    _SettingsDestination destination, {
    required bool showOwner,
    ValueChanged<_SettingsDestination>? onOpen,
  }) {
    Widget row(String? version) => SettingsRow(
      key: ValueKey('settings-destination-${destination.id}'),
      title: destination.titleKey,
      value: showOwner
          ? destination.owner?.titleKey ?? ''
          : destination.trailingKey ?? version ?? '',
      leading: SettingsIconTile(
        icon: destination.icon,
        backgroundColor: destination.color,
      ),
      onTap: () {
        if (onOpen != null) {
          onOpen(destination);
        } else {
          _openDestination(destination);
        }
      },
    );

    if (!destination.showsVersion) return row(null);
    return FutureBuilder<AppVersion>(
      future: _versionFuture,
      builder: (context, snapshot) =>
          row(showOwner ? null : 'v${snapshot.data?.version ?? '...'}'),
    );
  }

  void _openDestination(
    _SettingsDestination destination, {
    BuildContext? context,
  }) {
    Navigator.of(context ?? this.context).push(
      destination.platformNeutralRoute
          ? AppPageRoute<void>(
              pageBuilder: (_, _, _) => destination.destination(),
            )
          : MaterialPageRoute<void>(builder: (_) => destination.destination()),
    );
  }

  Widget _logoutCard(BuildContext context) {
    return AppInteractiveSurface(
      key: const ValueKey('settings-log-out'),
      semanticLabel: AppStrings.t(AppStringKeys.settingsLogOut),
      onTap: () {
        final navigator = Navigator.of(context);
        if (navigator.canPop()) navigator.pop();
        unawaited(
          context.read<AccountStore>().logOutActive(
            context.read<AuthManager>(),
          ),
        );
      },
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: SettingsPanel(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxl,
          vertical: AppSpacing.md,
        ),
        child: Text(
          AppStrings.t(AppStringKeys.settingsLogOut),
          textAlign: TextAlign.center,
          style: AppTextStyle.body(AppTheme.tagRed),
        ),
      ),
    );
  }
}

enum _SettingsOwner {
  telegram(AppStringKeys.settingsScopeTelegram),
  mithka(AppStringKeys.settingsScopeMithka);

  const _SettingsOwner(this.titleKey);

  final String titleKey;
}

List<_SettingsCategory> _settingsCategories(
  List<_SettingsDestination> destinations,
) {
  final byId = {
    for (final destination in destinations) destination.id: destination,
  };
  return _settingsCategoryDefinitions
      .map(
        (definition) => _SettingsCategory(
          id: definition.id,
          titleKey: definition.titleKey,
          icon: definition.icon,
          destinations: [for (final id in definition.destinationIds) ?byId[id]],
        ),
      )
      .where((category) => category.destinations.isNotEmpty)
      .toList(growable: false);
}

const _settingsCategoryDefinitions = <_SettingsCategoryDefinition>[
  _SettingsCategoryDefinition(
    id: 'general',
    titleKey: AppStringKeys.generalTitle,
    icon: HeroAppIcons.gear,
    destinationIds: ['mithka-pro'],
  ),
  _SettingsCategoryDefinition(
    id: 'notifications',
    titleKey: AppStringKeys.notificationNotifications,
    icon: HeroAppIcons.solidBell,
    destinationIds: ['notifications'],
  ),
  _SettingsCategoryDefinition(
    id: 'privacy',
    titleKey: AppStringKeys.privacySecurityTitle,
    icon: HeroAppIcons.shieldHalved,
    destinationIds: [
      'telegram-privacy',
      'telegram-blocked-users',
      'mithka-content-filters',
      'mithka-app-lock',
      'mithka-account-backup',
    ],
  ),
  _SettingsCategoryDefinition(
    id: 'appearance',
    titleKey: AppStringKeys.appearanceTitle,
    icon: HeroAppIcons.wandMagicSparkles,
    destinationIds: [
      'mithka-theme',
      'mithka-appearance',
      'mithka-chat-behavior',
    ],
  ),
  _SettingsCategoryDefinition(
    id: 'chat-folders',
    titleKey: AppStringKeys.appearanceChatFolders,
    icon: HeroAppIcons.solidFolder,
    destinationIds: ['telegram-chat-folders'],
  ),
  _SettingsCategoryDefinition(
    id: 'data-storage',
    titleKey: AppStringKeys.settingsDataAndStorage,
    icon: HeroAppIcons.compactDisc,
    destinationIds: ['mithka-data-storage'],
  ),
  _SettingsCategoryDefinition(
    id: 'hotkeys',
    titleKey: AppStringKeys.desktopHotkeysTitle,
    icon: HeroAppIcons.key,
    destinationIds: ['mithka-hotkeys'],
  ),
  _SettingsCategoryDefinition(
    id: 'language',
    titleKey: AppStringKeys.languageTitle,
    icon: HeroAppIcons.language,
    destinationIds: ['telegram-language', 'mithka-translation'],
  ),
  _SettingsCategoryDefinition(
    id: 'advanced',
    titleKey: AppStringKeys.advancedTitle,
    icon: HeroAppIcons.grip,
    destinationIds: [
      'mithka-features',
      'mithka-ai',
      'mithka-proxy',
      'mithka-advanced',
      'mithka-developer',
    ],
  ),
  _SettingsCategoryDefinition(
    id: 'about',
    titleKey: AppStringKeys.settingsAboutMithka,
    icon: HeroAppIcons.circleInfo,
    destinationIds: ['mithka-about'],
  ),
];

class _SettingsCategoryDefinition {
  const _SettingsCategoryDefinition({
    required this.id,
    required this.titleKey,
    required this.icon,
    required this.destinationIds,
  });

  final String id;
  final String titleKey;
  final AppIconData icon;
  final List<String> destinationIds;
}

class _SettingsCategory {
  const _SettingsCategory({
    required this.id,
    required this.titleKey,
    required this.icon,
    required this.destinations,
  });

  final String id;
  final String titleKey;
  final AppIconData icon;
  final List<_SettingsDestination> destinations;
}

class _SettingsDestination {
  const _SettingsDestination({
    required this.id,
    required this.group,
    required this.order,
    required this.titleKey,
    required this.icon,
    required this.color,
    required this.destination,
    this.splitDestination,
    this.owner,
    this.trailingKey,
    this.platformNeutralRoute = false,
    this.showsVersion = false,
    this.searchTerms = const [],
  });

  final String id;
  final _SettingsOwner? owner;
  final int group;
  final int order;
  final String titleKey;
  final AppIconData icon;
  final Color color;
  final Widget Function() destination;
  final Widget Function()? splitDestination;
  final String? trailingKey;
  final bool platformNeutralRoute;
  final bool showsVersion;
  final List<String> searchTerms;

  bool matches(BuildContext context, String query) {
    final haystack = <String>[
      titleKey.l10n(context),
      if (owner != null) owner!.titleKey.l10n(context),
      id.replaceAll('-', ' '),
      ...searchTerms,
    ].join(' ').toLowerCase();
    return haystack.contains(query);
  }
}
