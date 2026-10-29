import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/adaptive_split_layout.dart';
import 'package:mithka/app/app_navigator.dart';
import 'package:mithka/app/bottom_bar_layout.dart';
import 'package:mithka/app/chat_deep_link_controller.dart';
import 'package:mithka/app/content_view.dart';
import 'package:mithka/app/detail_content_reveal.dart';
import 'package:mithka/app/horizontal_safe_viewport.dart';
import 'package:mithka/app/liquid_glass_bottom_bar.dart';
import 'package:mithka/app/main_tab_view.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/chat/chat_view.dart';
import 'package:mithka/chats/archived_chats_view.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/chats/search_view.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/components/drawer_controller.dart' as dc;
import 'package:mithka/contacts/contacts_view.dart';
import 'package:mithka/l10n/app_locale_controller.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/profile/profile_view.dart';
import 'package:mithka/settings/desktop_hotkey_controller.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('folder slides never reset to All or toggle the Messages tab', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await _setSurfaceSize(tester, const Size(1100, 720));
      await _pumpMainShell(tester);
      TdClient.shared.emitLocalUpdate({
        '@type': 'updateChatFolders',
        'chat_folders': [
          {
            'id': 1,
            'title': 'Work',
            'icon': {'name': 'Work'},
          },
          {
            'id': 2,
            'title': 'Home',
            'icon': {'name': 'Home'},
          },
        ],
      });
      await tester.pump();
      await tester.pump();
      final controller = tester
          .widget<ChatListView>(find.byType(ChatListView))
          .controller!;
      final toggles = controller.toggleFirstUnreadRequests;
      await tester.tap(find.byKey(const ValueKey('side-folder-1')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChatFolderRail>(find.byType(ChatFolderRail))
            .selectedFolderId,
        1,
      );
      await tester.tap(find.byKey(const ValueKey('side-folder-2')));
      for (var frame = 0; frame < 24; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          tester
              .widget<ChatFolderRail>(find.byType(ChatFolderRail))
              .selectedFolderId,
          isNotNull,
        );
      }
      expect(controller.toggleFirstUnreadRequests, toggles);
      expect(
        tester
            .widget<ChatFolderRail>(find.byType(ChatFolderRail))
            .selectedFolderId,
        2,
      );
      await _disposeShell(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'Duo side tabs use the strip and yield to routes and the drawer',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await _setSurfaceSize(tester, const Size(466, 678));
      tester.view.padding = const FakeViewPadding(right: 84, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(right: 84, bottom: 34);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      final harness = await _pumpMainShell(
        tester,
        reducedMotion: true,
        withSideViewport: true,
      );
      await tester.pump();
      final contactsTab = find.byKey(const ValueKey('side-tab-2'));
      expect(tester.getRect(contactsTab).left, greaterThanOrEqualTo(382));
      expect(find.byKey(const ValueKey('classic-bottom-bar')), findsNothing);
      for (final label in ['Messages', 'Contacts', 'Moments']) {
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('side-tab-bar')),
            matching: find.text(label),
          ),
          findsNothing,
        );
      }
      await tester.tap(contactsTab);
      await tester.pump();
      final contacts = tester.element(find.byType(ContactsView));
      final scroll = find.descendant(
        of: find.byType(ContactsView),
        matching: find.byType(CustomScrollView),
      );
      expect(tester.getRect(scroll).bottom, 678);
      harness.drawer.open();
      await tester.pump();
      expect(contactsTab, findsNothing);
      harness.drawer.close();
      await tester.pump();
      expect(contactsTab, findsOneWidget);
      final navigator = Navigator.of(
        tester.element(find.byType(MainSplitRootView)),
        rootNavigator: true,
      );
      unawaited(
        navigator.push<void>(
          MaterialPageRoute(builder: (_) => const SizedBox.expand()),
        ),
      );
      await tester.pumpAndSettle();
      expect(contactsTab, findsNothing);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(contactsTab, findsOneWidget);
      tester.view.padding = const FakeViewPadding(bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(bottom: 34);
      await tester.pump();
      await tester.pump();
      expect(contactsTab, findsNothing);
      expect(find.byKey(const ValueKey('classic-bottom-bar')), findsOneWidget);
      expect(tester.element(find.byType(ContactsView)), same(contacts));
      expect(tester.takeException(), isNull);
      await _disposeShell(tester);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  for (final size in [const Size(390, 844), const Size(1024, 800)]) {
    testWidgets('glass option switches live without losing tabs at $size', (
      tester,
    ) async {
      await _setSurfaceSize(tester, size);
      final harness = await _pumpMainShell(tester, reducedMotion: true);
      expect(find.byKey(const ValueKey('classic-bottom-bar')), findsOneWidget);
      expect(find.byType(LiquidGlassBottomBar), findsNothing);
      await tester.tap(find.byKey(const ValueKey('bottom-tab-2')));
      await tester.pump();
      final contacts = tester.element(find.byType(ContactsView));

      harness.theme.liquidGlassBottomBar = true;
      await tester.pump();
      expect(find.byType(LiquidGlassBottomBar), findsOneWidget);
      expect(find.byKey(const ValueKey('classic-bottom-bar')), findsNothing);
      // The viewport now reaches the screen bottom; padding is inside the
      // scroll content so its last row can move clear of the overlaid bar.
      await tester.pump();
      final scroll = find.descendant(
        of: find.byType(ContactsView),
        matching: find.byType(CustomScrollView),
      );
      expect(tester.getRect(scroll).bottom, size.height);
      expect(BottomBarInset.of(tester.element(scroll)), greaterThan(60));

      expect(
        identical(tester.element(find.byType(ContactsView)), contacts),
        isTrue,
      );
      expect(
        tester
            .widget<LiquidGlassBottomBar>(find.byType(LiquidGlassBottomBar))
            .selection,
        1,
      );

      // Removing the selected optional tab must update both the page and pill.
      harness.theme.showContactsTab = false;
      await tester.pump();
      await tester.pump();
      final bar = tester.widget<LiquidGlassBottomBar>(
        find.byType(LiquidGlassBottomBar),
      );
      expect(bar.itemCount, 1);
      expect(bar.selection, 0);
      expect(find.byType(ChatListView), findsOneWidget);
      harness.theme.showContactsTab = true;
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('bottom-tab-2')));
      await tester.pump();
      expect(find.byType(ContactsView), findsOneWidget);

      harness.theme.liquidGlassBottomBar = false;
      await tester.pump();
      expect(find.byType(LiquidGlassBottomBar), findsNothing);
      expect(find.byKey(const ValueKey('classic-bottom-bar')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _disposeShell(tester);
    });
  }

  testWidgets('rapid main-tab switching preserves the nested tab state', (
    tester,
  ) async {
    await _setSurfaceSize(tester, const Size(800, 1200));
    await _pumpMainShell(tester);

    // The test shell has two main tabs, Messages and Contacts.
    await tester.tapAt(const Offset(600, 1168));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ContactsView), findsOneWidget);

    await tester.tap(find.text('Group chat'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester.widget<Text>(find.text('Group chat')).style?.fontWeight,
      FontWeight.w600,
    );

    // Interrupt each transition with another selection. The already-built
    // Contacts navigator must stay mounted throughout the rapid changes.
    await tester.tapAt(const Offset(200, 1168));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(const Offset(600, 1168));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(const Offset(200, 1168));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(const Offset(600, 1168));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ContactsView), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Group chat')).style?.fontWeight,
      FontWeight.w600,
    );
    await _disposeShell(tester);
  });

  testWidgets('reduced motion opens and closes the profile drawer instantly', (
    tester,
  ) async {
    await _setSurfaceSize(tester, const Size(390, 844));
    final harness = await _pumpMainShell(tester, reducedMotion: true);

    var drawerPosition = _closestAncestor<Positioned>(
      tester,
      find.byType(ProfileView),
    );
    expect(drawerPosition.left, closeTo(-343.2, 0.001));

    harness.drawer.open();
    await tester.pump();
    drawerPosition = _closestAncestor<Positioned>(
      tester,
      find.byType(ProfileView),
    );
    expect(drawerPosition.left, 0);
    expect(find.byKey(const ValueKey('profile-banner-edit')), findsOneWidget);
    expect(find.byTooltip('Edit profile'), findsNothing);

    harness.drawer.close();
    await tester.pump();
    drawerPosition = _closestAncestor<Positioned>(
      tester,
      find.byType(ProfileView),
    );
    expect(drawerPosition.left, closeTo(-343.2, 0.001));
    await _disposeShell(tester);
  });

  testWidgets('reduced motion reveals a tablet detail without an entrance', (
    tester,
  ) async {
    await _setSurfaceSize(tester, const Size(1024, 800));
    await _pumpMainShell(tester, reducedMotion: true, showChannelsTab: true);
    expect(
      find.byKey(const ValueKey('chat-list-inline-search')),
      findsOneWidget,
    );

    // Move from Messages to Channels. On a tablet this replaces the detail
    // pane as well as the sidebar root.
    await tester.tapAt(const Offset(164, 770));
    await tester.pump();

    final detail = find.byKey(const ValueKey('tablet-channel-empty'));
    expect(detail, findsOneWidget);

    final surface = find.byKey(DetailContentReveal.surfaceKey);
    expect(surface, findsOneWidget);
    expect(tester.getRect(detail), tester.getRect(surface));
    expect(find.byKey(DetailContentReveal.transitionTintKey), findsNothing);
    await _disposeShell(tester);
  });

  testWidgets('tablet archive replaces only the sidebar pane', (tester) async {
    await _setSurfaceSize(tester, const Size(1024, 800));
    await _pumpMainShell(tester, reducedMotion: true);

    final emptyDetail = find.byKey(const ValueKey('tablet-message-empty'));
    final detailElement = tester.element(emptyDetail);
    final updates = ChangeNotifier();
    addTearDown(updates.dispose);
    final archived = [
      ChatSummary(
        id: 77,
        title: 'Archived conversation',
        lastMessage: 'Still in the list pane',
        lastMessageId: 2,
        date: 1,
        unreadCount: 0,
        order: 1,
        isMuted: false,
      ),
    ];

    final chatList = tester.widget<ChatListView>(find.byType(ChatListView));
    chatList.onOpenArchived!(
      ArchivedChatListSelection(
        chatsProvider: () => archived,
        updates: updates,
        onClearUnread: (_) {},
      ),
    );
    await tester.pump();

    expect(find.byType(ArchivedChatsView), findsOneWidget);
    expect(find.text('Archived conversation'), findsOneWidget);
    expect(identical(tester.element(emptyDetail), detailElement), isTrue);

    tester.widget<ArchivedChatsView>(find.byType(ArchivedChatsView)).onBack!();
    await tester.pump();

    expect(find.byType(ArchivedChatsView), findsNothing);
    expect(find.byType(ChatListView), findsOneWidget);
    expect(identical(tester.element(emptyDetail), detailElement), isTrue);
    await _disposeShell(tester);
  });

  testWidgets('macOS uses an icon rail and embedded list-pane chrome', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await _setSurfaceSize(tester, const Size(1100, 720));
      await _pumpMainShell(tester, reducedMotion: true);

      final rail = find.byKey(const ValueKey('desktop-navigation-rail'));
      final listPane = find.byKey(const ValueKey('desktop-list-pane'));
      expect(rail, findsOneWidget);
      expect(tester.getSize(rail).width, desktopNavigationRailWidth);
      expect(tester.getSize(listPane).width, inInclusiveRange(320, 420));
      expect(
        tester.widget<ChatListView>(find.byType(ChatListView)).desktopSidebar,
        isTrue,
      );
      expect(
        find.byKey(const ValueKey('chat-list-desktop-toolbar')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('chat-list-desktop-add')), findsNothing);
      expect(
        find.byKey(const ValueKey('chat-list-inline-search')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('desktop-navigation-item-1')));
      await tester.pump();
      final tabTranslation = tester.widget<Transform>(
        find.byKey(const ValueKey('main-tab-translation-2')),
      );
      expect(tabTranslation.transform.getTranslation().x, 0);
      final contacts = tester.widget<ContactsView>(find.byType(ContactsView));
      expect(contacts.desktopSidebar, isTrue);
      expect(find.byKey(const ValueKey('contacts-root-header')), findsNothing);
      final chatController = tester
          .widget<ChatListView>(find.byType(ChatListView, skipOffstage: false))
          .controller!;
      const folderKey = ValueKey('test-desktop-folder-rail');
      chatController.publishSideFolders(
        Object(),
        const SizedBox(key: folderKey),
      );
      await tester.pump();
      expect(find.byKey(folderKey), findsNothing);
      await tester.tap(find.byKey(const ValueKey('desktop-navigation-item-0')));
      await tester.pump();
      chatController.publishSideFolders(
        Object(),
        const SizedBox(key: folderKey),
      );
      await tester.pump();
      expect(find.byKey(folderKey), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('desktop-navigation-item-1')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('contacts-desktop-toolbar')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await _disposeShell(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('narrow macOS keeps the rail and collapses the list column', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await _setSurfaceSize(tester, const Size(780, 620));
      await _pumpMainShell(tester, reducedMotion: true);

      expect(
        find.byKey(const ValueKey('desktop-navigation-rail')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('desktop-list-pane')), findsNothing);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('desktop-conversation-pane')))
            .width,
        780 - desktopNavigationRailWidth,
      );
      expect(
        tester.widget<ChatListView>(find.byType(ChatListView)).desktopSidebar,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await _disposeShell(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop title-bar chat actions keep their live destinations', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await _setSurfaceSize(tester, const Size(1100, 720));
      await _pumpMainShell(tester, reducedMotion: true, withDesktopFrame: true);

      final searchField = find.byKey(
        const ValueKey('desktop-title-bar-search'),
      );
      final searchInput = find.byKey(
        const ValueKey('desktop-title-bar-search-input'),
      );
      final addAction = find.byKey(const ValueKey('desktop-title-bar-add'));
      expect(searchField, findsOneWidget);
      expect(searchInput, findsOneWidget);
      expect(addAction, findsOneWidget);
      expect(
        DesktopHotkeyRegistry.instance.hasEnabledHandler(
          DesktopHotkeyAction.focusSearch,
        ),
        isTrue,
      );
      expect(
        find.byKey(const ValueKey('chat-list-inline-search')),
        findsNothing,
      );
      await tester.tap(searchInput);
      await tester.pump();
      expect(find.byType(SearchView), findsNothing);
      await tester.enterText(searchInput, 'inline');
      await tester.pump();
      expect(
        find.byKey(const ValueKey('desktop-inline-search-panel')),
        findsOneWidget,
      );

      await tester.tap(addAction);
      await tester.pump();
      final menu = find.byKey(const ValueKey('desktop-title-bar-plus-menu'));
      expect(menu, findsOneWidget);
      expect(
        tester.getTopRight(menu).dx,
        moreOrLessEquals(tester.getBottomRight(addAction).dx, epsilon: 0.01),
      );
      expect(
        tester.getTopRight(menu).dy,
        moreOrLessEquals(
          tester.getBottomRight(addAction).dy + 6,
          epsilon: 0.01,
        ),
      );

      await tester.tapAt(const Offset(200, 200));
      await tester.pump();
      expect(menu, findsNothing);
      await _disposeShell(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('simultaneous shells own independent navigator keys', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await _setSurfaceSize(tester, const Size(740, 844));
      final firstKeys = <GlobalKey<NavigatorState>>[];
      final secondKeys = <GlobalKey<NavigatorState>>[];
      SharedPreferences.setMockInitialValues({
        'showChannelsTab': false,
        'showMomentsTab': false,
        'communitiesEnabled': false,
      });
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      final accounts = AccountStore(prefs);
      final auth = AuthManager();
      final translation = TranslationController(prefs);
      final drawer = dc.DrawerController();
      final deepLinks = ChatDeepLinkController.shared;
      deepLinks.consumePending();
      addTearDown(theme.dispose);
      addTearDown(accounts.dispose);
      addTearDown(auth.dispose);
      addTearDown(translation.dispose);
      addTearDown(drawer.dispose);
      // Two shells alive at once, as in a desktop window plus the split root:
      // each gets its own keys and neither can claim the other's navigator.
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeController>.value(value: theme),
            ChangeNotifierProvider<AppLocaleController>.value(
              value: AppLocaleController(prefs),
            ),
            ChangeNotifierProvider<AccountStore>.value(value: accounts),
            ChangeNotifierProvider<AuthManager>.value(value: auth),
            ChangeNotifierProvider<TranslationController>.value(
              value: translation,
            ),
            ChangeNotifierProvider<ChatDeepLinkController>.value(
              value: deepLinks,
            ),
            ChangeNotifierProvider<dc.DrawerController>.value(value: drawer),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData(extensions: [AppColors.light]),
            home: Row(
              children: [
                Expanded(child: MainTabView(keysHost: firstKeys.addAll)),
                Expanded(child: MainTabView(keysHost: secondKeys.addAll)),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(firstKeys, hasLength(4));
      expect(secondKeys, hasLength(4));
      // The lazy tab stack builds the selected tab's navigator; every key
      // must be distinct across the two shells and the live ones reachable.
      final built = <int>[];
      for (var i = 0; i < firstKeys.length; i++) {
        expect(firstKeys[i], isNot(same(secondKeys[i])));
        if (firstKeys[i].currentState != null) built.add(i);
      }
      expect(built, isNotEmpty);
      for (final i in built) {
        expect(firstKeys[i].currentState, isNotNull);
        expect(secondKeys[i].currentState, isNotNull);
      }
      // No GlobalKey duplication exception was thrown, and both navigators
      // stay independently addressable.
      expect(tester.takeException(), isNull);
      await _disposeShell(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android root back requests application exit', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await _setSurfaceSize(tester, const Size(390, 844));
      await _pumpMainShell(tester, reducedMotion: true);
      final exitCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'SystemNavigator.pop') exitCalls.add(call);
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(exitCalls.map((call) => call.method), ['SystemNavigator.pop']);
      await _disposeShell(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android back pops nested routes before exiting at the root', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await _setSurfaceSize(tester, const Size(390, 844));
      final exitCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'SystemNavigator.pop') exitCalls.add(call);
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      var keys = <GlobalKey<NavigatorState>>[];
      await _pumpMainShell(
        tester,
        reducedMotion: true,
        onKeys: (k) => keys = k,
      );
      await tester.pump();
      unawaited(
        keys[0].currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) =>
                const SizedBox(key: ValueKey('android-back-nested-route')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(keys[0].currentState!.canPop(), isTrue);

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(keys[0].currentState!.canPop(), isFalse);
      expect(find.byType(ChatListView), findsOneWidget);
      expect(exitCalls, isEmpty);

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(exitCalls.map((call) => call.method), ['SystemNavigator.pop']);
      await _disposeShell(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('external phone deep links replace the active chat', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await _setSurfaceSize(tester, const Size(390, 844));
      final navigator = _TrackingNavigatorObserver();
      await _pumpMainShell(
        tester,
        reducedMotion: true,
        navigatorObservers: [navigator],
      );
      final deepLinks = ChatDeepLinkController.shared;

      deepLinks.openChat(chatId: 41, title: 'First chat', messageId: 410);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));
      _discardMissingTdlibErrors(tester);
      expect(navigator.routes, hasLength(2));
      expect(_chatFor(navigator.routes.last).chatId, 41);

      deepLinks.openChat(chatId: 84, title: 'Replacement chat', messageId: 840);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));
      _discardMissingTdlibErrors(tester);
      expect(navigator.routes, hasLength(2));
      expect(_chatFor(navigator.routes.last).chatId, 84);

      navigator.navigator!.pop();
      await tester.pump();
      expect(navigator.routes, hasLength(1));
      expect(find.byType(ChatListView), findsOneWidget);
      await _disposeShell(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('phone message jumps return to the source chat', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await _setSurfaceSize(tester, const Size(390, 844));
      final navigator = _TrackingNavigatorObserver();
      await _pumpMainShell(
        tester,
        reducedMotion: true,
        navigatorObservers: [navigator],
      );
      final deepLinks = ChatDeepLinkController.shared;

      deepLinks.openChat(chatId: 41, title: 'Source chat', messageId: 410);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));
      _discardMissingTdlibErrors(tester);

      deepLinks.openChat(
        chatId: 84,
        title: 'Linked chat',
        messageId: 840,
        preserveChatStack: true,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));
      _discardMissingTdlibErrors(tester);
      expect(navigator.routes, hasLength(3));
      expect(_chatFor(navigator.routes.last).chatId, 84);

      navigator.navigator!.pop();
      await tester.pump();
      expect(navigator.routes, hasLength(2));
      expect(_chatFor(navigator.routes.last).chatId, 41);
      await _disposeShell(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'phone chat back button slides the conversation out across the viewport',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await _setSurfaceSize(tester, const Size(390, 844));
        await _pumpMainShell(tester);
        final deepLinks = ChatDeepLinkController.shared;

        deepLinks.openChat(chatId: 41, title: 'Mobile chat', messageId: 410);
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        _discardMissingTdlibErrors(tester);

        final chatView = find.byType(ChatView);
        expect(chatView, findsOneWidget);
        expect(tester.getTopLeft(chatView).dx, closeTo(0, 0.5));

        final backButton = find.descendant(
          of: chatView,
          matching: find.byIcon(HeroAppIcons.chevronLeft.data),
        );
        expect(backButton, findsOneWidget);
        await tester.tap(backButton);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 90));
        _discardMissingTdlibErrors(tester);

        final midPopLeft = tester.getTopLeft(chatView).dx;
        expect(midPopLeft, greaterThan(180));
        expect(midPopLeft, lessThan(390));

        await tester.pump(const Duration(milliseconds: 240));
        await tester.pump();
        _discardMissingTdlibErrors(tester);
        expect(chatView, findsNothing);
        expect(find.byType(ChatListView), findsOneWidget);
        await _disposeShell(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}

void _discardMissingTdlibErrors(WidgetTester tester) {
  Object? error;
  while ((error = tester.takeException()) != null) {
    expect(error, isA<ArgumentError>());
    expect(error.toString(), contains('libtdjson'));
  }
}

class _MainShellHarness {
  const _MainShellHarness({required this.drawer, required this.theme});

  final ThemeController theme;

  final dc.DrawerController drawer;
}

Future<_MainShellHarness> _pumpMainShell(
  WidgetTester tester, {
  bool reducedMotion = false,
  bool showChannelsTab = false,
  bool withDesktopFrame = false,
  bool withSideViewport = false,
  List<NavigatorObserver> navigatorObservers = const [],
  void Function(List<GlobalKey<NavigatorState>> keys)? onKeys,
}) async {
  SharedPreferences.setMockInitialValues({
    'showChannelsTab': showChannelsTab,
    'showMomentsTab': false,
    'communitiesEnabled': false,
  });
  final prefs = await SharedPreferences.getInstance();
  final theme = ThemeController(prefs);
  final accounts = AccountStore(prefs);
  final auth = AuthManager();
  final translation = TranslationController(prefs);
  final drawer = dc.DrawerController();
  final deepLinks = ChatDeepLinkController.shared;
  deepLinks.consumePending();

  addTearDown(theme.dispose);
  addTearDown(accounts.dispose);
  addTearDown(auth.dispose);
  addTearDown(translation.dispose);
  addTearDown(drawer.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        ChangeNotifierProvider<AppLocaleController>.value(
          value: AppLocaleController(prefs),
        ),
        ChangeNotifierProvider<AccountStore>.value(value: accounts),
        ChangeNotifierProvider<AuthManager>.value(value: auth),
        ChangeNotifierProvider<TranslationController>.value(value: translation),
        ChangeNotifierProvider<ChatDeepLinkController>.value(value: deepLinks),
        ChangeNotifierProvider<dc.DrawerController>.value(value: drawer),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorObservers: navigatorObservers,
        theme: ThemeData(
          brightness: Brightness.light,
          extensions: [AppColors.light],
        ),
        builder: (context, child) {
          final content = MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: reducedMotion,
              textScaler: TextScaler.noScaling,
            ),
            child: withSideViewport
                ? HorizontalSafeViewport(sideNavigation: true, child: child!)
                : child!,
          );
          if (!withDesktopFrame) return content;
          return DesktopPrimaryWindowFrame(
            accountReady: true,
            showAccountPhone: false,
            child: content,
          );
        },
        home: MainSplitRootView(keysHost: onKeys),
      ),
    ),
  );
  await tester.pump();
  return _MainShellHarness(drawer: drawer, theme: theme);
}

ChatView _chatFor(Route<dynamic> route) {
  final chatRoute = route as AppChatPageRoute<dynamic>;
  return chatRoute.builder(chatRoute.navigator!.context) as ChatView;
}

class _TrackingNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> routes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : routes.indexOf(oldRoute);
    if (index >= 0 && newRoute != null) {
      routes[index] = newRoute;
    }
  }
}

Future<void> _disposeShell(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  // Chat-list cache warming uses delayed no-op guards after disposal.
  await tester.pump(const Duration(seconds: 6));
}

Future<void> _setSurfaceSize(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

T _closestAncestor<T extends Widget>(WidgetTester tester, Finder finder) {
  final element = tester.element(finder);
  T? result;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is! T) return true;
    result = widget;
    return false;
  });
  return result!;
}
