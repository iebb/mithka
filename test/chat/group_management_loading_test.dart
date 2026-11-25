import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/admin/group_administration_view.dart';
import 'package:mithka/chat/admin/group_management_view.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/contacts/contacts_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/profile_account/edit_field_view.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _chat({required bool isChannel}) => {
  '@type': 'chat',
  'id': isChannel ? -100123 : -100456,
  'title': isChannel ? 'News Channel' : 'Test Group',
  'type': {
    '@type': 'chatTypeSupergroup',
    'supergroup_id': isChannel ? 123 : 456,
    'is_channel': isChannel,
  },
};

Map<String, dynamic> _selfCreator() => {
  '@type': 'chatMember',
  'status': {'@type': 'chatMemberStatusCreator', 'is_member': true},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var getChatFails = false;
  var fullInfoStalls = false;
  var supergroupFails = false;
  Completer<Map<String, dynamic>>? supergroupStall;
  Map<String, dynamic> supergroupResult = _supergroup(username: 'existing');

  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          switch (request['@type']) {
            case 'getChat':
              if (getChatFails) {
                return {'@type': 'error', 'code': 400, 'message': 'chat gone'};
              }
              return _chat(isChannel: request['chat_id'] == -100123);
            case 'getMe':
              return {'@type': 'user', 'id': 1, 'first_name': 'Me'};
            case 'getChatMember':
              return _selfCreator();
            case 'getSupergroup':
              if (supergroupStall != null) {
                // Simulates getSupergroup held behind TDLib's queue: the
                // response only arrives when the test completes it.
                return supergroupStall!.future;
              }
              if (supergroupFails) {
                return {'@type': 'error', 'code': 400, 'message': 'flood'};
              }
              return supergroupResult;
            case 'getSupergroupFullInfo':
              if (fullInfoStalls) {
                // Simulates a query held behind TDLib's flood control: the
                // response never arrives within the view's lifetime.
                return Completer<Map<String, dynamic>>().future;
              }
              return {
                '@type': 'supergroupFullInfo',
                'can_get_statistics': false,
              };
            case 'getForumTopics':
              return {'@type': 'forumTopics', 'topics': const <Object>[]};
            case 'getContacts':
              return {'@type': 'users', 'user_ids': const <int>[]};
            case 'getChats':
              return {'@type': 'chats', 'chat_ids': const <int>[]};
            default:
              return {'@type': 'ok'};
          }
        },
        send: (_) async {},
        updates: const Stream<Map<String, dynamic>>.empty(),
      ),
    );
  });

  tearDownAll(TdClient.shared.closeProxy);

  setUp(() {
    getChatFails = false;
    fullInfoStalls = false;
    supergroupStall = null;
    supergroupFails = false;
    supergroupResult = _supergroup(username: 'existing');
  });

  Future<void> pumpView(WidgetTester tester, {required bool isChannel}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          theme: ThemeData(extensions: [AppColors.light]),
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: GroupManagementView(
            chatId: isChannel ? -100123 : -100456,
            title: isChannel ? 'News Channel' : 'Test Group',
            isChannel: isChannel,
          ),
        ),
      ),
    );
  }

  testWidgets('renders without waiting for a stalled full-info query', (
    tester,
  ) async {
    fullInfoStalls = true;
    await pumpView(tester, isChannel: true);
    // The page must be interactive well before the 15s full-info timeout.
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(ListView), findsOneWidget);
    expect(find.text('News Channel'), findsOneWidget);

    // Flush the background full-info timeout timer.
    await tester.pump(const Duration(seconds: 16));
    expect(find.byType(ListView), findsOneWidget);
  });

  testWidgets(
    'full-info-backed editors stay disabled until full info arrives',
    (tester) async {
      await pumpAdvanced(
        tester,
        fullInfoQuery: (_) =>
            Completer<Map<String, dynamic>>().future, // Stalls forever.
      );
      await tester.pump(const Duration(milliseconds: 250));

      // The page rendered from the local database...
      expect(find.text('Description'), findsOneWidget);
      expect(find.text('Slow mode'), findsOneWidget);
      // ...but the full-info-backed editors are inert: tapping them must
      // not open anything over an unloaded default.
      await tester.tap(find.text('Description'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(EditFieldView), findsNothing);

      // Flush the 15s full-info timeout timer the stalled query armed.
      await tester.pump(const Duration(seconds: 16));
      expect(find.byType(ListView), findsOneWidget);
    },
  );

  testWidgets(
    'forum topic creation dialog renders its TextField inside a Material surface',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      addTearDown(theme.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            theme: ThemeData(extensions: [AppColors.light]),
            locale: const Locale('en'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ForumTopicsAdministrationView(chatId: -100456),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is AppIcon && w.icon == HeroAppIcons.plus,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Announcements');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
    },
  );

  testWidgets(
    'pushing ContactsView onto Navigator provides Material and a back button',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      addTearDown(theme.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            theme: ThemeData(extensions: [AppColors.light]),
            locale: const Locale('en'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => GestureDetector(
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(builder: (_) => const ContactsView()),
                ),
                child: const Text('open-contacts'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open-contacts'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('contacts-back-button')),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'alice');
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('contacts-back-button')));
      await tester.pumpAndSettle();
      expect(find.text('open-contacts'), findsOneWidget);
    },
  );
}

Map<String, dynamic> _supergroup({String username = ''}) => {
  '@type': 'supergroup',
  'id': 456,
  'is_channel': false,
  'usernames': {
    '@type': 'usernames',
    'editable_username': username.isEmpty ? null : username,
  },
};

Future<void> pumpAdvanced(
  WidgetTester tester, {
  Future<Map<String, dynamic>> Function(int)? fullInfoQuery,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final theme = ThemeController(prefs);
  addTearDown(theme.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: GroupAdvancedAdministrationView(
          chatId: -100456,
          supergroupId: 456,
          fullInfoQuery: fullInfoQuery,
        ),
      ),
    ),
  );
}
