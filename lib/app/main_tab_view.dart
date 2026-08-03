//
//  main_tab_view.dart
//
//  Tab shell: 消息 / 联系人 / optional 动态, plus the left-sliding "我" profile drawer
//  overlaid above the tab bar. The bottom tab bar is either a custom flat bar
//  ("classic", default) or the system tab bar — chosen in 外观 settings. Port of
//  the Swift `MainTabView`.
//

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/account_store.dart';
import '../auth/auth_manager.dart';
import '../channels/topic_channels_view.dart';
import '../channels/topic_chat_view.dart';
import '../chat/chat_info_view.dart';
import '../chat/chat_members_view.dart';
import '../chat/chat_view.dart';
import '../chat/desktop_chat_context_pane.dart';
import '../chat/music_player_controller.dart';
import '../chats/archived_chats_view.dart';
import '../chats/chat_list_view.dart';
import '../communities/community_view.dart';
import '../components/app_icons.dart';
import '../components/drawer_controller.dart' as dc;
import '../components/ui_components.dart';
import '../contacts/contacts_view.dart';
import '../l10n/app_locale_controller.dart';
import '../l10n/app_localizations.dart';
import '../l10n/telegram_language_controller.dart';
import '../moments/moments_view.dart';
import '../profile/profile_view.dart';
import '../settings/desktop_hotkey_controller.dart';
import '../settings/topic_group_display_mode.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import '../theme/telegram_cloud_theme.dart';
import '../theme/theme_controller.dart';
import '../update/update_checker.dart';
import 'adaptive_split_layout.dart';
import 'app_navigator.dart';
import 'chat_deep_link_controller.dart';
import 'desktop_chat_window.dart';
import 'desktop_navigation_rail.dart';
import 'desktop_utility_window.dart';
import 'detail_content_reveal.dart';
import 'unread_badge_model.dart';

@visibleForTesting
bool desktopChatKindUsesContextPane(ChatKind? kind) =>
    kind == ChatKind.group || kind == ChatKind.channel;

class MainTabView extends StatefulWidget {
  const MainTabView({super.key});

  @override
  State<MainTabView> createState() => _MainTabViewState();
}

class MainSplitRootView extends StatefulWidget {
  const MainSplitRootView({super.key});

  @override
  State<MainSplitRootView> createState() => _MainSplitRootViewState();
}

class _MainTabViewState extends _MainRootViewState<MainTabView> {
  @override
  bool get checkForUpdates => true;
}

class _MainSplitRootViewState extends _MainRootViewState<MainSplitRootView> {}

abstract class _MainRootViewState<T extends StatefulWidget> extends State<T> {
  static const _desktopSidebarWidthKey = 'mithka.desktopSplitSidebarWidth.v1';

  bool get checkForUpdates => false;

  int _selection = 0;
  late final dc.TabBarVisibility _tabBar = dc.TabBarVisibility();
  late final UnreadBadgeModel _unread = UnreadBadgeModel()..start();
  late final ChatListController _chatListController = ChatListController();
  late final ChatViewExitController _messageChatExitController =
      ChatViewExitController();
  ChatListSelection? _selectedMessageChat;
  CommunityListSelection? _selectedMessageCommunity;
  ArchivedChatListSelection? _selectedArchivedChats;
  int? _closedDesktopInfoChatId;
  Widget? _selectedChannelDetail;
  Widget? _selectedContactDetail;
  Widget? _selectedMomentDetail;
  ChatDeepLinkController? _chatDeepLinks;
  AccountStore? _observedAccounts;
  int? _observedAccountSlot;
  double? _splitSidebarWidth;
  bool _splitResizeHandleHovered = false;
  bool? _wasUsingSplitSelection;
  DesktopHotkeyRegistration? _newChatHotkeyRegistration;
  DesktopHotkeyRegistration? _focusSearchHotkeyRegistration;

