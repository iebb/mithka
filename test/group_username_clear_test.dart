import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/group_management_view.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/edit_field_view.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> currentChat = {};
  final requests = <Map<String, dynamic>>[];

  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          requests.add(Map.of(request));
          switch (request['@type']) {
            case 'getChat':
              return currentChat;
            case 'getMe':
              return {'@type': 'user', 'id': 1};
            case 'getChatMember':
              return {
                '@type': 'chatMember',
                'status': {'@type': 'chatMemberStatusCreator'},
              };
            case 'getSupergroup':
              return {
                '@type': 'supergroup',
                'id': 10,
                'usernames': {
                  '@type': 'usernames',
                  'active_usernames': ['currentname'],
                  'disabled_usernames': [],
                  'editable_username': 'currentname',
                  'collectible_usernames': [],
                },
              };
            case 'getSupergroupFullInfo':
              return {'@type': 'supergroupFullInfo', 'member_count': 1};
            default:
              return {'@type': 'ok'};
          }
        },
        send: (_) async {},
        updates: const Stream.empty(),
      ),
    );
  });
  tearDownAll(TdClient.shared.closeProxy);

  Future<void> pumpView(WidgetTester tester) async {
    currentChat = {
      '@type': 'chat',
      'id': 42,
      'title': 'Group',
      'type': {
        '@type': 'chatTypeSupergroup',
        'supergroup_id': 10,
        'is_channel': false,
      },
    };
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

  testWidgets('clearing the public username sends an empty string', (
    tester,
  ) async {
    await pumpView(tester);
    expect(find.text('@currentname'), findsOneWidget);

    requests.clear();
    await tester.tap(find.text('Public Username'));
    await tester.pumpAndSettle();
    expect(find.byType(EditFieldView), findsOneWidget);

    // Clear the field with the trailing x button, then save.
    await tester.tap(
      find
          .byWidgetPredicate(
            (w) => w is AppIcon && w.icon == HeroAppIcons.xmark,
          )
          .first,
    );
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final clear = requests
        .where((r) => r['@type'] == 'setSupergroupUsername')
        .toList();
    expect(clear, hasLength(1));
    expect(clear.single['username'], '');
  });
}
