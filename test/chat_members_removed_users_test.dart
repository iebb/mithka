import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_members_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final requestedFilters = <String>[];
  final statusUpdates = <Map<String, dynamic>>[];
  var pageCount = 1;
  setUp(() {
    pageCount = 1;
    requestedFilters.clear();
    statusUpdates.clear();
  });

  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          switch (request['@type']) {
            case 'getChat':
              return {
                '@type': 'chat',
                'id': 10,
                'type': {
                  '@type': 'chatTypeSupergroup',
                  'supergroup_id': 20,
                  'is_channel': true,
                },
              };
            case 'getMe':
              return {'@type': 'user', 'id': 1, 'first_name': 'Me'};
            case 'getChatMember':
              return {
                '@type': 'chatMember',
                'status': {
                  '@type': 'chatMemberStatusCreator',
                  'is_member': true,
                },
              };
            case 'getSupergroupMembers':
              requestedFilters.add(request['filter']['@type'] as String);
              return {
                '@type': 'chatMembers',
                'member_count': pageCount,
                'members': [
                  for (var index = 0; index < pageCount; index++)
                    {
                      '@type': 'chatMember',
                      'member_id': {
                        '@type': 'messageSenderUser',
                        'user_id': 42 + index,
                      },
                      'status': {
                        '@type': 'chatMemberStatusBanned',
                        'banned_until_date': 0,
                      },
                    },
                ],
              };
            case 'getUser':
              return {
                '@type': 'user',
                'id': 42,
                'first_name': 'Banned',
                'last_name': 'User',
              };
            case 'setChatMemberStatus':
              statusUpdates.add(Map<String, dynamic>.from(request));
              return {'@type': 'ok'};
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

  Future<void> pumpView(WidgetTester tester) async {
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
          home: const ChatMembersView(
            chatId: 10,
            title: 'Channel',
            mode: ChatMembersMode.banned,
          ),
        ),
      ),
    );
  }

  testWidgets('every page of removed users keeps the banned filter', (
    tester,
  ) async {
    pageCount = 200;
    requestedFilters.clear();
    await pumpView(tester);
    await tester.pumpAndSettle();
    pageCount = 1;
    final list = find.byType(ListView).first;
    final scroll = tester.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)).first,
    );
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump(const Duration(milliseconds: 100));
    expect(requestedFilters.length, greaterThanOrEqualTo(2));
    expect(
      requestedFilters,
      everyElement('supergroupMembersFilterBanned'),
      reason:
          'pagination must never replace removed users with current members',
    );
  });

  testWidgets('banned mode lists removed users and unbans them', (
    tester,
  ) async {
    requestedFilters.clear();
    statusUpdates.clear();
    await pumpView(tester);
    await tester.pumpAndSettle();

    expect(requestedFilters, contains('supergroupMembersFilterBanned'));
    expect(find.text('Removed Users'), findsOneWidget);
    expect(find.text('Banned User'), findsOneWidget);

    await tester.drag(find.text('Banned User'), const Offset(-120, 0));
    await tester.pump();
    await tester.tap(find.text('Unban'));
    await tester.pumpAndSettle();

    final dialog = find.byType(CupertinoAlertDialog);
    expect(dialog, findsOneWidget);
    await tester.tap(
      find.descendant(of: dialog, matching: find.text('Unban')).last,
    );
    await tester.pumpAndSettle();

    expect(statusUpdates, hasLength(1));
    expect(statusUpdates.single['status']['@type'], 'chatMemberStatusLeft');
    expect(find.text('Banned User'), findsNothing);
    expect(find.text('Removed Users'), findsOneWidget);
  });
}
