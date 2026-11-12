import 'dart:async';

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

  final requests = <Map<String, dynamic>>[];
  final Map<String, dynamic> selfStatus = {'@type': 'chatMemberStatusCreator'};
  Map<String, dynamic> memberStatus = {'@type': 'chatMemberStatusMember'};
  Completer<Map<String, dynamic>>? userGate;

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
                'id': 10,
                'type': {'@type': 'chatTypeSupergroup', 'supergroup_id': 20},
              };
            case 'getMe':
              return {'@type': 'user', 'id': 1, 'first_name': 'Me'};
            case 'getChatMember':
              return {'@type': 'chatMember', 'status': selfStatus};
            case 'getSupergroupFullInfo':
              return {'@type': 'supergroupFullInfo', 'member_count': 2};
            case 'getSupergroupMembers':
              return {
                '@type': 'chatMembers',
                'member_count': 2,
                'members': [
                  {
                    '@type': 'chatMember',
                    'member_id': {'@type': 'messageSenderUser', 'user_id': 42},
                    'status': memberStatus,
                  },
                  if (userGate != null)
                    {
                      '@type': 'chatMember',
                      'member_id': {
                        '@type': 'messageSenderUser',
                        'user_id': 43,
                      },
                      'status': memberStatus,
                    },
                ],
              };
            case 'getUser':
              if (request['user_id'] == 42 && userGate != null) {
                return userGate!.future;
              }
              return {
                '@type': 'user',
                'id': 42,
                'first_name': 'Bob',
                'last_name': '',
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
    userGate = null;
    requests.clear();
    memberStatus = {'@type': 'chatMemberStatusMember'};
    selfStatus['@type'] = 'chatMemberStatusCreator';
  });

  Future<void> pumpView(WidgetTester tester, {bool settle = true}) async {
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeController(await SharedPreferences.getInstance());
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
          home: const ChatMembersView(chatId: 10, title: 'Group'),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets(
    'a disposed member view never falls back to active-account reads',
    (tester) async {
      userGate = Completer<Map<String, dynamic>>();
      await pumpView(tester, settle: false);
      expect(
        requests.where((r) => r['@type'] == 'getUser' && r['user_id'] == 42),
        isNotEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      requests.clear();
      userGate!.complete({'@type': 'user', 'id': 42, 'first_name': 'Held'});
      userGate = null;
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        requests.where((r) => r['@type'] == 'getUser'),
        isEmpty,
        reason: 'released view ownership must not resume on the active account',
      );
    },
  );

  testWidgets('unrestricting a member who left keeps them out of the group', (
    tester,
  ) async {
    memberStatus = {
      '@type': 'chatMemberStatusRestricted',
      'is_member': false,
      'restricted_until_date': 0,
      'permissions': {
        '@type': 'chatPermissions',
        'can_send_basic_messages': false,
      },
    };
    await pumpView(tester);
    await tester.drag(find.text('Bob'), const Offset(-120, 0));
    await tester.pumpAndSettle();

    requests.clear();
    await tester.tap(find.text('Remove restrictions'));
    await tester.pumpAndSettle();

    final set = requests
        .where((r) => r['@type'] == 'setChatMemberStatus')
        .toList();
    expect(set, hasLength(1));
    // Left lifts the restrictions without re-adding the user; Member
    // would invite them back into the group.
    expect(set.single['status']['@type'], 'chatMemberStatusLeft');
  });

  testWidgets(
    'moderation queries stay pinned to the account that opened the view',
    (tester) async {
      // The view must retain the slot that was active when it opened (the
      // proxy pins slot 0) and route every query through that lease, so a
      // later foreground switch cannot retarget in-flight or
      // post-confirmation mutations.
      await pumpView(tester);
      expect(TdClient.shared.activeSlot, 0);

      await tester.drag(find.text('Bob'), const Offset(-120, 0));
      await tester.pumpAndSettle();

      requests.clear();
      await tester.tap(find.text('Restrict'));
      await tester.pumpAndSettle();
      final sheet = find.byType(Scrollable).last;
      final sheetState = tester.state<ScrollableState>(sheet);
      for (
        var i = 0;
        i < 40 && find.text('Apply').hitTestable().evaluate().isEmpty;
        i++
      ) {
        sheetState.position.jumpTo(
          (sheetState.position.pixels + 250).clamp(
            0.0,
            sheetState.position.maxScrollExtent,
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      final set = requests
          .where((r) => r['@type'] == 'setChatMemberStatus')
          .toList();
      expect(set, hasLength(1));
    },
  );

  testWidgets(
    'a restriction confirmation that outlives its view sends nothing',
    (tester) async {
      // Confirmation-lifecycle regression: the modal sheet stays open while
      // the underlying view is disposed (e.g. the account switcher replaced
      // the page). Applying the sheet must not send any mutation.
      await pumpView(tester);
      await tester.drag(find.text('Bob'), const Offset(-120, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Restrict'));
      await tester.pumpAndSettle();
      final sheet = find.byType(Scrollable).last;
      final sheetState = tester.state<ScrollableState>(sheet);
      for (
        var i = 0;
        i < 40 && find.text('Apply').hitTestable().evaluate().isEmpty;
        i++
      ) {
        sheetState.position.jumpTo(
          (sheetState.position.pixels + 250).clamp(
            0.0,
            sheetState.position.maxScrollExtent,
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Replace the page under the sheet, then apply.
      final applyCenter = tester.getCenter(find.text('Apply').hitTestable());
      final element = find.byType(ChatMembersView).evaluate().single;
      final navigator = element.findAncestorStateOfType<NavigatorState>()!;
      unawaited(
        navigator.pushReplacement(
          MaterialPageRoute(builder: (_) => const Scaffold(body: SizedBox())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ChatMembersView), findsNothing);

      requests.clear();
      await tester.tapAt(applyCenter);
      await tester.pumpAndSettle();
      expect(
        requests.where((r) => r['@type'] == 'setChatMemberStatus'),
        isEmpty,
      );
    },
  );
}
