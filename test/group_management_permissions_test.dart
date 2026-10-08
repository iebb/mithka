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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> currentChat = {};
  bool currentIsForum = false;
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
                'is_forum': currentIsForum,
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

  Map<String, dynamic> supergroupChat({bool isChannel = false}) => {
    '@type': 'chat',
    'id': 42,
    'title': isChannel ? 'Channel' : 'Group',
    'type': {
      '@type': 'chatTypeSupergroup',
      'supergroup_id': 10,
      'is_channel': isChannel,
    },
    'permissions': const {
      '@type': 'chatPermissions',
      'can_send_basic_messages': true,
      'can_send_photos': true,
      'can_send_videos': true,
      'can_send_documents': true,
      'can_send_voice_notes': true,
      'can_send_video_notes': true,
      'can_send_audios': true,
      'can_send_polls': true,
      'can_send_other_messages': true,
      'can_add_link_previews': true,
      'can_react_to_messages': true,
      'can_edit_tag': true,
      'can_invite_users': true,
      'can_pin_messages': false,
      'can_change_info': false,
      'can_create_topics': false,
    },
  };

  Future<void> pumpView(
    WidgetTester tester, {
    required Map<String, dynamic> chat,
    bool isForum = false,
  }) async {
    currentChat = chat;
    currentIsForum = isForum;
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
          // A fresh home per scenario so the previous pump's view (still on
          // the tree) doesn't produce duplicate text finders.
          home: KeyedSubtree(
            key: UniqueKey(),
            child: GroupManagementView(
              chatId: 42,
              title: chat['title'] as String,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('channel header says Manage channel, group says Manage group', (
    tester,
  ) async {
    await pumpView(tester, chat: supergroupChat());
    expect(find.text('Manage group'), findsOneWidget);
    expect(find.text('Manage channel'), findsNothing);

    await pumpView(tester, chat: supergroupChat(isChannel: true));
    expect(find.text('Manage channel'), findsOneWidget);
    expect(find.text('Manage group'), findsNothing);
  });

  testWidgets('create-topics permission shows only in forum supergroups', (
    tester,
  ) async {
    await pumpView(tester, chat: supergroupChat());
    expect(find.text('Create topics'), findsNothing);

    await pumpView(tester, chat: supergroupChat(), isForum: true);
    await tester.dragUntilVisible(
      find.text('Create topics'),
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    expect(find.text('Create topics'), findsOneWidget);
  });

  testWidgets('saving permissions posts the TDLib 1.8.67 field names', (
    tester,
  ) async {
    requests.clear();
    final chat = supergroupChat();
    currentChat = chat;
    currentIsForum = true;
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
          home: GroupManagementView(chatId: 42, title: chat['title'] as String),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap the switch by position: rect is on-screen after the drag, but
    // finder-based tap resolves to a stale off-screen render object.
    final reactionRow = find.text('Send reactions');
    await tester.dragUntilVisible(
      reactionRow,
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    final switchRect = tester.getRect(
      find
          .descendant(
            of: find
                .ancestor(of: reactionRow, matching: find.byType(Row))
                .first,
            matching: find.byWidgetPredicate((w) {
              if (w is! Container || w.constraints == null) return false;
              final c = w.constraints!;
              return c.minWidth == 24 &&
                  c.maxWidth == 24 &&
                  c.minHeight == 24 &&
                  c.maxHeight == 24;
            }),
          )
          .first,
    );
    await tester.tapAt(switchRect.center);

    expect(
      requests.where((r) => r['@type'] == 'setChatPermissions'),
      isNotEmpty,
    );
    final request = requests.lastWhere(
      (r) => r['@type'] == 'setChatPermissions',
    );
    final permissions = request['permissions'] as Map<String, dynamic>;
    expect(permissions['can_add_link_previews'], isTrue);
    expect(permissions, isNot(contains('can_add_web_page_previews')));
    expect(permissions, isNot(contains('can_manage_topics')));
    expect(permissions['can_react_to_messages'], isFalse);
    expect(permissions['can_edit_tag'], isTrue);
  });
}
