import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/chat_deep_link_controller.dart';
import 'package:mithka/app/main_tab_view.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/chat/chat_unread_progress.dart';
import 'package:mithka/chat/chat_view.dart';
import 'package:mithka/components/drawer_controller.dart' as dc;
import 'package:mithka/l10n/app_locale_controller.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/moments/moments_view.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

var _singleUnread = false;
var _singleUnreadLineCount = 0;
var _thinHistory = false;
var _tallGroupUnread = false;
var _shortGroup = false;
double? _savedReadingTop;

void main() {
  late StreamController<Map<String, dynamic>> updates;
  final requests = <Map<String, dynamic>>[];
  setUpAll(() {
    updates = StreamController<Map<String, dynamic>>.broadcast();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          requests.add(request);
          return _response(request);
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });
  setUp(() {
    _singleUnread = false;
    _singleUnreadLineCount = 0;
    _thinHistory = false;
    _tallGroupUnread = false;
    _shortGroup = false;
  });
  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });
  testWidgets(
    'one short unread arrives at the bottom without a first-drag jump',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        _singleUnread = true;
        clearChatMemoryCaches();
        await _setSurfaceSize(tester, const Size(390, 844));
        await _pumpMainShell(tester, reducedMotion: true);
        ChatDeepLinkController.shared.openChat(chatId: -42, title: 'Channel');
        await _settle(tester);
        final target = find.byKey(const ValueKey('messageTextBubble-1000'));
        expect(target, findsOneWidget);
        final before = tester.getRect(target);
        final viewport = tester.getRect(find.byType(CustomScrollView).last);
        expect(viewport.bottom - before.bottom, lessThan(60));
        final drag = await tester.startGesture(viewport.center);
        await drag.moveBy(const Offset(0, 25));
        await tester.pump();
        expect(
          (tester.getRect(target).bottom - before.bottom).abs(),
          lessThan(80),
        );
        await drag.up();
        await _settle(tester);
        expect(tester.takeException(), isNull);
        await _disposeShell(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  for (final thinHistory in [false, true]) {
    testWidgets(
      'one medium unread fills the viewport before the first drag, thin=$thinHistory',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          _singleUnread = true;
          _singleUnreadLineCount = 12;
          _thinHistory = thinHistory;
          clearChatMemoryCaches();
          await _setSurfaceSize(tester, const Size(390, 844));
          await _pumpMainShell(tester, reducedMotion: true);
          ChatDeepLinkController.shared.openChat(chatId: -42, title: 'Channel');
          await _settle(tester);
          final target = find.byKey(const ValueKey('messageTextBubble-1000'));
          final viewport = tester.getRect(find.byType(CustomScrollView).last);
          final before = tester.getRect(target);
          expect(viewport.bottom - before.bottom, lessThan(40));
          final drag = await tester.startGesture(viewport.center);
          await drag.moveBy(const Offset(0, 25));
          await tester.pump(const Duration(milliseconds: 16));
          expect((tester.getRect(target).top - before.top).abs(), lessThan(45));
          await drag.up();
          await _settle(tester);
          expect((tester.getRect(target).top - before.top).abs(), lessThan(45));
          expect(tester.takeException(), isNull);
          await _disposeShell(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }

  for (final openAtLatest in [false, true]) {
    testWidgets(
      'a very tall first unread keeps its divider visible, latest=$openAtLatest',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          _singleUnread = !openAtLatest;
          _singleUnreadLineCount = 90;
          _thinHistory = !openAtLatest;
          clearChatMemoryCaches();
          await _setSurfaceSize(tester, const Size(390, 844));
          await _pumpMainShell(
            tester,
            reducedMotion: true,
            openAtLatest: openAtLatest,
          );
          ChatDeepLinkController.shared.openChat(chatId: -42, title: 'Channel');
          await _settle(tester);
          if (openAtLatest) {
            await tester.tap(
              find.byKey(ChatNewMessagesControlShell.unreadBadgeKey),
            );
            await _settle(tester);
          }
          final viewport = tester.getRect(find.byType(CustomScrollView).last);
          final divider = find.text(
            AppStringKeys.chatNewMessagesDivider.l10n(
              tester.element(find.byType(ChatView)),
            ),
          );
          expect(divider, findsOneWidget);
          final before = tester.getRect(divider);
          expect(before.top, greaterThanOrEqualTo(viewport.top));
          expect(before.bottom, lessThan(viewport.center.dy));
          final drag = await tester.startGesture(viewport.center);
          await drag.moveBy(const Offset(0, -25));
          await tester.pump(const Duration(milliseconds: 16));
          expect(
            (tester.getRect(divider).top - before.top).abs(),
            lessThan(45),
          );
          await drag.up();
          await _settle(tester);
          expect(tester.takeException(), isNull);
          await _disposeShell(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }

  testWidgets(
    'group with two tall unread messages keeps the first unread visible',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        _tallGroupUnread = true;
        clearChatMemoryCaches();
        await _setSurfaceSize(tester, const Size(390, 844));
        await _pumpMainShell(tester, reducedMotion: true);
        ChatDeepLinkController.shared.openChat(chatId: -42, title: 'Group');
        await _settle(tester);
        final first = find.byKey(const ValueKey('messageTextBubble-999'));
        expect(first, findsOneWidget);
        final viewport = tester.getRect(find.byType(CustomScrollView).last);
        expect(
          tester.getRect(first).top,
          greaterThanOrEqualTo(viewport.top - 24),
        );
        expect(tester.getRect(first).top, lessThan(viewport.center.dy));
        await _disposeShell(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('reopening a group preserves the previous reading position', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      _tallGroupUnread = true;
      clearChatMemoryCaches();
      await _setSurfaceSize(tester, const Size(390, 844));
      await _pumpMainShell(tester, reducedMotion: true);
      for (var visit = 0; visit < 3; visit++) {
        ChatDeepLinkController.shared.openChat(chatId: -42, title: 'Group');
        await _settle(tester);
        final first = find.byKey(const ValueKey('messageTextBubble-999'));
        expect(first, findsOneWidget);
        final viewport = tester.getRect(find.byType(CustomScrollView).last);
        final top = tester.getRect(first).top;
        if (visit == 0) {
          final drag = await tester.startGesture(viewport.center);
          await drag.moveBy(const Offset(0, -160));
          await tester.pump(const Duration(milliseconds: 100));
          await drag.up();
          await _settle(tester);
          _savedReadingTop = tester.getRect(first).top;
        } else {
          expect(top, closeTo(_savedReadingTop!, 1));
        }
        Navigator.of(
          tester.element(find.byType(ChatView)),
          rootNavigator: true,
        ).pop();
        await _settle(tester);
      }
      expect(tester.takeException(), isNull);
      await _disposeShell(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Moments original target survives a later metadata update', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      _tallGroupUnread = true;
      _shortGroup = true;
      clearChatMemoryCaches();
      await _setSurfaceSize(tester, const Size(390, 844));
      await _pumpMainShell(tester, reducedMotion: true);
      openChannelPostOriginal(
        tester.element(find.byType(MainSplitRootView)),
        ChannelPost(
          channel: ChatSummary(
            id: -42,
            title: 'Group',
            lastMessage: '',
            lastMessageId: 1000,
            date: 1,
            unreadCount: 2,
            order: 1,
            isMuted: false,
            kind: ChatKind.group,
          ),
          message: TDParse.message(_message(999))!,
          accountSlot: 0,
        ),
      );
      await _settle(tester);
      final target = find.byKey(const ValueKey('messageTextBubble-999'));
      expect(target, findsOneWidget);
      final before = tester.getRect(target);
      updates.add({
        '@type': 'updateMessageContent',
        'chat_id': -42,
        'message_id': 970,
        'new_content': {
          '@type': 'messageText',
          'text': {'@type': 'formattedText', 'text': 'Updated earlier message'},
        },
      });
      await _settle(tester);
      expect(target, findsOneWidget);
      expect(tester.getRect(target).top, closeTo(before.top, 1));
      expect(tester.takeException(), isNull);
      await _disposeShell(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'a short destination fills the bottom after the keyboard closes',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        _tallGroupUnread = true;
        _shortGroup = true;
        clearChatMemoryCaches();
        await _setSurfaceSize(tester, const Size(390, 844));
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await _pumpMainShell(tester, reducedMotion: true);
        ChatDeepLinkController.shared.openChat(
          chatId: -42,
          title: 'Group',
          messageId: 999,
        );
        await _settle(tester);
        tester.view.viewInsets = const FakeViewPadding();
        await _settle(tester);
        final viewport = tester.getRect(find.byType(CustomScrollView).last);
        final latest = find.byKey(const ValueKey('messageTextBubble-1000'));
        expect(latest, findsOneWidget);
        expect(viewport.bottom - tester.getRect(latest).bottom, lessThan(40));
        expect(tester.takeException(), isNull);
        await _disposeShell(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  for (final openAtLatest in [false, true]) {
    testWidgets(
      'channel unread destination is reached on first entry, latest=$openAtLatest',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          clearChatMemoryCaches();
          requests.clear();
          await _setSurfaceSize(tester, const Size(390, 844));
          await _pumpMainShell(
            tester,
            reducedMotion: true,
            openAtLatest: openAtLatest,
          );
          ChatDeepLinkController.shared.openChat(chatId: -42, title: 'Channel');
          await _settle(tester);
          final state = tester.state(find.byType(ChatView));
          if (openAtLatest) {
            await tester.tap(
              find.byKey(ChatNewMessagesControlShell.unreadBadgeKey),
            );
            await _settle(tester);
          }
          final target = find.byKey(const ValueKey('messageTextBubble-101'));
          expect(target, findsOneWidget);
          final rect = tester.getRect(target);
          expect(rect.bottom, greaterThan(100));
          expect(rect.top, lessThan(600));
          expect(tester.state(find.byType(ChatView)), same(state));
          expect(tester.takeException(), isNull);
          await _disposeShell(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
}

Map<String, dynamic> _message(int id) => {
  '@type': 'message',
  'id': id,
  'chat_id': -42,
  'date': 1700000000 + id,
  'is_outgoing': false,
  'sender_id': {'@type': 'messageSenderChat', 'chat_id': -42},
  'content': {
    '@type': 'messageText',
    'text': {
      '@type': 'formattedText',
      'text': _shortGroup
          ? 'Group $id'
          : _tallGroupUnread
          ? 'Group $id\n${List.filled(id >= 999 ? 45 : 2, 'Group message content.').join('\n')}'
          : _singleUnread && id == 1000
          ? 'Post $id${'\nUnread post content.' * _singleUnreadLineCount}'
          : _singleUnreadLineCount > 0 && id == 101
          ? 'Post $id${'\nUnread post content.' * _singleUnreadLineCount}'
          : 'Post $id\n${List.filled(id % 4 == 0 ? 28 : 4, 'A long channel post with varying height.').join('\n')}',
    },
  },
};
Map<String, dynamic> _response(Map<String, dynamic> request) {
  switch (request['@type']) {
    case 'getChat':
      return {
        '@type': 'chat',
        'id': -42,
        'title': 'Channel',
        'last_read_inbox_message_id': _singleUnread
            ? 999
            : _tallGroupUnread
            ? 998
            : 100,
        'unread_count': _singleUnread
            ? 1
            : _tallGroupUnread
            ? 2
            : 900,
        'last_message': _message(1000),
        'type': {
          '@type': 'chatTypeSupergroup',
          'supergroup_id': 42,
          'is_channel': !_tallGroupUnread,
        },
      };
    case 'getSupergroup':
      return {
        '@type': 'supergroup',
        'id': 42,
        'is_channel': !_tallGroupUnread,
        'status': {'@type': 'chatMemberStatusMember'},
      };
    case 'getConnectionState':
      return {'@type': 'connectionStateReady'};
    case 'getChatHistory':
      final from = request['from_message_id'] as int;
      return {
        '@type': 'messages',
        'messages': [
          if (from == 0)
            for (var id = 1000; id > (_thinHistory ? 998 : 960); id--)
              _message(id),
          if (from == 999 || (_tallGroupUnread && from == 998))
            for (var id = 1000; id > (_thinHistory ? 998 : 960); id--)
              _message(id),
          if (from == 100)
            for (var id = 130; id >= 51; id--) _message(id),
        ],
      };
    case 'getMessage':
      return _message(request['message_id'] as int);
    case 'getMe':
      return {'@type': 'user', 'id': 1, 'first_name': 'Test'};
    default:
      return {'@type': 'ok'};
  }
}

class _MainShellHarness {
  const _MainShellHarness({required this.drawer});

  final dc.DrawerController drawer;
}

Future<_MainShellHarness> _pumpMainShell(
  WidgetTester tester, {
  bool reducedMotion = false,
  bool showChannelsTab = false,
  bool openAtLatest = false,
  List<NavigatorObserver> navigatorObservers = const [],
}) async {
  SharedPreferences.setMockInitialValues({
    'showChannelsTab': showChannelsTab,
    'openChatsAtLatest': openAtLatest,
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
            child: child!,
          );
          return content;
        },
        home: const MainSplitRootView(),
      ),
    ),
  );
  await tester.pump();
  return _MainShellHarness(drawer: drawer);
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

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 3),
  );
}
