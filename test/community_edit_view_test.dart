import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/communities/community_edit_view.dart';
import 'package:mithka/communities/community_models.dart';
import 'package:mithka/communities/community_view.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/edit_field_view.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The community profile editor mirrors the iOS CommunityEditScreen: the hub's
// ellipsis menu gains an Edit Profile entry only for creators and admins
// holding can_change_info, the name round-trips through setCommunityName, and
// a TDLib too old to know the method answers with a parse-level error that
// must surface as an explicit "not supported yet" toast rather than a generic
// failure.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final requests = <Map<String, dynamic>>[];
  // Set by the unsupported-method test so setCommunityName answers with the
  // parse-level error a pinned pre-1.8.68 tdjson produces.
  var rejectCommunityName = false;

  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          requests.add(Map<String, dynamic>.from(request));
          if (request['@type'] == 'setCommunityName' && rejectCommunityName) {
            return {
              '@type': 'error',
              'code': 400,
              'message': 'Failed to parse JSON object as TDLib request',
            };
          }
          return {'@type': 'ok'};
        },
        send: (_) async {},
        updates: const Stream<Map<String, dynamic>>.empty(),
      ),
    );
  });
  tearDownAll(TdClient.shared.closeProxy);

  setUp(requests.clear);

  CommunitySummary community({required bool canChangeInfo}) => CommunitySummary(
    id: 42,
    name: 'Formula Paddock',
    haveAccess: true,
    isAdministrator: canChangeInfo,
    canEditChatList: true,
    canChangeInfo: canChangeInfo,
  );

  Future<void> pumpHome(
    WidgetTester tester,
    Widget home, {
    bool settle = true,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  group('canChangeInfo', () {
    test('the creator status carries the right', () {
      final parsed = CommunitySummary.fromTd({
        '@type': 'community',
        'id': '42',
        'have_access': true,
        'name': 'Formula Paddock',
        'status': {'@type': 'communityMemberStatusCreator'},
      });
      expect(parsed.canChangeInfo, isTrue);
    });

    test('an administrator needs can_change_info in the rights', () {
      final withoutRight = CommunitySummary.fromTd({
        '@type': 'community',
        'id': '42',
        'name': 'Formula Paddock',
        'status': {
          '@type': 'communityMemberStatusAdministrator',
          'rights': {
            '@type': 'communityAdministratorRights',
            'can_edit_chat_list': true,
          },
        },
      });
      expect(withoutRight.canChangeInfo, isFalse);

      final withRight = CommunitySummary.fromTd({
        '@type': 'community',
        'id': '42',
        'name': 'Formula Paddock',
        'status': {
          '@type': 'communityMemberStatusAdministrator',
          'rights': {
            '@type': 'communityAdministratorRights',
            'can_change_info': true,
          },
        },
      });
      expect(withRight.canChangeInfo, isTrue);
    });

    test('merge keeps the flag when TDLib re-delivers the community', () {
      final source = community(canChangeInfo: true);
      final target = community(canChangeInfo: false);
      target.merge(source);
      expect(target.canChangeInfo, isTrue);
    });
  });

  testWidgets('the hub menu hides Edit Profile without the right', (
    tester,
  ) async {
    await pumpHome(
      tester,
      CommunityView(
        community: community(canChangeInfo: false),
        chats: const [],
        onCollapsedChanged: (_) {},
      ),
    );

    await tester.tap(find.byKey(const ValueKey('community-header-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Show as One Chat'), findsOneWidget);
    expect(find.text('Edit Profile'), findsNothing);

    // Close the menu so nothing outlives the test.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
  });

  testWidgets('the hub menu opens the editor with the right', (tester) async {
    await pumpHome(
      tester,
      CommunityView(
        community: community(canChangeInfo: true),
        chats: const [],
        onCollapsedChanged: (_) {},
      ),
    );

    await tester.tap(find.byKey(const ValueKey('community-header-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Edit Profile'), findsOneWidget);

    await tester.tap(find.text('Edit Profile'));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityEditView), findsOneWidget);
    // The editor renders the name in the avatar card and the row value.
    expect(find.text('Formula Paddock'), findsNWidgets(2));

    // Pop back via the editor's chevron so the route settles before teardown.
    // pageBack() can't be used: the app's NavHeader owns a custom back control.
    await tester.tap(find.byIcon(HeroAppIcons.chevronLeft.data));
    await tester.pumpAndSettle();
  });

  testWidgets('saving a name round-trips through setCommunityName', (
    tester,
  ) async {
    final summary = community(canChangeInfo: true);
    await pumpHome(
      tester,
      CommunityEditView(community: summary),
      settle: false,
    );
    // SettingsListView settles without any pending animation, but a fixed
    // frame budget keeps this pump independent of scaffold transitions.
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const ValueKey('community-edit-name')));
    await tester.pumpAndSettle();
    expect(find.byType(EditFieldView), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Paddock Club');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final request = requests.last;
    expect(request['@type'], 'setCommunityName');
    expect(request['community_id'], 42);
    expect(request['name'], 'Paddock Club');

    // The editor mutates the shared summary in place, so the hub header and
    // the row both reflect the new name without a re-fetch.
    expect(summary.name, 'Paddock Club');
    expect(find.text('Paddock Club'), findsWidgets);
    expect(find.text('Formula Paddock'), findsNothing);
  });

  testWidgets('an old TDLib library degrades into the unsupported toast', (
    tester,
  ) async {
    rejectCommunityName = true;
    addTearDown(() => rejectCommunityName = false);

    await pumpHome(
      tester,
      CommunityEditView(community: community(canChangeInfo: true)),
      settle: false,
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const ValueKey('community-edit-name')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Paddock Club');
    await tester.tap(find.text('Save'));

    // The error toast rides an overlay timer, so it needs discrete pumps to
    // appear and to drain before teardown.
    const toast = 'The bundled TDLib build doesn’t support this yet';
    var reported = false;
    for (var round = 0; round < 6 && !reported; round++) {
      await tester.pump(const Duration(milliseconds: 100));
      reported = find.text(toast).evaluate().isNotEmpty;
    }
    expect(reported, isTrue, reason: 'the unsupported toast is visible');

    for (var i = 0; i < 45; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text(toast), findsNothing);

    // The editor stayed on screen and the name was not applied locally.
    expect(find.byType(CommunityEditView), findsOneWidget);
    // The editor renders the name in the avatar card and the row value.
    expect(find.text('Formula Paddock'), findsNWidgets(2));
  });
}
