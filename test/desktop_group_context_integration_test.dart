import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/adaptive_split_layout.dart';
import 'package:mithka/app/chat_deep_link_controller.dart';
import 'package:mithka/app/main_tab_view.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/components/drawer_controller.dart' as dc;
import 'package:mithka/l10n/app_locale_controller.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('only group and channel selections request desktop context', () {
    expect(desktopChatKindUsesContextPane(ChatKind.group), isTrue);
    expect(desktopChatKindUsesContextPane(ChatKind.channel), isTrue);
    expect(desktopChatKindUsesContextPane(ChatKind.privateChat), isFalse);
    expect(desktopChatKindUsesContextPane(ChatKind.bot), isFalse);
    expect(desktopChatKindUsesContextPane(null), isFalse);
  });

  test('a deep-link selection can adopt its resolved group kind', () {
    const unresolved = ChatListSelection(
      chatId: 42,
      title: 'Deep-linked group',
      initialMessageId: 99,
    );

    expect(unresolved.kind, isNull);
    final resolved = unresolved.withResolvedKind(ChatKind.group);
    expect(desktopChatKindUsesContextPane(resolved.kind), isTrue);
    expect(resolved.chatId, unresolved.chatId);
    expect(resolved.initialMessageId, unresolved.initialMessageId);
  });

  testWidgets(
    'desktop reserves the context pane for group chats without crushing conversation',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await _setSurfaceSize(tester, const Size(1100, 720));
        await _pumpMainShell(tester);

        _selectChat(tester, _chat(42, ChatKind.group, 'Project group'));
        await tester.pump();
        _expectOnlyMissingTdlibErrors(tester);

        final conversationPane = find.byKey(
          const ValueKey('desktop-conversation-pane'),
        );
        final expectedGeometry = resolveDesktopShellGeometry(
          totalWidth: 1100,
          requestedSidebarWidth: defaultSplitSidebarWidth(
            1100 - desktopNavigationRailWidth,
          ),
          infoPaneRequested: true,
        );
        expect(
          tester.getSize(conversationPane).width,
          closeTo(
            expectedGeometry.conversationWidth +
                desktopInfoPaneHandleWidth +
                desktopInfoPaneWidth,
            0.01,
          ),
        );
        expect(
          expectedGeometry.conversationWidth,
          greaterThanOrEqualTo(desktopConversationMinWidth),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await _disposeShell(tester);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('wide iPad adds the same lightweight group context pane', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await _setSurfaceSize(tester, const Size(1100, 800));
      await _pumpMainShell(tester);

      _selectChat(tester, _chat(45, ChatKind.group, 'Tablet group'));
      await tester.pump();
      _expectOnlyMissingTdlibErrors(tester);

      final sidebarWidth = defaultSplitSidebarWidth(1100);
      expect(
        1100 - sidebarWidth - desktopInfoPaneHandleWidth - desktopInfoPaneWidth,
        greaterThanOrEqualTo(splitDetailMinWidth),
      );
      expect(
        find.byKey(const ValueKey('desktop-navigation-rail')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await _disposeShell(tester);
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void _expectOnlyMissingTdlibErrors(WidgetTester tester) {
  Object? error;
  while ((error = tester.takeException()) != null) {
    expect(error, isA<ArgumentError>());
    expect(error.toString(), contains('libtdjson.dylib'));
  }
}

ChatSummary _chat(int id, ChatKind kind, String title) => ChatSummary(
  id: id,
  title: title,
  lastMessage: 'Latest message',
  lastMessageId: 1,
  date: 1,
  unreadCount: 0,
  order: 1,
  isMuted: false,
  kind: kind,
);

void _selectChat(WidgetTester tester, ChatSummary chat) {
  final list = tester.widget<ChatListView>(find.byType(ChatListView));
  list.onChatSelected!(ChatListSelection.fromChat(chat));
}

Future<void> _pumpMainShell(WidgetTester tester) async {
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
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          brightness: Brightness.light,
          extensions: [AppColors.light],
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: true, textScaler: TextScaler.noScaling),
          child: child!,
        ),
        home: const MainSplitRootView(),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _disposeShell(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
}

Future<void> _setSurfaceSize(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}