  @override
  void initState() {
    super.initState();
    if (isDesktopTargetPlatform()) {
      unawaited(_restoreDesktopSidebarWidth());
      _newChatHotkeyRegistration = DesktopHotkeyRegistry.instance.register(
        DesktopHotkeyAction.newChat,
        () => _runChatListHotkey(_chatListController.openNewChat),
      );
      _focusSearchHotkeyRegistration = DesktopHotkeyRegistry.instance.register(
        DesktopHotkeyAction.focusSearch,
        () => _runChatListHotkey(_chatListController.focusSearch),
      );
    }
    // Android-only: check GitHub Releases for a newer same-ABI build (once).
    if (checkForUpdates) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) UpdateChecker.maybePrompt(context);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_synchronizeInstalledCloudThemes());
    });
  }

  Future<void> _restoreDesktopSidebarWidth() async {
    final prefs = await SharedPreferences.getInstance();
    final savedWidth = prefs.getDouble(_desktopSidebarWidthKey);
    if (!mounted || savedWidth == null) return;
    setState(() => _splitSidebarWidth = savedWidth);
  }

  Future<void> _persistDesktopSidebarWidth() async {
    if (!isDesktopTargetPlatform()) return;
    final width = _splitSidebarWidth;
    if (width == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_desktopSidebarWidthKey, width);
  }

  Future<void> _synchronizeInstalledCloudThemes() async {
    final controller = context.read<ThemeController>();
    final themes = await TelegramCloudThemeService().loadInstalled(
      fallback: controller.installedCloudThemes,
    );
    if (!mounted) return;
    controller.synchronizeInstalledCloudThemes(themes);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final usesSplitSelection = _usesSplitSelection(context);
    if (_wasUsingSplitSelection == true && !usesSplitSelection) {
      _messageChatExitController.prepareExit();
      _selectedArchivedChats = null;
    }
    _wasUsingSplitSelection = usesSplitSelection;
    final accounts = context.read<AccountStore>();
    if (!identical(_observedAccounts, accounts)) {
      _observedAccounts?.removeListener(_handleAccountStoreChanged);
      _observedAccounts = accounts;
      _observedAccountSlot = accounts.activeSlot;
      accounts.addListener(_handleAccountStoreChanged);
    }
    final controller = context.read<ChatDeepLinkController>();
    if (identical(_chatDeepLinks, controller)) return;
    _chatDeepLinks?.removeListener(_handlePendingChatDeepLink);
    _chatDeepLinks = controller..addListener(_handlePendingChatDeepLink);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _handlePendingChatDeepLink();
    });
  }

  @override
  void dispose() {
    _newChatHotkeyRegistration?.dispose();
    _focusSearchHotkeyRegistration?.dispose();
    _observedAccounts?.removeListener(_handleAccountStoreChanged);
    _chatDeepLinks?.removeListener(_handlePendingChatDeepLink);
    _chatListController.dispose();
    _unread.dispose();
    _tabBar.dispose();
    super.dispose();
  }

  void _runChatListHotkey(VoidCallback action) {
    if (!mounted) return;
    final size = MediaQuery.sizeOf(context);
    if (usesDesktopShellLayout(size) && !canShowDesktopListPane(size.width)) {
      _clearTabletDetail(0);
    }
    if (_selection != 0) setState(() => _selection = 0);
    action();
  }

  void _handleAccountStoreChanged() {
    final accounts = _observedAccounts;
    if (accounts == null || accounts.activeSlot == _observedAccountSlot) return;
    _messageChatExitController.prepareExit();
    _observedAccountSlot = accounts.activeSlot;
    _closedDesktopInfoChatId = null;
  }

  late final List<GlobalKey<NavigatorState>> _navKeys = List.generate(
    4,
    (_) => GlobalKey<NavigatorState>(),
  );

  static const _allTabs = [
    _MainTabItem(0, AppStringKeys.tabMessages, HeroAppIcons.solidMessage),
    _MainTabItem(1, AppStringKeys.tabChannels, HeroAppIcons.hashtag),
    _MainTabItem(2, AppStringKeys.tabContacts, HeroAppIcons.users),
    _MainTabItem(3, AppStringKeys.tabMoments, HeroAppIcons.circleNotch),
  ];

  List<_MainTabItem> _visibleTabs(ThemeController theme) => [
    _allTabs[0],
    if (theme.showChannelsTab) _allTabs[1],
    _allTabs[2],
    if (theme.showMomentsTab) _allTabs[3],
  ];

  Widget _root(int i) => switch (i) {
    0 => ChatListView(controller: _chatListController),
    1 => const TopicChannelsView(),
    2 => const ContactsView(),
    _ => const MomentsView(),
  };

  Future<bool> _onWillPop() async {
    if (_usesSplitSelection(context)) {
      switch (_selection) {
        case 0:
          if (_selectedArchivedChats != null) {
            setState(() => _selectedArchivedChats = null);
            return false;
          }
          if (_selectedMessageChat != null) {
            _messageChatExitController.prepareExit();
            setState(() => _selectedMessageChat = null);
            return false;
          }
          if (_selectedMessageCommunity != null) {
            setState(() => _selectedMessageCommunity = null);
            return false;
          }
        case 1:
          if (_selectedChannelDetail != null) {
            setState(() => _selectedChannelDetail = null);
            return false;
          }
        case 2:
          if (_selectedContactDetail != null) {
            setState(() => _selectedContactDetail = null);
            return false;
          }
        case 3:
          if (_selectedMomentDetail != null) {
            setState(() => _selectedMomentDetail = null);
            return false;
          }
      }
    }
    final nav = _navKeys[_selection].currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
      return false;
    }
    return true;
  }

  void _select(int i) {
    final theme = context.read<ThemeController>();
    final tabs = _visibleTabs(theme);
    if (i < 0 || i >= tabs.length) return;
    final tabIndex = tabs[i].index;
    final shouldToggleMessages = tabIndex == 0;
    if (tabIndex == _selection) {
      // Tapping the active tab pops to its root.
      if (_usesSplitSelection(context) &&
          tabIndex == 0 &&
          _selectedArchivedChats != null) {
        setState(() => _selectedArchivedChats = null);
        return;
      }
      _navKeys[tabIndex].currentState?.popUntil((r) => r.isFirst);
      if (_usesSplitSelection(context)) _clearTabletDetail(tabIndex);
      if (shouldToggleMessages) _toggleMessagesListTarget(theme);
      return;
    }
    if (_usesSplitSelection(context) && _selection == 0) {
      _messageChatExitController.prepareExit();
    }
    setState(() => _selection = tabIndex);
    if (shouldToggleMessages) _toggleMessagesListTarget(theme);
  }

  void _toggleMessagesListTarget(ThemeController theme) {
    _chatListController.toggleFirstUnreadOrTop(
      mayHaveUnread: _unread.countFor(theme.unreadBadgeMode) > 0,
    );
  }

  void _handlePendingChatDeepLink() {
    if (!mounted) return;
    final request = _chatDeepLinks?.consumePending();
    if (request == null) return;
    _openMessageDeepLink(request);
  }

  void _openMessageDeepLink(ChatDeepLinkRequest request) {
    final accounts = context.read<AccountStore>();
    final requestedSlot =
        request.accountSlot ??
        accounts.summaries
            .where((account) => account.userId == request.accountUserId)
            .map((account) => account.slot)
            .firstOrNull;
    if (requestedSlot != null && requestedSlot != accounts.activeSlot) {
      accounts.switchTo(requestedSlot, context.read<AuthManager>());
      final controller = _chatDeepLinks;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller?.openChat(
          chatId: request.chatId,
          title: request.title,
          messageId: request.messageId,
        );
      });
      return;
    }
    if (_usesSplitSelection(context)) {
      final nextSelection = ChatListSelection(
        chatId: request.chatId,
        title: request.title,
        initialMessageId: request.messageId,
      );
      _prepareMessageChatReplacement(nextSelection);
      setState(() {
        _selection = 0;
        _selectedMessageCommunity = null;
        _selectedMessageChat = nextSelection;
      });
      return;
    }

    setState(() => _selection = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = Navigator.of(context, rootNavigator: true);
      navigator.popUntil((route) => route.isFirst);
      navigator.push(
        AppChatPageRoute(
          builder: (_) => ChatView(
            chatId: request.chatId,
            title: request.title,
            initialMessageId: request.messageId,
          ),
        ),
      );
    });
  }

  void _openDesktopUtility(
    DesktopUtilityWindowKind kind,
    String title, {
    int? chatId,
    int? userId,
    String? initialSettingsCategoryId,
  }) {
    final accounts = context.read<AccountStore>();
    unawaited(
      DesktopUtilityWindowService.instance.open(
        DesktopUtilityWindowArguments(
          kind: kind,
          accountSlot: accounts.activeSlot,
          accountUserId: accounts.activeUserId,
          chatId: chatId,
          userId: userId,
          initialSettingsCategoryId: initialSettingsCategoryId,
          title: title,
          localeTag: Localizations.localeOf(context).toLanguageTag(),
          dark: Theme.of(context).brightness == Brightness.dark,
        ),
      ),
    );
  }

  Future<void> _openDesktopSavedMessages() async {
    final accounts = context.read<AccountStore>();
    var userId = accounts.activeUserId;
    try {
      if (userId == null || userId <= 0) {
        final me = await TdClient.shared.query({'@type': 'getMe'});
        userId = me.int64('id');
      }
      if (userId == null || userId <= 0) return;
      final chat = await TdClient.shared.query({
        '@type': 'createPrivateChat',
        'user_id': userId,
        'force': false,
      });
      final chatId = chat.int64('id') ?? userId;
      if (!mounted) return;
      _openDesktopUtility(
        DesktopUtilityWindowKind.savedMessages,
        AppStrings.t(AppStringKeys.savedMessages),
        chatId: chatId,
      );
    } catch (_) {
      if (!mounted || userId == null || userId <= 0) return;
      _openDesktopUtility(
        DesktopUtilityWindowKind.savedMessages,
        AppStrings.t(AppStringKeys.savedMessages),
        chatId: userId,
      );
    }
  }

  void _clearTabletDetail(int tabIndex) {
    switch (tabIndex) {
      case 0:
        if (_selectedMessageChat != null || _selectedMessageCommunity != null) {
          _messageChatExitController.prepareExit();
          setState(() {
            _selectedMessageChat = null;
            _selectedMessageCommunity = null;
          });
        }
      case 1:
        if (_selectedChannelDetail != null) {
          setState(() => _selectedChannelDetail = null);
        }
      case 2:
        if (_selectedContactDetail != null) {
          setState(() => _selectedContactDetail = null);
        }
      case 3:
        if (_selectedMomentDetail != null) {
          setState(() => _selectedMomentDetail = null);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _tabBar),
        ChangeNotifierProvider.value(value: _unread),
      ],
      // Material ancestor so the tab content (bare Containers) gets a proper
      // DefaultTextStyle instead of the debug red/yellow-underline fallback.
      child: Material(
        type: MaterialType.transparency,
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (!didPop) await _onWillPop();
          },
          child: _rootStack(),
        ),
      ),
    );
  }

  Widget _rootStack() {
    return Stack(children: [_classicTabs(), _drawerOverlay()]);
  }

  // MARK: - Per-tab navigators

  Widget _tabNavigator(int i) {
    return _TabNavigator(
      navigatorKey: _navKeys[i],
      observer: dc.TabDepthObserver(i, _tabBar),
      root: _root(i),
    );
  }

  int _visibleSelection(List<_MainTabItem> tabs) {
    final index = tabs.indexWhere((tab) => tab.index == _selection);
    return index < 0 ? tabs.length - 1 : index;
  }

  Widget _stack(List<_MainTabItem> tabs) => _LazyTabStack(
    selection: _visibleSelection(tabs),
    items: tabs,
    builder: (tab) => _tabNavigator(tab.index),
  );

  // MARK: - Classic (flat) tab bar

  Widget _classicTabs() {
    final theme = context.watch<ThemeController>();
    if (!theme.communitiesEnabled && _selectedMessageCommunity != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            context.read<ThemeController>().communitiesEnabled ||
            _selectedMessageCommunity == null) {
          return;
        }
        setState(() => _selectedMessageCommunity = null);
      });
    }
    final tabs = _visibleTabs(theme);
    if (!tabs.any((tab) => tab.index == _selection)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selection = tabs.last.index);
      });
    }
    final selection = _visibleSelection(tabs);
    final activeTabIndex = tabs[selection].index;
    if (_usesDesktopShell(context)) {
      return _desktopSplitTabs(tabs, selection, activeTabIndex);
    }
    if (_usesTabletSplit(context)) {
      return _tabletSplitTabs(tabs, selection, activeTabIndex);
    }
    return AnimatedBuilder(
      animation: _tabBar,
      builder: (context, _) {
        final showTabBar = _tabBar.depth(activeTabIndex) == 0;
        return Column(
          children: [
            Expanded(child: _musicAwareContent(_stack(tabs))),
            _fixedMusicPlayer(safeBottom: !showTabBar),
            AnimatedSize(
              duration: AppMotion.duration(context, AppMotion.responsive),
              curve: AppMotion.standard,
              alignment: Alignment.bottomCenter,
              child: showTabBar
                  ? AnimatedBuilder(
                      animation: _unread,
                      builder: (context, _) => _ClassicTabBar(
                        selection: selection,
                        onSelect: _select,
                        items: tabs,
                        onClearUnread: _chatListController.markAllRead,
                        unread: _unread.countFor(theme.unreadBadgeMode),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }

  Widget _fixedMusicPlayer({required bool safeBottom}) {
    return AnimatedBuilder(
      animation: MusicPlayerController.shared,
      builder: (context, _) {
        final player = MusicPlayerController.shared;
        return AnimatedSize(
          duration: AppMotion.duration(context, AppMotion.responsive),
          curve: AppMotion.standard,
          child:
              player.isVisible &&
                  !player.collapsed &&
                  !player.hasEmbeddedPlayerHost
              ? GlobalMusicPlayerBar(
                  bottomPadding: safeBottom
                      ? MediaQuery.paddingOf(context).bottom.clamp(0, 12)
                      : 0,
                )
              : const SizedBox.shrink(),
        );
      },
    );
  }

  Widget _musicAwareContent(Widget child, {bool reserveForShellPlayer = true}) {
    return AnimatedBuilder(
      animation: MusicPlayerController.shared,
      child: child,
      builder: (context, child) {
        final player = MusicPlayerController.shared;
        if (!reserveForShellPlayer ||
            !player.isVisible ||
            player.collapsed ||
            player.hasEmbeddedPlayerHost) {
          return child!;
        }
        return MediaQuery.removePadding(
          context: context,
          removeBottom: true,
          child: child!,
        );
      },
    );
  }

  Widget _desktopSplitTabs(
    List<_MainTabItem> tabs,
    int selection,
    int activeTabIndex,
  ) {
    final theme = context.watch<ThemeController>();
    final telegramLanguage = context.watch<TelegramLanguageController>();
    final accounts = context.watch<AccountStore>();
    final size = MediaQuery.sizeOf(context);
    final contentWidth = size.width - desktopNavigationRailWidth;
    final requestedSidebarWidth =
        _splitSidebarWidth ?? defaultSplitSidebarWidth(contentWidth);
    final messageSelection = activeTabIndex == 0 ? _selectedMessageChat : null;
    final selectedChat = desktopChatKindUsesContextPane(messageSelection?.kind)
        ? messageSelection
        : null;
    final infoPaneRequested =
        selectedChat != null && _closedDesktopInfoChatId != selectedChat.chatId;
    final geometry = resolveDesktopShellGeometry(
      totalWidth: size.width,
      requestedSidebarWidth: requestedSidebarWidth,
      infoPaneRequested: infoPaneRequested,
    );
    final canToggleInfoPane =
        geometry.showListPane &&
        selectedChat != null &&
        canShowDesktopInfoPane(
          totalWidth: size.width,
          sidebarWidth: geometry.sidebarWidth,
        );
    final contextPane = geometry.showInfoPane && selectedChat != null
        ? KeyedSubtree(
            key: ValueKey('desktop-chat-context-pane-${selectedChat.chatId}'),
            child: DesktopChatContextPane(
              chatId: selectedChat.chatId,
              title: selectedChat.title,
              onOpenMembers: () =>
                  unawaited(_openDesktopChatMembers(selectedChat)),
              onOpenMember: _openDesktopChatMember,
            ),
          )
        : null;
    final contextPaneExtent = contextPane == null
        ? 0.0
        : desktopInfoPaneHandleWidth + desktopInfoPaneWidth;
    final destinations = [
      for (final tab in tabs)
        DesktopNavigationDestination(
          label: tab.label.l10n(context),
          icon: tab.icon,
        ),
    ];
    final fileLabel = telegramText(AppStringKeys.topicPostContentFile);
    final videoLabel = telegramText(AppStringKeys.sharedMediaVideos);
    final railActions = [
      DesktopNavigationAction(
        id: 'calls',
        label: AppStrings.t(AppStringKeys.callsTitle),
        icon: HeroAppIcons.phone,
        onTap: () => _openDesktopUtility(
          DesktopUtilityWindowKind.calls,
          AppStrings.t(AppStringKeys.callsTitle),
        ),
      ),
      DesktopNavigationAction(
        id: 'videos',
        label: videoLabel,
        icon: HeroAppIcons.video,
        onTap: () =>
            _openDesktopUtility(DesktopUtilityWindowKind.videos, videoLabel),
      ),
    ];
    final applicationMenuQuickActions = [
      DesktopNavigationAction(
        id: 'saved-messages',
        label: AppStrings.t(AppStringKeys.savedMessages),
        icon: HeroAppIcons.thumbtack,
        onTap: () => unawaited(_openDesktopSavedMessages()),
      ),
      DesktopNavigationAction(
        id: 'files',
        label: fileLabel,
        icon: HeroAppIcons.folder,
        onTap: () =>
            _openDesktopUtility(DesktopUtilityWindowKind.files, fileLabel),
      ),
      DesktopNavigationAction(
        id: 'appearance',
        label: AppStrings.t(AppStringKeys.appearanceTitle),
        icon: HeroAppIcons.palette,
        onTap: () => _openDesktopUtility(
          DesktopUtilityWindowKind.settings,
          AppStrings.t(AppStringKeys.profileSettings),
          initialSettingsCategoryId: 'appearance',
        ),
      ),
    ];
    final applicationMenuActions = [
      DesktopNavigationAction(
        id: 'settings',
        label: AppStrings.t(AppStringKeys.profileSettings),
        icon: HeroAppIcons.gear,
        onTap: () => _openDesktopUtility(
          DesktopUtilityWindowKind.settings,
          AppStrings.t(AppStringKeys.profileSettings),
        ),
      ),
    ];
    final selectedLocaleKey = AppLocalizations.localeKeyFor(
      telegramLanguage.mithkaLocale,
    );
    final languageOptions = [
      for (final option in AppLocaleController.options)
        DesktopLanguageMenuOption(
          id: option.tag,
          label: option.label.l10n(context),
          selected:
              AppLocalizations.localeKeyFor(option.locale) == selectedLocaleKey,
          onTap: () => unawaited(() async {
            await telegramLanguage.selectSupportedLocale(option.locale);
            await DesktopChatWindowService.instance.notifyPresentationChanged();
          }()),
        ),
    ];
    return AnimatedBuilder(
      animation: _tabBar,
      builder: (context, _) => Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Row(
                  children: [
                    AnimatedBuilder(
                      animation: _unread,
                      builder: (context, _) => DesktopNavigationRail(
                        destinations: destinations,
                        selection: selection,
                        onSelect: _select,
                        unread: _unread.countFor(theme.unreadBadgeMode),
                        onClearUnread: _chatListController.markAllRead,
                        accounts: accounts.summaries,
                        activeAccountSlot: accounts.activeSlot,
                        onSelectAccount: (slot) => accounts.switchTo(
                          slot,
                          context.read<AuthManager>(),
                        ),
                        onAddAccount: () =>
                            accounts.addAccount(context.read<AuthManager>()),
                        switchAccountLabel: AppStrings.t(
                          AppStringKeys.loginSwitchAccount,
                        ),
                        addAccountLabel: AppStrings.t(
                          AppStringKeys.profileAddAccount,
                        ),
                        themeToggleLabel: AppStrings.t(
                          Theme.of(context).brightness == Brightness.dark
                              ? AppStringKeys.themeModeLight
                              : AppStringKeys.themeModeDark,
                        ),
                        darkMode:
                            Theme.of(context).brightness == Brightness.dark,
                        onToggleThemeMode: () {
                          theme.mode =
                              Theme.of(context).brightness == Brightness.dark
                              ? AppearanceMode.light
                              : AppearanceMode.dark;
                        },
                        showAccountPhone: !theme.hideSidebarPhone,
                        actions: railActions,
                        applicationMenuLabel: AppStrings.t(
                          AppStringKeys.chatMenu,
                        ),
                        languageMenuLabel: AppStrings.t(
                          AppStringKeys.languageTelegramLanguage,
                        ),
                        languageOptions: languageOptions,
                        applicationMenuQuickActions:
                            applicationMenuQuickActions,
                        applicationMenuActions: applicationMenuActions,
                      ),
                    ),
                    if (geometry.showListPane)
                      SizedBox(
                        key: const ValueKey('desktop-list-pane'),
                        width: geometry.sidebarWidth,
                        child: _LazyTabStack(
                          selection: selection,
                          items: tabs,
                          builder: (tab) => _tabletSidebarRoot(
                            tab.index,
                            desktopSidebar: true,
                          ),
                        ),
                      ),
                    SizedBox(
                      key: const ValueKey('desktop-conversation-pane'),
                      width: geometry.conversationWidth + contextPaneExtent,
                      child: _musicAwareContent(
                        geometry.showListPane ||
                                _hasSelectedDesktopDetail(activeTabIndex)
                            ? _animatedTabletDetailPane(
                                activeTabIndex,
                                showMessageBackButton:
                                    desktopDetailNeedsBackButton(geometry),
                                onMessageOpenFullInfo: messageSelection == null
                                    ? null
                                    : () => unawaited(
                                        _openDesktopFullChatInfo(
                                          messageSelection,
                                        ),
                                      ),
                                onMessageOpenUserProfile:
                                    _openDesktopUserProfile,
                                onMessageInfoPressed: canToggleInfoPane
                                    ? () => setState(
                                        () => _closedDesktopInfoChatId =
                                            geometry.showInfoPane
                                            ? selectedChat.chatId
                                            : null,
                                      )
                                    : null,
                                messageTrailingPane: contextPane,
                                messageTrailingPaneWidth: desktopInfoPaneWidth,
                              )
                            : _LazyTabStack(
                                selection: selection,
                                items: tabs,
                                builder: (tab) => _tabletSidebarRoot(
                                  tab.index,
                                  desktopSidebar: true,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
                if (geometry.showListPane)
                  Positioned(
                    left:
                        desktopNavigationRailWidth +
                        geometry.sidebarWidth -
                        splitResizeHandleWidth / 2,
                    top: 0,
                    bottom: 0,
                    child: _splitResizeHandle(
                      totalWidth: contentWidth,
                      sidebarWidth: geometry.sidebarWidth,
                    ),
                  ),
              ],
            ),
          ),
          _fixedMusicPlayer(safeBottom: true),
        ],
      ),
    );
  }

  bool _hasSelectedDesktopDetail(int activeTabIndex) =>
      switch (activeTabIndex) {
        0 => _selectedMessageChat != null || _selectedMessageCommunity != null,
        1 => _selectedChannelDetail != null,
        2 => _selectedContactDetail != null,
        _ => _selectedMomentDetail != null,
      };

  Widget _tabletSplitTabs(
    List<_MainTabItem> tabs,
    int selection,
    int activeTabIndex,
  ) {
    final theme = context.watch<ThemeController>();
    final size = MediaQuery.of(context).size;
    final sidebarWidth = constrainSplitSidebarWidth(
      requestedWidth:
          _splitSidebarWidth ?? defaultSplitSidebarWidth(size.width),
      totalWidth: size.width,
    );
    final messageSelection = activeTabIndex == 0 ? _selectedMessageChat : null;
    final selectedChat = desktopChatKindUsesContextPane(messageSelection?.kind)
        ? messageSelection
        : null;
    final selectedChatId = selectedChat?.chatId;
    final canToggleInfoPane =
        selectedChat != null &&
        size.width >=
            sidebarWidth +
                splitDetailMinWidth +
                desktopInfoPaneHandleWidth +
                desktopInfoPaneWidth;
    final showInfoPane =
        canToggleInfoPane && _closedDesktopInfoChatId != selectedChatId;
    final contextPane = showInfoPane
        ? KeyedSubtree(
            key: ValueKey('tablet-chat-context-pane-${selectedChat.chatId}'),
            child: DesktopChatContextPane(
              chatId: selectedChat.chatId,
              title: selectedChat.title,
              onOpenMembers: () =>
                  unawaited(_openDesktopChatMembers(selectedChat)),
              onOpenMember: _openDesktopChatMember,
            ),
          )
        : null;
    return AnimatedBuilder(
      animation: _tabBar,
      builder: (context, _) => Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: sidebarWidth,
                      child: Column(
                        children: [
                          Expanded(
                            child: _LazyTabStack(
                              selection: selection,
                              items: tabs,
                              builder: (tab) => _tabletSidebarRoot(tab.index),
                            ),
                          ),
                          AnimatedBuilder(
                            animation: _unread,
                            builder: (context, _) => _ClassicTabBar(
                              selection: selection,
                              onSelect: _select,
                              items: tabs,
                              onClearUnread: _chatListController.markAllRead,
                              unread: _unread.countFor(theme.unreadBadgeMode),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _musicAwareContent(
                        _animatedTabletDetailPane(
                          activeTabIndex,
                          onMessageInfoPressed: canToggleInfoPane
                              ? () => setState(
                                  () => _closedDesktopInfoChatId = showInfoPane
                                      ? selectedChatId
                                      : null,
                                )
                              : null,
                          messageTrailingPane: contextPane,
                          messageTrailingPaneWidth: desktopInfoPaneWidth,
                        ),
                      ),
                    ),
                  ],
                ),
                Positioned(
                  left: sidebarWidth - splitResizeHandleWidth / 2,
                  top: 0,
                  bottom: 0,
                  child: _splitResizeHandle(
                    totalWidth: size.width,
                    sidebarWidth: sidebarWidth,
                  ),
                ),
              ],
            ),
          ),
          _fixedMusicPlayer(safeBottom: true),
        ],
      ),
    );
  }

  Widget _splitResizeHandle({
    required double totalWidth,
    required double sidebarWidth,
  }) {
    final dividerColor = _splitResizeHandleHovered
        ? AppTheme.brand.withValues(alpha: 0.78)
        : context.colors.divider;
    return Semantics(
      label: 'Resize sidebar',
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) {
          if (!_splitResizeHandleHovered) {
            setState(() => _splitResizeHandleHovered = true);
          }
        },
        onExit: (_) {
          if (_splitResizeHandleHovered) {
            setState(() => _splitResizeHandleHovered = false);
          }
        },
        child: GestureDetector(
          key: const ValueKey('main-split-resize-handle'),
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) {
            if (_splitSidebarWidth != sidebarWidth) {
              setState(() => _splitSidebarWidth = sidebarWidth);
            }
          },
          onHorizontalDragUpdate: (details) {
            final current = _splitSidebarWidth ?? sidebarWidth;
            final resized = constrainSplitSidebarWidth(
              requestedWidth: current + details.delta.dx,
              totalWidth: totalWidth,
            );
            if (resized != _splitSidebarWidth) {
              setState(() => _splitSidebarWidth = resized);
            }
          },
          onHorizontalDragEnd: (_) {
            unawaited(_persistDesktopSidebarWidth());
          },
          child: SizedBox(
            width: splitResizeHandleWidth,
            child: Center(
              child: AnimatedContainer(
                duration: AppMotion.duration(context, AppMotion.quick),
                curve: AppMotion.standard,
                width: _splitResizeHandleHovered ? 2 : 1,
                color: dividerColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabletSidebarRoot(int tabIndex, {bool desktopSidebar = false}) {
    final communitiesEnabled = context
        .watch<ThemeController>()
        .communitiesEnabled;
    return switch (tabIndex) {
      0 => _tabletMessagesSidebar(
        communitiesEnabled,
        desktopSidebar: desktopSidebar,
      ),
      1 => TopicChannelsView(
        desktopSidebar: desktopSidebar,
        onOpenDetail: (detail) {
          setState(() => _selectedChannelDetail = detail);
        },
      ),
      2 => ContactsView(
        desktopSidebar: desktopSidebar,
        onOpenDetail: (detail) {
          setState(() => _selectedContactDetail = detail);
        },
      ),
      _ => MomentsView(
        desktopSidebar: desktopSidebar,
        onOpenDetail: (detail) {
          setState(() => _selectedMomentDetail = detail);
        },
      ),
    };
  }

  Widget _tabletMessagesSidebar(
    bool communitiesEnabled, {
    bool desktopSidebar = false,
  }) {
    final archivedSelection = _selectedArchivedChats;
    return IndexedStack(
      index: archivedSelection == null ? 0 : 1,
      children: [
        TickerMode(
          enabled: archivedSelection == null,
          child: ChatListView(
            desktopSidebar: desktopSidebar,
            controller: _chatListController,
            selectedChatId: _selectedMessageChat?.chatId,
            selectedCommunityId: communitiesEnabled
                ? _selectedMessageCommunity?.community.id
                : null,
            onChatSelected: (chat) {
              _prepareMessageChatReplacement(chat);
              setState(() {
                _selectedMessageCommunity = null;
                _selectedMessageChat = chat;
              });
            },
            onCommunitySelected: (community) {
              if (!communitiesEnabled) return;
              _messageChatExitController.prepareExit();
              setState(() {
                _selectedMessageChat = null;
                _selectedMessageCommunity = community;
              });
            },
            onOpenArchived: (selection) {
              setState(() => _selectedArchivedChats = selection);
            },
          ),
        ),
        if (archivedSelection == null)
          const SizedBox.shrink()
        else
          AnimatedBuilder(
            animation: archivedSelection.updates,
            builder: (context, _) => ArchivedChatsView(
              chats: archivedSelection.chatsProvider(),
              selectedChatId: _selectedMessageChat?.chatId,
              onClearUnread: archivedSelection.onClearUnread,
              onBack: () => setState(() => _selectedArchivedChats = null),
              onChatSelected: (chat) {
                final nextSelection = ChatListSelection.fromChat(chat);
                _prepareMessageChatReplacement(nextSelection);
                setState(() {
                  _selectedMessageCommunity = null;
                  _selectedMessageChat = nextSelection;
                });
              },
            ),
          ),
      ],
    );
  }

  Widget _tabletDetailPane(
    int activeTabIndex, {
    bool showMessageBackButton = false,
    VoidCallback? onMessageInfoPressed,
    VoidCallback? onMessageOpenFullInfo,
    void Function(int userId, String name)? onMessageOpenUserProfile,
    Widget? messageTrailingPane,
    double messageTrailingPaneWidth = 0,
  }) => switch (activeTabIndex) {
    0 => _messageDetailPane(
      showBackButton: showMessageBackButton,
      onInfoPressed: onMessageInfoPressed,
      onOpenFullInfo: onMessageOpenFullInfo,
      onOpenUserProfile: onMessageOpenUserProfile,
      trailingPane: messageTrailingPane,
      trailingPaneWidth: messageTrailingPaneWidth,
    ),
    1 =>
      _selectedChannelDetail ??
          const _SplitEmptyPane(
            icon: HeroAppIcons.hashtag,
            title: AppStringKeys.tabSelectChannelContent,
          ),
    2 =>
      _selectedContactDetail ??
          const _SplitEmptyPane(
            icon: HeroAppIcons.users,
            title: AppStringKeys.tabSelectContact,
          ),
    _ =>
      _selectedMomentDetail ??
          ChannelMomentsView(
            isRootTab: true,
            title: AppStringKeys.tabFriendMoments,
            onOpenDetail: (detail) {
              setState(() => _selectedMomentDetail = detail);
            },
          ),
  };

  Widget _animatedTabletDetailPane(
    int activeTabIndex, {
    bool showMessageBackButton = false,
    VoidCallback? onMessageInfoPressed,
    VoidCallback? onMessageOpenFullInfo,
    void Function(int userId, String name)? onMessageOpenUserProfile,
    Widget? messageTrailingPane,
    double messageTrailingPaneWidth = 0,
  }) {
    final detail = _tabletDetailPane(
      activeTabIndex,
      showMessageBackButton: showMessageBackButton,
      onMessageInfoPressed: onMessageInfoPressed,
      onMessageOpenFullInfo: onMessageOpenFullInfo,
      onMessageOpenUserProfile: onMessageOpenUserProfile,
      messageTrailingPane: messageTrailingPane,
      messageTrailingPaneWidth: messageTrailingPaneWidth,
    );
    final motionKey = switch (activeTabIndex) {
      0 when _selectedMessageCommunity != null => ValueKey(
        'tablet-message-community-${_selectedMessageCommunity!.community.id}',
      ),
      0 when _selectedMessageChat != null => ValueKey(
        'tablet-message-chat-${_selectedMessageChat!.chatId}-'
        '${_selectedMessageChat!.supportsTopics}-'
        '${_selectedMessageChat!.initialMessageId ?? 0}-'
        '${_selectedMessageChat!.composerFocusRequestId}',
      ),
      0 => const ValueKey('tablet-message-empty'),
      1 when _selectedChannelDetail != null => ObjectKey(
        _selectedChannelDetail!,
      ),
      1 => const ValueKey('tablet-channel-empty'),
      2 when _selectedContactDetail != null => ObjectKey(
        _selectedContactDetail!,
      ),
      2 => const ValueKey('tablet-contact-empty'),
      _ when _selectedMomentDetail != null => ObjectKey(_selectedMomentDetail!),
      _ => const ValueKey('tablet-moments-root'),
    };
    return DetailContentReveal(motionKey: motionKey, child: detail);
  }

  Widget _messageDetailPane({
    bool showBackButton = false,
    VoidCallback? onInfoPressed,
    VoidCallback? onOpenFullInfo,
    void Function(int userId, String name)? onOpenUserProfile,
    Widget? trailingPane,
    double trailingPaneWidth = 0,
  }) {
    final selectedCommunity =
        context.watch<ThemeController>().communitiesEnabled
        ? _selectedMessageCommunity
        : null;
    if (selectedCommunity != null) {
      return KeyedSubtree(
        key: ValueKey('message-community-${selectedCommunity.community.id}'),
        child: CommunityView(
          community: selectedCommunity.community,
          chats: selectedCommunity.chats,
          viewableChats: selectedCommunity.viewableChats,
          updates: selectedCommunity.updates,
          chatsProvider: selectedCommunity.chatsProvider,
          viewableChatsProvider: selectedCommunity.viewableChatsProvider,
          onCollapsedChanged: selectedCommunity.onCollapsedChanged,
          showBackButton: showBackButton,
          onBack: showBackButton
              ? () => setState(() => _selectedMessageCommunity = null)
              : null,
          onChatSelected: (chat) {
            final nextSelection = ChatListSelection.fromChat(chat);
            _prepareMessageChatReplacement(nextSelection);
            setState(() {
              _selectedMessageCommunity = null;
              _selectedMessageChat = nextSelection;
            });
          },
        ),
      );
    }
    final selected = _selectedMessageChat;
    if (selected == null) return const _MessageEmptyPane();
    final chat = selected.chat;
    const headerHeight =
        AppMetric.headerAvatarSize + (AppSpacing.md + AppSpacing.xxs) * 2;
    final headerColor = context.colors.chatBackground;
    return KeyedSubtree(
      key: ValueKey(
        'message-detail-${selected.chatId}-${selected.supportsTopics}-'
        '${selected.initialMessageId ?? 0}-${selected.composerFocusRequestId}',
      ),
      child:
          selected.supportsTopics &&
              chat != null &&
              selected.initialMessageId == null
          ? _ForumSplitDetailPane(
              chat: chat,
              headerHeight: headerHeight,
              headerColor: headerColor,
              exitController: _messageChatExitController,
              showBackButton: showBackButton,
              onBack: () => setState(() => _selectedMessageChat = null),
              onInfoPressed: onInfoPressed,
              onOpenFullInfo: onOpenFullInfo,
              onOpenUserProfile: onOpenUserProfile,
              trailingPane: trailingPane,
              trailingPaneWidth: trailingPaneWidth,
            )
          : ChatView(
              chatId: selected.chatId,
              title: selected.title,
              seedMessage: chat?.lastChatMessage,
              initialMessageId: selected.initialMessageId,
              showBackButton: showBackButton,
              headerHeight: headerHeight,
              headerColor: headerColor,
              showHeaderDivider: false,
              trailingPane: trailingPane,
              trailingPaneWidth: trailingPaneWidth,
              requestComposerFocusOnReady: selected.composerFocusRequestId != 0,
              exitController: _messageChatExitController,
              onChatKindResolved: (kind) =>
                  _handleSelectedChatKindResolved(selected.chatId, kind),
              onInfoPressed: onInfoPressed,
              onOpenFullInfo: onOpenFullInfo,
              onOpenUserProfile: onOpenUserProfile,
              onBack: () => setState(() => _selectedMessageChat = null),
            ),
    );
  }

  Future<void> _openDesktopFullChatInfo(ChatListSelection selected) async {
    _openDesktopUtility(
      DesktopUtilityWindowKind.chatInfo,
      selected.title,
      chatId: selected.chatId,
    );
  }

  Future<void> _openDesktopChatMembers(ChatListSelection selected) async {
    await Navigator.of(context, rootNavigator: true).push<void>(
      AppPageRoute<void>(
        pageBuilder: (_, _, _) =>
            ChatMembersView(chatId: selected.chatId, title: selected.title),
      ),
    );
  }

  void _openDesktopChatMember(ChatMember member) {
    _openDesktopUserProfile(member.id, member.name);
  }

  void _openDesktopUserProfile(int userId, String name) {
    _openDesktopUtility(
      DesktopUtilityWindowKind.userProfile,
      name,
      userId: userId,
    );
  }

  void _prepareMessageChatReplacement(ChatListSelection? nextSelection) {
    final current = _selectedMessageChat;
    if (current == null ||
        (nextSelection != null &&
            current.chatId == nextSelection.chatId &&
            current.supportsTopics == nextSelection.supportsTopics &&
            current.initialMessageId == nextSelection.initialMessageId &&
            current.composerFocusRequestId ==
                nextSelection.composerFocusRequestId)) {
      return;
    }
    _messageChatExitController.prepareExit();
  }

  void _handleSelectedChatKindResolved(int chatId, ChatKind kind) {
    final current = _selectedMessageChat;
    if (current == null || current.chatId != chatId || current.kind == kind) {
      return;
    }
    setState(() => _selectedMessageChat = current.withResolvedKind(kind));
  }

  bool _usesTabletSplit(BuildContext context) {
    return usesAdaptiveSplitLayout(MediaQuery.of(context).size);
  }

  bool _usesDesktopShell(BuildContext context) {
    return usesDesktopShellLayout(MediaQuery.sizeOf(context));
  }

  bool _usesSplitSelection(BuildContext context) {
    return usesSplitSelectionLayout(MediaQuery.sizeOf(context));
  }

  // MARK: - Drawer overlay (the "我" profile drawer)

  Widget _drawerOverlay() =>
      _ProfileDrawerOverlay(controller: context.read<dc.DrawerController>());
}

class _ProfileDrawerOverlay extends StatefulWidget {
  const _ProfileDrawerOverlay({required this.controller});

  final dc.DrawerController controller;

  @override
  State<_ProfileDrawerOverlay> createState() => _ProfileDrawerOverlayState();
}

class _ProfileDrawerOverlayState extends State<_ProfileDrawerOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  void _rebuild() => setState(() {});

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.deliberate,
      reverseDuration: AppMotion.responsive,
      value: widget.controller.isOpen ? 1 : 0,
    )..addListener(_rebuild);
    widget.controller.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = AppMotion.duration(context, AppMotion.deliberate);
    _controller.reverseDuration = AppMotion.duration(
      context,
      AppMotion.responsive,
    );
    _sync();
  }

  @override
  void didUpdateWidget(covariant _ProfileDrawerOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    oldWidget.controller.removeListener(_sync);
    widget.controller.addListener(_sync);
    _sync();
  }

  void _sync() {
    if (AppMotion.isReduced(context)) {
      _controller.value = widget.controller.isOpen ? 1 : 0;
    } else if (widget.controller.isOpen) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    _controller
      ..removeListener(_rebuild)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = math.min(MediaQuery.sizeOf(context).width * 0.88, 420.0);
    final progress = AppMotion.emphasized.transform(_controller.value);
    return IgnorePointer(
      ignoring: _controller.isDismissed,
      child: ExcludeSemantics(
        excluding: _controller.isDismissed,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.controller.close,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.35 * progress),
                ),
              ),
            ),
            Positioned(
              left: -width * (1 - progress),
              top: 0,
              bottom: 0,
              width: width,
              child: Material(
                color: context.colors.groupedBackground,
                child: const ProfileView(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ForumSplitDetailPane extends StatefulWidget {
  const _ForumSplitDetailPane({
    required this.chat,
    required this.headerHeight,
    required this.headerColor,
    required this.exitController,
    required this.showBackButton,
    required this.onBack,
    this.onInfoPressed,
    this.onOpenFullInfo,
    this.onOpenUserProfile,
    this.trailingPane,
    this.trailingPaneWidth = 0,
  });

  final ChatSummary chat;
  final double headerHeight;
  final Color headerColor;
  final ChatViewExitController exitController;
  final bool showBackButton;
  final VoidCallback onBack;
  final VoidCallback? onInfoPressed;
  final VoidCallback? onOpenFullInfo;
  final void Function(int userId, String name)? onOpenUserProfile;
  final Widget? trailingPane;
  final double trailingPaneWidth;

  @override
  State<_ForumSplitDetailPane> createState() => _ForumSplitDetailPaneState();
}

class _ForumSplitDetailPaneState extends State<_ForumSplitDetailPane> {
  var _index = 0;
  int? _topicThreadId;

  Future<void> _showChatMode() async {
    await TopicGroupDisplayPreference.set(TopicGroupDisplayMode.chat);
    if (!mounted) return;
    setState(() => _index = 0);
  }

  Future<void> _showChannelMode([int? threadId]) async {
    await TopicGroupDisplayPreference.set(TopicGroupDisplayMode.channel);
    if (!mounted) return;
    widget.exitController.prepareExit();
    setState(() {
      _index = 1;
      _topicThreadId = threadId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final content = _index == 0
        ? ChatView(
            key: const ValueKey('forum-detail-chat'),
            chatId: widget.chat.id,
            title: widget.chat.title,
            seedMessage: widget.chat.lastChatMessage,
            showBackButton: widget.showBackButton,
            headerHeight: widget.headerHeight,
            headerColor: widget.headerColor,
            headerBottom: _tabSwitcher(c),
            trailingPane: widget.trailingPane,
            trailingPaneWidth: widget.trailingPaneWidth,
            exitController: widget.exitController,
            onInfoPressed: widget.onInfoPressed,
            onOpenFullInfo: widget.onOpenFullInfo,
            onOpenUserProfile: widget.onOpenUserProfile,
            onBack: widget.onBack,
            onOpenTopicMode: (threadId) =>
                unawaited(_showChannelMode(threadId)),
          )
        : TopicChatView(
            key: ValueKey('${widget.chat.id}:${_topicThreadId ?? 0}'),
            chat: widget.chat,
            initialThreadId: _topicThreadId,
            showBackButton: widget.showBackButton,
            headerHeight: widget.headerHeight,
            headerColor: widget.headerColor,
            onOpenChatView: () => unawaited(_showChatMode()),
            onBack: widget.onBack,
          );
    return DetailContentReveal(
      motionKey: ValueKey('forum-detail-$_index-${_topicThreadId ?? 0}'),
      child: content,
    );
  }

  Widget _tabSwitcher(AppColors c) {
    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          height: 32,
          decoration: BoxDecoration(
            color: c.searchFill,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ForumDetailTabButton(
                selected: _index == 0,
                icon: HeroAppIcons.solidMessage,
                label: AppStringKeys.tabMessages,
                onTap: () => unawaited(_showChatMode()),
              ),
              _ForumDetailTabButton(
                selected: _index == 1,
                icon: HeroAppIcons.hashtag,
                label: AppStringKeys.topicChatAllTopics,
                onTap: () => unawaited(_showChannelMode()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ForumDetailTabButton extends StatelessWidget {
  const _ForumDetailTabButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final AppIconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.duration(context, AppMotion.responsive),
        curve: AppMotion.standard,
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? AppTheme.brand : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            AppIcon(
              icon,
              size: 17,
              color: selected ? Colors.white : c.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              label.l10n(context),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : c.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageEmptyPane extends StatelessWidget {
  const _MessageEmptyPane();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ColoredBox(
      color: c.groupedBackground,
      child: Center(
        child: Opacity(
          opacity: 0.08,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/penguin.png', width: 92, height: 92),
              const SizedBox(width: 18),
              Text(
                'Mithka',
                style: TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.w600,
                  color: c.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SplitEmptyPane extends StatelessWidget {
  const _SplitEmptyPane({required this.icon, required this.title});

  final AppIconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ColoredBox(
      color: c.groupedBackground,
      child: Center(
        child: Opacity(
          opacity: 0.18,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(icon, size: 56, color: c.textTertiary),
              const SizedBox(height: 14),
              Text(
                title.l10n(context),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: c.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MainTabItem {
  const _MainTabItem(this.index, this.label, this.icon);

  final int index;
  final String label;
  final AppIconData icon;
}

class _LazyTabStack extends StatefulWidget {
  const _LazyTabStack({
    required this.selection,
    required this.items,
    required this.builder,
  });

  final int selection;
  final List<_MainTabItem> items;
  final Widget Function(_MainTabItem tab) builder;

  @override
  State<_LazyTabStack> createState() => _LazyTabStackState();
}

class _LazyTabStackState extends State<_LazyTabStack>
    with SingleTickerProviderStateMixin {
  final Set<int> _builtTabIndexes = {};
  late final AnimationController _transition;
  int? _departingTabIndex;
  double _direction = 1;
  int _transitionGeneration = 0;

  @override
  void initState() {
    super.initState();
    _transition = AnimationController(
      vsync: this,
      duration: AppMotion.deliberate,
      value: 1,
    );
    _rememberSelection();
  }

  @override
  void didUpdateWidget(covariant _LazyTabStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldPosition = _selectedPosition(oldWidget);
    final oldTabIndex = oldWidget.items.isEmpty
        ? null
        : oldWidget.items[oldPosition].index;
    _builtTabIndexes.removeWhere(
      (index) => !widget.items.any((tab) => tab.index == index),
    );
    _rememberSelection();
    if (widget.items.isEmpty) return;
    final nextPosition = _selectedPosition(widget);
    final nextTabIndex = widget.items[nextPosition].index;
    if (oldTabIndex == null || oldTabIndex == nextTabIndex) return;

    _direction = nextPosition >= oldPosition ? 1 : -1;
    _departingTabIndex = widget.items.any((tab) => tab.index == oldTabIndex)
        ? oldTabIndex
        : null;
    _transition.duration = AppMotion.duration(context, AppMotion.deliberate);
    final generation = ++_transitionGeneration;
    if (_transition.duration == Duration.zero) {
      _transition.value = 1;
      _departingTabIndex = null;
      return;
    }
    _transition.forward(from: 0).whenComplete(() {
      if (!mounted || generation != _transitionGeneration) return;
      setState(() => _departingTabIndex = null);
    });
  }

  int _selectedPosition(_LazyTabStack source) => source.items.isEmpty
      ? 0
      : source.selection.clamp(0, source.items.length - 1).toInt();

  void _rememberSelection() {
    if (widget.items.isEmpty) return;
    final selectedIndex = _selectedPosition(widget);
    final selected = widget.items[selectedIndex];
    _builtTabIndexes.add(selected.index);
  }

  @override
  void dispose() {
    _transition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.expand();
    final selectedPosition = _selectedPosition(widget);
    final selectedTabIndex = widget.items[selectedPosition].index;
    final desktopInPlace = AppMotion.usesInPlaceDesktopNavigation(context);
    return ColoredBox(
      color: context.colors.background,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _transition,
          builder: (context, _) {
            final progress = AppMotion.standard.transform(_transition.value);
            return Stack(
              fit: StackFit.expand,
              children: [
                for (final tab in widget.items)
                  _animatedTab(
                    tab: tab,
                    selectedTabIndex: selectedTabIndex,
                    progress: progress,
                    desktopInPlace: desktopInPlace,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _animatedTab({
    required _MainTabItem tab,
    required int selectedTabIndex,
    required double progress,
    required bool desktopInPlace,
  }) {
    final selected = tab.index == selectedTabIndex;
    final departing = tab.index == _departingTabIndex;
    final visible = selected || departing;
    final opacity = selected ? 0.86 + 0.14 * progress : 1 - progress;
    final offset = desktopInPlace
        ? 0.0
        : selected
        ? _direction * 20 * (1 - progress)
        : -_direction * 10 * progress;
    final scale = desktopInPlace
        ? 1.0
        : selected
        ? 0.995 + 0.005 * progress
        : 1 - 0.005 * progress;

    return Offstage(
      offstage: !visible,
      child: ExcludeSemantics(
        excluding: !selected,
        child: IgnorePointer(
          ignoring: !selected,
          child: TickerMode(
            enabled: selected,
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Transform.translate(
                key: ValueKey('main-tab-translation-${tab.index}'),
                offset: Offset(offset, 0),
                child: Transform.scale(
                  key: ValueKey('main-tab-scale-${tab.index}'),
                  scale: scale,
                  child: KeyedSubtree(
                    key: ValueKey('main-tab-${tab.index}'),
                    child: _builtTabIndexes.contains(tab.index)
                        ? widget.builder(tab)
                        : const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hosts one tab's navigation stack so pushes stay within the tab.
class _TabNavigator extends StatelessWidget {
  const _TabNavigator({
    required this.navigatorKey,
    required this.observer,
    required this.root,
  });
  final GlobalKey<NavigatorState> navigatorKey;
  final NavigatorObserver observer;
  final Widget root;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      observers: [observer],
      onGenerateRoute: (settings) =>
          MaterialPageRoute(builder: (_) => root, settings: settings),
    );
  }
}

/// Flat bottom tab bar.
class _ClassicTabBar extends StatelessWidget {
  const _ClassicTabBar({
    required this.selection,
    required this.onSelect,
    required this.onClearUnread,
    required this.items,
    required this.unread,
  });
  final int selection;
  final ValueChanged<int> onSelect;
  final VoidCallback onClearUnread;
  final List<_MainTabItem> items;
  final int unread;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(top: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelect(i),
                    child: Center(
                      child: SizedBox(
                        width: 64,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 36,
                              height: 28,
                              child: Stack(
                                clipBehavior: Clip.none,
                                alignment: Alignment.center,
                                children: [
                                  TweenAnimationBuilder<double>(
                                    duration: AppMotion.duration(
                                      context,
                                      AppMotion.responsive,
                                    ),
                                    curve: AppMotion.standard,
                                    tween: Tween<double>(
                                      end: selection == i ? 1 : 0,
                                    ),
                                    builder: (context, value, child) =>
                                        Transform.translate(
                                          offset: Offset(0, -value),
                                          child: Transform.scale(
                                            scale: 1 + value * 0.08,
                                            child: AppIcon(
                                              items[i].icon,
                                              size: 24,
                                              color: Color.lerp(
                                                c.textTertiary,
                                                AppTheme.brand,
                                                value,
                                              ),
                                            ),
                                          ),
                                        ),
                                  ),
                                  if (i == 0 && unread > 0)
                                    Positioned(
                                      right: -14,
                                      top: -2,
                                      child: UnreadBadge(
                                        count: unread,
                                        onClear: onClearUnread,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            AnimatedDefaultTextStyle(
                              duration: AppMotion.duration(
                                context,
                                AppMotion.responsive,
                              ),
                              curve: AppMotion.standard,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: selection == i
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: selection == i
                                    ? AppTheme.brand
                                    : c.textTertiary,
                              ),
                              child: Text(
                                items[i].label.l10n(context),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
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
