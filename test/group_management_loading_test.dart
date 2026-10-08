import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/group_administration_view.dart';
import 'package:mithka/chat/group_management_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/edit_field_view.dart';
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

  testWidgets('shows a retry card when getChat fails', (tester) async {
    getChatFails = true;
    await pumpView(tester, isChannel: false);
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      find.byKey(const ValueKey('group-management-load-retry')),
      findsOneWidget,
    );
    expect(find.byType(ListView), findsNothing);

    getChatFails = false;
    await tester.tap(find.byKey(const ValueKey('group-management-load-retry')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(ListView), findsOneWidget);
    expect(find.text('Test Group'), findsOneWidget);
  });

  testWidgets('uses channel wording inside channels', (tester) async {
    await pumpView(tester, isChannel: true);
    await tester.pumpAndSettle();

    expect(find.text('Manage channel'), findsOneWidget);
    expect(find.text('Channel Name'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Subscribers'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Subscribers'), findsOneWidget);
    expect(find.text('Removed Users'), findsOneWidget);
    expect(find.text('Group name'), findsNothing);
  });

  testWidgets('keeps group wording inside groups', (tester) async {
    await pumpView(tester, isChannel: false);
    await tester.pumpAndSettle();

    expect(find.text('Manage group'), findsOneWidget);
    expect(find.text('Group name'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Members'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Members'), findsOneWidget);
    expect(find.text('Channel Name'), findsNothing);
  });

  testWidgets(
    'the username editor stays inert while supergroup metadata is pending',
    (tester) async {
      supergroupStall = Completer<Map<String, dynamic>>();
      await pumpView(tester, isChannel: false);
      // The page renders from the local database and the owner's rights
      // resolve, but getSupergroup never lands.
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Public Username'), findsOneWidget);

      // Tapping the row must not open a blank editor: saving it would
      // submit username:'' and clear the real username.
      await tester.tap(find.text('Public Username'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(EditFieldView), findsNothing);

      // Late landing: the row unlocks and shows the real value.
      supergroupStall!.complete(supergroupResult);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('@existing'), findsOneWidget);
      await tester.tap(find.text('Public Username'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(EditFieldView), findsOneWidget);
      expect(find.text('existing'), findsAtLeastNWidgets(1));
    },
  );

  testWidgets(
    'a failed supergroup fetch offers a retry and unlocks the editor after it',
    (tester) async {
      supergroupFails = true;
      await pumpView(tester, isChannel: false);
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        find.byKey(const ValueKey('group-management-meta-retry')),
        findsOneWidget,
      );
      await tester.tap(find.text('Public Username'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(EditFieldView), findsNothing);

      supergroupFails = false;
      await tester.tap(
        find.byKey(const ValueKey('group-management-meta-retry')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('group-management-meta-retry')),
        findsNothing,
      );
      expect(find.text('@existing'), findsOneWidget);
    },
  );

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
    'a failed full-info fetch shows a retry and enables editors after it lands',
    (tester) async {
      var failFirst = true;
      await pumpAdvanced(
        tester,
        fullInfoQuery: (_) async {
          if (failFirst) {
            failFirst = false;
            throw Exception('flood');
          }
          return _supergroupFullInfo();
        },
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      // The failure card appears with a retry, and the description editor
      // stays inert while the values are unknown.
      expect(
        find.byKey(const ValueKey('group-admin-full-info-retry')),
        findsOneWidget,
      );
      await tester.tap(find.text('Description'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(EditFieldView), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('group-admin-full-info-retry')),
      );
      await tester.pumpAndSettle();

      // Full info landed: the row shows the real value and the retry card
      // is gone.
      expect(
        find.byKey(const ValueKey('group-admin-full-info-retry')),
        findsNothing,
      );
      expect(find.text('Existing description'), findsOneWidget);

      // With full info known, the description editor opens with the real
      // value pre-filled instead of a blank that would overwrite it.
      await tester.tap(find.text('Description'));
      await tester.pumpAndSettle();
      expect(find.byType(EditFieldView), findsOneWidget);
      expect(find.text('Existing description'), findsAtLeastNWidgets(1));
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

Map<String, dynamic> _supergroupFullInfo({
  String description = 'Existing description',
  int slowMode = 30,
}) => <String, dynamic>{
  '@type': 'supergroupFullInfo',
  'description': description,
  'slow_mode_delay': slowMode,
  'photo': null,
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
