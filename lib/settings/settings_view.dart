//
//  settings_view.dart
//
//  Settings are grouped by ownership so Telegram account controls are not
//  confused with Mithka preferences stored on this device. Frequently used
//  destinations are linked directly and can be searched from this screen.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app/app_version.dart';
import '../auth/account_store.dart';
import '../auth/auth_manager.dart';
import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/desktop_content_constraint.dart';
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
import 'business_settings_view.dart';
import 'chat_folder_management_view.dart';
import 'developer_mode_controller.dart';
import 'developer_settings_view.dart';
import 'edit_profile_view.dart';
import 'feature_settings_view.dart';
import 'general_settings_view.dart';
import 'language_settings_view.dart';
import 'notification_settings_view.dart';
import 'privacy_detail_views.dart';
import 'privacy_security_view.dart';
import 'proxy_view.dart';
import 'translation_settings_view.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key, this.focusSearch = false});

  /// Used by Telegram's `settingsSectionSearch` internal link.
  final bool focusSearch;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late final Future<AppVersion> _versionFuture = AppVersion.load();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
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
    final c = context.colors;
    final destinations = _destinations(context);
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
      child: Scaffold(
        backgroundColor: c.groupedBackground,
        body: Column(
          children: [
            NavHeader(
              title: AppStrings.t(AppStringKeys.profileSettings),
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: DesktopContentConstraint(
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
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_SettingsDestination> _destinations(BuildContext context) {
    final developer = context.watch<DeveloperModeController>();
    final pro = context.watch<MithkaProService>();
    return [
      _SettingsDestination(
        id: 'edit-profile',
        owner: _SettingsOwner.telegram,
        group: 0,
        titleKey: AppStringKeys.editProfileTitle,
        icon: HeroAppIcons.solidCircleUser,
        color: const Color(0xFF3C8CF0),
        destination: () => const EditProfileView(),
        searchTerms: const ['account', 'name', 'username', 'phone', 'bio'],
      ),
      _SettingsDestination(
        id: 'telegram-business',
        owner: _SettingsOwner.telegram,
        group: 0,
        titleKey: AppStringKeys.businessSettingsTitle,
        icon: HeroAppIcons.venue,
        color: const Color(0xFF7467F0),
        destination: () => const BusinessSettingsView(),
        searchTerms: const [
          'business',
          'hours',
          'location',
          'greeting',
          'away',
          'quick replies',
        ],
      ),
      _SettingsDestination(
        id: 'telegram-notifications',
        owner: _SettingsOwner.telegram,
        group: 1,
        titleKey: AppStringKeys.notificationNotifications,
        icon: HeroAppIcons.solidBell,
        color: const Color(0xFFF5A623),
        destination: () => const NotificationSettingsView(),
        searchTerms: const [
          'alerts',
          'private messages',
          'groups',
          'channels',
          'stories',
          'reactions',
        ],
      ),
      _SettingsDestination(
        id: 'telegram-privacy',
        owner: _SettingsOwner.telegram,
        group: 1,
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
        group: 1,
        titleKey: AppStringKeys.blockingBlocklist,
        icon: HeroAppIcons.ban,
        color: const Color(0xFFDA405B),
        destination: () => const BlockedUsersView(),
        searchTerms: const ['blocked users', 'blocklist', 'unblock'],
      ),
      _SettingsDestination(
        id: 'telegram-chat-folders',
        owner: _SettingsOwner.telegram,
        group: 1,
        titleKey: AppStringKeys.appearanceChatFolders,
        icon: HeroAppIcons.solidFolder,
        color: const Color(0xFF34A2DF),
        destination: () => const ChatFolderManagementView(),
        searchTerms: const ['folders', 'tabs', 'chat lists', 'organize'],
      ),
      _SettingsDestination(
        id: 'telegram-language',
        owner: _SettingsOwner.telegram,
        group: 1,
        titleKey: AppStringKeys.languageTelegramLanguage,
        icon: HeroAppIcons.globe,
        color: const Color(0xFF34A2DF),
        destination: () => const TelegramLanguageSettingsView(),
        searchTerms: const ['language pack', 'telegram text'],
      ),
      _SettingsDestination(
        id: 'mithka-pro',
        owner: _SettingsOwner.mithka,
        group: 0,
        titleKey: AppStringKeys.mithkaProTitle,
        icon: HeroAppIcons.solidStar,
        color: const Color(0xFF7C5CFC),
        destination: () => const MithkaProView(),
        trailingKey: pro.isPro ? AppStringKeys.mithkaProActive : null,
        platformNeutralRoute: true,
        searchTerms: const ['pro', 'support', 'subscription'],
      ),
      _SettingsDestination(
        id: 'mithka-appearance',
        owner: _SettingsOwner.mithka,
        group: 1,
        titleKey: AppStringKeys.appearanceTitle,
        icon: HeroAppIcons.wandMagicSparkles,
        color: const Color(0xFF8E7BFF),
        destination: () => const AppearanceView(),
        searchTerms: const [
          'theme',
          'font',
          'icon',
          'wallpaper',
          'bubbles',
          'interface',
        ],
      ),
      _SettingsDestination(
        id: 'mithka-language',
        owner: _SettingsOwner.mithka,
        group: 1,
        titleKey: AppStringKeys.languageMithkaLanguage,
        icon: HeroAppIcons.language,
        color: const Color(0xFF34A2DF),
        destination: () => const MithkaLanguageSettingsView(),
        searchTerms: const ['app language', 'interface language', 'locale'],
      ),
      _SettingsDestination(
        id: 'mithka-translation',
        owner: _SettingsOwner.mithka,
        group: 1,
        titleKey: AppStringKeys.translationSettingsTitle,
        icon: HeroAppIcons.comment,
        color: const Color(0xFF16B0A0),
        destination: () => const TranslationSettingsView(),
        searchTerms: const ['translate', 'languages', 'automatic translation'],
      ),
      _SettingsDestination(
        id: 'mithka-notifications',
        owner: _SettingsOwner.mithka,
        group: 2,
        titleKey: AppStringKeys.notificationOnDeviceTitle,
        icon: HeroAppIcons.bell,
        color: const Color(0xFFF5A623),
        destination: () => const MithkaNotificationSettingsView(),
        searchTerms: const [
          'in-app notifications',
          'vibrate',
          'preview',
          'lock screen',
          'accounts',
        ],
      ),
      _SettingsDestination(
        id: 'mithka-data-storage',
        owner: _SettingsOwner.mithka,
        group: 2,
        titleKey: AppStringKeys.settingsDataAndStorage,
        icon: HeroAppIcons.compactDisc,
        color: const Color(0xFF16B0A0),
        destination: () => const GeneralSettingsView(),
        searchTerms: const [
          'data',
          'storage',
          'cache',
          'downloads',
          'network',
          'auto download',
        ],
      ),
      _SettingsDestination(
        id: 'mithka-chat-behavior',
        owner: _SettingsOwner.mithka,
        group: 2,
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
        titleKey: AppStringKeys.accountBackupTitle,
        icon: HeroAppIcons.cloudArrowDown,
        color: const Color(0xFF7467F0),
        destination: () => const AccountBackupView(),
        searchTerms: const ['backup', 'restore', 'session', 'export', 'import'],
      ),
      _SettingsDestination(
        id: 'mithka-features',
        owner: _SettingsOwner.mithka,
        group: 3,
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
        group: 3,
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
        group: 3,
        titleKey: AppStringKeys.proxyTitle,
        icon: HeroAppIcons.globe,
        color: const Color(0xFF34A2DF),
        destination: () => const ProxyView(),
        searchTerms: const ['proxy', 'socks5', 'http', 'mtproto', 'connection'],
      ),
      _SettingsDestination(
        id: 'mithka-advanced',
        owner: _SettingsOwner.mithka,
        group: 3,
        titleKey: AppStringKeys.advancedTitle,
        icon: HeroAppIcons.objectGroup,
        color: const Color(0xFF16B0A0),
        destination: () => const AdvancedSettingsView(),
        searchTerms: const ['advanced', 'relay', 'transfer boost'],
      ),
      if (developer.unlocked)
        _SettingsDestination(
          id: 'mithka-developer',
          owner: _SettingsOwner.mithka,
          group: 3,
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
        group: 3,
        titleKey: AppStringKeys.settingsAboutMithka,
        icon: HeroAppIcons.circleInfo,
        color: const Color(0xFF8E8E93),
        destination: () => const AboutView(),
        showsVersion: true,
        searchTerms: const ['about', 'version', 'feedback', 'github'],
      ),
    ];
  }

  Widget _searchField(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Container(
        key: const ValueKey('settings-search-container'),
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: c.searchFill,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Row(
          children: [
            AppIcon(
              HeroAppIcons.magnifyingGlass,
              size: AppMetric.searchIcon,
              color: c.textTertiary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: TextField(
                key: const ValueKey('settings-search-field'),
                controller: _searchController,
                focusNode: _searchFocusNode,
                textInputAction: TextInputAction.search,
                style: TextStyle(
                  fontSize: AppTextSize.callout,
                  color: c.textPrimary,
                ),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: AppStringKeys.settingsSearchHint.l10n(context),
                  hintStyle: TextStyle(
                    fontSize: AppTextSize.callout,
                    color: c.textTertiary,
                  ),
                ),
              ),
            ),
            if (_searchController.text.isNotEmpty)
              AppInteractiveSurface(
                semanticLabel: AppStringKeys.countryPickerCancel.l10n(context),
                onTap: _searchController.clear,
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
          ],
        ),
      ),
    );
  }

  Widget _settingsList(
    BuildContext context,
    List<_SettingsDestination> destinations,
  ) {
    final telegram = destinations
        .where((item) => item.owner == _SettingsOwner.telegram)
        .toList();
    final mithka = destinations
        .where((item) => item.owner == _SettingsOwner.mithka)
        .toList();
    return ListView(
      key: const PageStorageKey<String>('settings-owner-list'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.section,
      ),
      children: [
        _scopeHeader(
          key: const ValueKey('settings-section-telegram'),
          title: AppStringKeys.settingsScopeTelegram.l10n(context),
          description: AppStringKeys.settingsScopeTelegramDescription.l10n(
            context,
          ),
          icon: HeroAppIcons.solidPaperPlane,
          color: const Color(0xFF3295F6),
        ),
        ..._groupCards(context, telegram),
        const SizedBox(height: AppSpacing.xl),
        _logoutCard(context),
        const SizedBox(height: 30),
        _scopeHeader(
          key: const ValueKey('settings-section-mithka'),
          title: AppStringKeys.settingsScopeMithka.l10n(context),
          description: AppStringKeys.settingsScopeMithkaDescription.l10n(
            context,
          ),
          icon: HeroAppIcons.wandMagicSparkles,
          color: const Color(0xFF7C5CFC),
        ),
        ..._groupCards(context, mithka),
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
    for (final group in groups.values) {
      if (widgets.isNotEmpty) {
        widgets.add(const SizedBox(height: AppSpacing.xl));
      }
      widgets.add(_destinationCard(context, group));
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

  Widget _scopeHeader({
    required Key key,
    required String title,
    required String description,
    required AppIconData icon,
    required Color color,
  }) {
    final c = context.colors;
    return Semantics(
      key: key,
      header: true,
      container: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsIconTile(
              icon: icon,
              backgroundColor: color,
              size: 34,
              iconSize: 18,
              radius: AppRadius.control,
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: AppTextWeight.semibold,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: AppTextSize.footnote,
                      height: 1.3,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _destinationCard(
    BuildContext context,
    List<_SettingsDestination> destinations, {
    bool showOwner = false,
  }) {
    final children = <Widget>[];
    for (var i = 0; i < destinations.length; i++) {
      if (i > 0) {
        children.add(
          const InsetDivider(leadingInset: AppMetric.settingsIconDividerInset),
        );
      }
      children.add(
        _destinationRow(context, destinations[i], showOwner: showOwner),
      );
    }
    return SettingsCard(children: children);
  }

  Widget _destinationRow(
    BuildContext context,
    _SettingsDestination destination, {
    required bool showOwner,
  }) {
    Widget row(String? version) => SettingsRow(
      key: ValueKey('settings-destination-${destination.id}'),
      title: destination.titleKey,
      value: showOwner
          ? destination.owner.titleKey
          : destination.trailingKey ?? version ?? '',
      leading: SettingsIconTile(
        icon: destination.icon,
        backgroundColor: destination.color,
      ),
      onTap: () => _openDestination(destination),
    );

    if (!destination.showsVersion) return row(null);
    return FutureBuilder<AppVersion>(
      future: _versionFuture,
      builder: (context, snapshot) =>
          row(showOwner ? null : 'v${snapshot.data?.version ?? '...'}'),
    );
  }

  void _openDestination(_SettingsDestination destination) {
    Navigator.of(context).push(
      destination.platformNeutralRoute
          ? AppPageRoute<void>(
              pageBuilder: (_, _, _) => destination.destination(),
            )
          : MaterialPageRoute<void>(builder: (_) => destination.destination()),
    );
  }

  Widget _logoutCard(BuildContext context) {
    final c = context.colors;
    return AppInteractiveSurface(
      key: const ValueKey('settings-log-out'),
      semanticLabel: AppStrings.t(AppStringKeys.settingsLogOut),
      onTap: () {
        Navigator.of(context).pop();
        unawaited(
          context.read<AccountStore>().logOutActive(
            context.read<AuthManager>(),
          ),
        );
      },
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        constraints: const BoxConstraints(
          minHeight: AppMetric.settingsRowHeight,
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxl,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
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

class _SettingsDestination {
  const _SettingsDestination({
    required this.id,
    required this.owner,
    required this.group,
    required this.titleKey,
    required this.icon,
    required this.color,
    required this.destination,
    this.trailingKey,
    this.platformNeutralRoute = false,
    this.showsVersion = false,
    this.searchTerms = const [],
  });

  final String id;
  final _SettingsOwner owner;
  final int group;
  final String titleKey;
  final AppIconData icon;
  final Color color;
  final Widget Function() destination;
  final String? trailingKey;
  final bool platformNeutralRoute;
  final bool showsVersion;
  final List<String> searchTerms;

  bool matches(BuildContext context, String query) {
    final haystack = <String>[
      titleKey.l10n(context),
      owner.titleKey.l10n(context),
      id.replaceAll('-', ' '),
      ...searchTerms,
    ].join(' ').toLowerCase();
    return haystack.contains(query);
  }
}
