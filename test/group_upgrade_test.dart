import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_info_view.dart';
import 'package:mithka/chat/chat_view.dart';
import 'package:mithka/chat/group_management_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final requests = <Map<String, dynamic>>[];
  var basicUpgraded = false;
  final Map<String, dynamic> selfStatus = {'@type': 'chatMemberStatusCreator'};

  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          requests.add(Map.of(request));
          switch (request['@type']) {
            case 'getChat':
              return {
                '@type': 'chat',
                'id': 42,
                'title': 'Group',
                'type': {'@type': 'chatTypeBasicGroup', 'basic_group_id': 10},
              };
            case 'getMe':
              return {'@type': 'user', 'id': 1};
            case 'getChatMember':
              return {'@type': 'chatMember', 'status': selfStatus};
            case 'getBasicGroup':
              return {
                '@type': 'basicGroup',
                'id': 10,
                'member_count': 3,
                'is_active': true,
                'upgraded_to_supergroup_id': basicUpgraded ? 77 : 0,
              };
            case 'upgradeBasicGroupChatToSupergroupChat':
              return {
                '@type': 'chat',
                'id': 99,
                'type': {'@type': 'chatTypeSupergroup', 'supergroup_id': 77},
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
    basicUpgraded = false;
  });

  Future<void> pumpView(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          locale: const Locale('en'),
          theme: ThemeData(extensions: [AppColors.light]),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const GroupManagementView(chatId: 42, title: 'Group'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the creator of a plain basic group sees the upgrade entry', (
    tester,
  ) async {
    await pumpView(tester);
    await tester.scrollUntilVisible(
      find.text('Convert to supergroup'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Convert to supergroup'), findsOneWidget);
  });

  testWidgets('confirming posts the upgrade and pops with the new chat id', (
    tester,
  ) async {
    await pumpView(tester);
    await tester.scrollUntilVisible(
      find.text('Convert to supergroup'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    requests.clear();

    await tester.tap(find.text('Convert to supergroup'));
    await tester.pumpAndSettle();
    expect(find.text('Convert to supergroup?'), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final upgrade = requests
        .where((r) => r['@type'] == 'upgradeBasicGroupChatToSupergroupChat')
        .toList();
    expect(upgrade, hasLength(1));
    expect(upgrade.single['chat_id'], 42);
  });

  testWidgets('an already-upgraded basic group hides the entry', (
    tester,
  ) async {
    basicUpgraded = true;
    await pumpView(tester);
    expect(find.text('Convert to supergroup'), findsNothing);
  });

  testWidgets(
    'an upgrade hands the new supergroup chat to the navigation owner',
    (tester) async {
      // ChatInfoView pushes GroupManagementView and consumes its result:
      // after the upgrade pops the new chat id, the shell must open the
      // new supergroup conversation instead of sitting on the deactivated
      // basic group.
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      addTearDown(theme.dispose);
      final translation = TranslationController(prefs);
      addTearDown(translation.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeController>.value(value: theme),
            ChangeNotifierProvider<TranslationController>.value(
              value: translation,
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            theme: ThemeData(extensions: [AppColors.light]),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ChatInfoView(chatId: 42, title: 'Group'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // ChatInfoView can be longer than the viewport; walk to the
      // management entry.
      final infoScroll = find.byType(Scrollable).first;
      for (var i = 0; i < 30; i++) {
        if (find.text('Manage group').evaluate().isNotEmpty) break;
        await tester.drag(infoScroll, const Offset(0, -300));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Manage group'), findsOneWidget);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Manage group'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manage group'));
      await tester.pumpAndSettle();
      expect(find.byType(GroupManagementView), findsOneWidget);

      final mgmtScroll = find.byType(Scrollable).first;
      for (var i = 0; i < 30; i++) {
        if (find.text('Convert to supergroup').evaluate().isNotEmpty) break;
        await tester.drag(mgmtScroll, const Offset(0, -300));
        await tester.pump(const Duration(milliseconds: 50));
      }
      requests.clear();
      await tester.tap(find.text('Convert to supergroup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));

      // The management view popped with the upgraded chat id and the
      // shell replaced itself with the new supergroup conversation.
      expect(find.byType(GroupManagementView), findsNothing);
      final chatView = find.byType(ChatView);
      expect(chatView, findsOneWidget);
      expect(
        (tester.widget(chatView) as ChatView).chatId,
        99,
        reason: 'the new supergroup chat must be the open conversation',
      );
    },
  );
}
