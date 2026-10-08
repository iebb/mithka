import 'dart:async';

import 'dart:io';

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

  testWidgets('restricting a member posts chatMemberStatusRestricted', (
    tester,
  ) async {
    await pumpView(tester);
    expect(find.text('Bob'), findsOneWidget);

    // Swipe the row open (leading edge) to reveal actions.
    await tester.drag(find.text('Bob'), const Offset(-120, 0));
    await tester.pumpAndSettle();

    requests.clear();
    await tester.tap(find.text('Restrict'));
    await tester.pumpAndSettle();
    // The sheet may exceed the viewport; walk down to the Apply button.
    // The sheet's ListView is the last scrollable while the modal is open.
    final sheet = find.byType(Scrollable).last;
    final sheetState = tester.state<ScrollableState>(sheet);
    for (
      var i = 0;
      i < 40 && find.text('Apply').hitTestable().evaluate().isEmpty;
      i++
    ) {
      expect(sheetState.position.maxScrollExtent, greaterThan(0));
      sheetState.position.jumpTo(
        (sheetState.position.pixels + 250).clamp(
          0.0,
          sheetState.position.maxScrollExtent,
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Apply').hitTestable(), findsOneWidget);

    // The sheet shows duration + permission switches; apply with everything
    // off (mute-all default).
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    final set = requests
        .where((r) => r['@type'] == 'setChatMemberStatus')
        .toList();
    expect(set, hasLength(1));
    final status = set.single['status'] as Map<String, dynamic>;
    expect(status['@type'], 'chatMemberStatusRestricted');
    expect(status['is_member'], isTrue);
    final perms = status['permissions'] as Map<String, dynamic>;
    expect(perms['can_send_basic_messages'], isFalse);
  });

  testWidgets('a restricted member offers Remove restrictions', (tester) async {
    memberStatus = {
      '@type': 'chatMemberStatusRestricted',
      'is_member': true,
      'restricted_until_date': 0,
      'permissions': {
        '@type': 'chatPermissions',
        'can_send_basic_messages': false,
      },
    };
    await pumpView(tester);
    await tester.drag(find.text('Bob'), const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(find.text('Remove restrictions'), findsOneWidget);
  });

  testWidgets('a read-only member is not offered moderation actions', (
    tester,
  ) async {
    memberStatus = {
      '@type': 'chatMemberStatusRestricted',
      'is_member': true,
      'restricted_until_date': 0,
      'permissions': {
        '@type': 'chatPermissions',
        'can_send_basic_messages': false,
      },
    };
    selfStatus['@type'] = 'chatMemberStatusMember';
    await pumpView(tester);
    await tester.drag(find.text('Bob'), const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(find.text('Remove restrictions'), findsNothing);
    expect(find.text('Restrict'), findsNothing);
    expect(find.text('Remove'), findsNothing);
  });

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

  testWidgets('unrestricting a present member restores plain membership', (
    tester,
  ) async {
    memberStatus = {
      '@type': 'chatMemberStatusRestricted',
      'is_member': true,
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
    expect(set.single['status']['@type'], 'chatMemberStatusMember');
  });

  testWidgets(
    'moderation queries stay pinned to the account that opened the view',
    (tester) async {
      // The view must retain the slot that was active when it opened (the
      // proxy pins slot 0) and route every query through that lease, so a
      // later foreground switch cannot retarget in-flight or
      // post-confirmation mutations. Source-level contract: the only
      // calls to TdClient.shared.query must not remain as a no-lease fallback.
      final source = File('lib/chat/chat_members_view.dart').readAsStringSync();
      final sharedCalls = RegExp(
        r'TdClient\.shared\.query\(',
      ).allMatches(source).length;
      expect(sharedCalls, 0, reason: 'missing ownership must fail closed');
      expect(source, contains('retainAccountSlot'));
      expect(source, contains('_leaseValid'));

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
