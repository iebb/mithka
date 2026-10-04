import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/group_management_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
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
              return {
                '@type': 'supergroup',
                'id': request['supergroup_id'],
                'is_channel': request['supergroup_id'] == 123,
              };
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

    expect(find.text('Manage Channel'), findsOneWidget);
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
}
