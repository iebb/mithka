import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/app_navigator.dart';
import 'package:mithka/app/chat_deep_link_controller.dart';
import 'package:mithka/app/main_tab_view.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/chat/chat_view.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/components/drawer_controller.dart' as dc;
import 'package:mithka/l10n/app_locale_controller.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
}

void _discardMissingTdlibErrors(WidgetTester tester) {
  Object? error;
  while ((error = tester.takeException()) != null) {
    expect(error, isA<ArgumentError>());
    expect(error.toString(), contains('libtdjson'));
  }
}

Future<void> _pumpMainShell(
  WidgetTester tester, {
  bool reducedMotion = false,
  List<NavigatorObserver> navigatorObservers = const [],
  void Function(List<GlobalKey<NavigatorState>> keys)? onKeys,
}) async {
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
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorObservers: navigatorObservers,
        theme: ThemeData(
          brightness: Brightness.light,
          extensions: [AppColors.light],
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reducedMotion,
            textScaler: TextScaler.noScaling,
          ),
          child: child!,
        ),
        home: MainSplitRootView(keysHost: onKeys),
      ),
    ),
  );
  await tester.pump();
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
