import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/profile/profile_detail_view.dart';
import 'package:mithka/profile/registration_date_estimate.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = 5555116287;
  const rawPhone = '37281981998';
  // Past the newest anchor: an ID the table has no position for, so the page
  // owes it no date and no bound.
  const undateableUserId = 99999999999;

  late Future<Map<String, dynamic>> Function(Map<String, dynamic>) handler;
  final clipboard = <String>[];
  var clipboardDenied = false;

  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) => handler(request),
        send: (_) async {},
        updates: const Stream<Map<String, dynamic>>.empty(),
      ),
    );
  });

  tearDownAll(TdClient.shared.closeProxy);

  setUp(() {
    clipboard.clear();
    clipboardDenied = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            if (clipboardDenied) {
              throw PlatformException(
                code: 'CLIPBOARD_DENIED',
                message: 'clipboard unavailable',
              );
            }
            final arguments = call.arguments;
            if (arguments is Map) clipboard.add('${arguments['text']}');
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  /// Serves one user whose private chat carries [accountInfo] in its action
  /// bar — Telegram's own registration month — or nothing at all.
  void serveProfile({
    Map<String, dynamic>? accountInfo,
    String bio = '',
    bool isBot = false,
    String? userType,
  }) {
    handler = (request) async {
      switch (request['@type']) {
        case 'getMe':
          return {'@type': 'user', 'id': 1, 'first_name': 'Me'};
        case 'getUser':
          return {
            '@type': 'user',
            'id': request['user_id'],
            'first_name': 'ieb',
            'last_name': '',
            'phone_number': rawPhone,
            'usernames': {
              '@type': 'usernames',
              'active_usernames': ['nekoko14'],
              'editable_username': 'nekoko14',
            },
            'type': {
              '@type': userType ?? (isBot ? 'userTypeBot' : 'userTypeRegular'),
              if (isBot) 'can_join_groups': false,
              if (isBot) 'can_read_all_group_messages': false,
              if (isBot) 'supports_inline_queries': false,
              if (isBot) 'is_chat_admin': false,
            },
            'status': {'@type': 'userStatusOffline', 'was_online': 0},
          };
        case 'getUserFullInfo':
          return {
            '@type': 'userFullInfo',
            if (bio.isNotEmpty) 'bio': {'@type': 'formattedText', 'text': bio},
          };
        case 'getUserProfilePhotos':
          return {'@type': 'photos', 'total_count': 0, 'photos': <dynamic>[]};
        case 'createPrivateChat':
          return {
            '@type': 'chat',
            'id': 42,
            'action_bar': {
              '@type': 'chatActionBarReportSpam',
              'can_unarchive': false,
              'distance': 0,
              'account_info': ?accountInfo,
            },
          };
        default:
          return {'@type': 'ok'};
      }
    };
  }

  Future<void> pumpProfile(WidgetTester tester, {int id = userId}) async {
    // The test font draws every glyph as a full-width box, so the bottom bar's
    // two fixed labels need a wider surface than a phone to fit; nothing here
    // asserts on layout.
    tester.view.physicalSize = const Size(560, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
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
          home: ProfileDetailView(userId: id, name: 'ieb'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Lets every copy toast run out so no timer outlives the test: fade in,
  /// hold, then fade out and remove.
  Future<void> drainToast(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
  }

  /// The row the page should show for an [id] it estimated, built the way the
  /// page builds it.
  String expectedRow(int id) {
    final estimate = estimateRegistrationDate(id)!;
    return AppStrings.t(AppStringKeys.profileDetailRegistrationAroundValue1, {
      'value1': DateFormat.yMMMM('en').format(estimate),
    });
  }

  testWidgets("shows Telegram's own registration month when it has one", (
    tester,
  ) async {
    serveProfile(
      accountInfo: {'registration_year': 2021, 'registration_month': 3},
    );
    await pumpProfile(tester);

    expect(find.text('Registration'), findsOneWidget);
    expect(find.text('March 2021'), findsOneWidget);
    // A month Telegram reported is a fact, so it carries no estimate qualifier.
    expect(find.textContaining('Around'), findsNothing);
  });

  testWidgets('estimates the registration month from the user ID', (
    tester,
  ) async {
    serveProfile();
    await pumpProfile(tester);

    expect(estimateRegistrationDate(userId), isNotNull);
    expect(find.text('Registration'), findsOneWidget);
    // The estimate says so out loud rather than posing as a date on file.
    expect(find.text(expectedRow(userId)), findsOneWidget);
    expect(find.textContaining('Around'), findsOneWidget);
  });

  testWidgets('leaves out an ID the anchor table has no position for', (
    tester,
  ) async {
    serveProfile(bio: 'just a cat');
    await pumpProfile(tester, id: undateableUserId);

    expect(estimateRegistrationDate(undateableUserId), isNull);
    // The card still renders for the bio; only the row it cannot support is
    // gone. Bounding the account from below would claim more than the fitted
    // table proves, so the page claims nothing instead.
    expect(find.text('just a cat').last, findsOneWidget);
    expect(find.text('Registration'), findsNothing);
    expect(find.textContaining('After'), findsNothing);
  });

  testWidgets('never estimates a bot, whose IDs the dataset excludes', (
    tester,
  ) async {
    serveProfile(bio: 'just a cat', isBot: true);
    await pumpProfile(tester);

    // The same ID on a human account does date, so what rules this one out is
    // the profile being a bot.
    expect(estimateRegistrationDate(userId), isNotNull);
    expect(find.text('just a cat').last, findsOneWidget);
    expect(find.text('Registration'), findsNothing);
  });

  for (final type in ['userTypeUnknown', 'userTypeDeleted']) {
    testWidgets('never estimates an unverified regular profile: $type', (
      tester,
    ) async {
      serveProfile(userType: type);
      await pumpProfile(tester);

      expect(estimateRegistrationDate(userId), isNotNull);
      expect(find.text('Registration'), findsNothing);
    });
  }

  testWidgets('an authoritative month does not need an ID-based estimate', (
    tester,
  ) async {
    serveProfile(
      userType: 'userTypeUnknown',
      accountInfo: {'registration_year': 2021, 'registration_month': 3},
    );
    await pumpProfile(tester);

    expect(find.text('March 2021'), findsOneWidget);
    expect(find.textContaining('Around'), findsNothing);
  });

  testWidgets('copies the Telegram ID without its label', (tester) async {
    serveProfile();
    await pumpProfile(tester);

    // Reading a page must not fill the clipboard, so a plain tap does nothing.
    await tester.tap(find.text('TG: $userId'));
    await tester.pump();
    expect(clipboard, isEmpty);

    await tester.longPress(find.text('TG: $userId'));
    await tester.pumpAndSettle();

    expect(clipboard, ['$userId']);
    expect(find.text('Copied'), findsOneWidget);
    await drainToast(tester);
  });

  testWidgets('copies the username and the dialable phone number', (
    tester,
  ) async {
    serveProfile();
    await pumpProfile(tester);

    // The pill draws '@' and the name as two boxes, so the press target is the
    // pill itself rather than a text finder.
    await tester.longPress(find.byKey(const ValueKey('profileUsernamePill')));
    await tester.pumpAndSettle();
    await tester.longPress(find.text(TDParse.formatPhone(rawPhone)));
    await tester.pumpAndSettle();

    expect(clipboard, ['@nekoko14', '+$rawPhone']);
    await drainToast(tester);
  });

  testWidgets('copies an info row, registration date included', (tester) async {
    serveProfile(
      accountInfo: {'registration_year': 2021, 'registration_month': 3},
      bio: 'just a cat',
    );
    await pumpProfile(tester);

    await tester.longPress(find.text('March 2021'));
    await tester.pumpAndSettle();
    // The bio shows once in the header and once in the info card; the card is
    // the copyable one and comes last.
    await tester.longPress(find.text('just a cat').last);
    await tester.pumpAndSettle();

    expect(clipboard, ['March 2021', 'just a cat']);
    await drainToast(tester);
  });

  testWidgets(
    'reports a copy the clipboard refused instead of a fake success',
    (tester) async {
      serveProfile();
      await pumpProfile(tester);
      clipboardDenied = true;

      await tester.longPress(find.text('TG: $userId'));
      await tester.pumpAndSettle();

      expect(clipboard, isEmpty);
      expect(find.text('Copied'), findsNothing);
      expect(
        find.text(AppStrings.t(AppStringKeys.profileDetailCopyFailed)),
        findsOneWidget,
      );
      await drainToast(tester);
    },
  );
}
