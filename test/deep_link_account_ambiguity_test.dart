import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/chat_deep_link_controller.dart';
import 'package:mithka/app/main_tab_view.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/components/drawer_controller.dart' as dc;
import 'package:mithka/l10n/app_locale_controller.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_bindings.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Regression: an account-less deep link (a t.me link tapped from a chat, a
// desktop handoff that carried no identity, ...) with several signed-in
// accounts used to be dropped silently — no navigation, no error. It must now
// offer an account choice, and picking one must open the chat on that account.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    supportDir = await Directory.systemTemp.createTemp('mithka-ambiguity');
    SharedPreferences.setMockInitialValues(const {});
    client = TdClient.shared;
    client.prepareForTesting(
      prefs: await SharedPreferences.getInstance(),
      supportDir: supportDir.path,
      bindings: _FakeBindings(client),
      queryOverride: (request, clientId) async => switch (request['@type']) {
        'getMe' => switch (clientId) {
          100 => {
            '@type': 'user',
            'id': 1,
            'first_name': 'Alpha',
            'phone_number': '+15550100',
            'type': {'@type': 'userTypeRegular'},
          },
          _ => {
            '@type': 'user',
            'id': 2,
            'first_name': 'Beta',
            'phone_number': '+15550101',
            'type': {'@type': 'userTypeRegular'},
          },
        },
        'getChats' => <String, dynamic>{
          '@type': 'chats',
          'total_count': 0,
          'chat_ids': const <int>[],
        },
        'loadChats' => <String, dynamic>{'@type': 'ok'},
        'getChat' => <String, dynamic>{
          '@type': 'chat',
          'id': request['chat_id'],
          'title': 'Target chat',
          'type': {
            '@type': 'chatTypeSupergroup',
            'supergroup_id': 42,
            'is_channel': false,
          },
          'permissions': {
            '@type': 'chatPermissions',
            'can_send_basic_messages': true,
          },
        },
        'getSupergroup' => <String, dynamic>{
          '@type': 'supergroup',
          'id': 42,
          'status': {'@type': 'chatMemberStatusMember'},
        },
        'getSupergroupFullInfo' => <String, dynamic>{
          '@type': 'supergroupFullInfo',
          'description': '',
          'member_count': 2,
        },
        'getChatHistory' => <String, dynamic>{
          '@type': 'messages',
          'total_count': 0,
          'messages': const <Object>[],
        },
        'getOption' => {'@type': 'optionValueInteger', 'value': '1024'},
        'getCountries' => {'@type': 'countries', 'countries': const []},
        'getCurrentState' => {'@type': 'ok'},
        'getBotApiAccountInfo' => {'@type': 'ok'},
        _ => {'@type': 'ok'},
      },
    );
    slotA = client.addSlot();
    slotB = client.addSlot();
    client.setActive(slotA);
  });
  tearDownAll(() async {
    await client.closeProxy();
    await supportDir.delete(recursive: true);
  });
  setUp(ChatDeepLinkController.shared.consumePending);

  testWidgets('an ambiguous link asks for the account, then opens it', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    final theme = ThemeController(prefs);
    final accounts = AccountStore(prefs);
    final auth = AuthManager();
    final translation = TranslationController(prefs);
    final drawer = dc.DrawerController();
    final deepLinks = ChatDeepLinkController.shared;
    addTearDown(theme.dispose);
    addTearDown(accounts.dispose);
    addTearDown(auth.dispose);
    addTearDown(translation.dispose);
    addTearDown(drawer.dispose);

    await tester.pumpWidget(_shell(theme, accounts, auth, translation, drawer));
    await tester.pump(const Duration(milliseconds: 300));

    // The tap equivalent: an account-less navigation request.
    deepLinks.openChat(
      chatId: -10042,
      title: 'Target chat',
      messageId: 7 << 20,
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('account-picker-dialog')), findsOneWidget);
    expect(find.byKey(ValueKey('account-picker-row-$slotB')), findsOneWidget);
    final dialog = find.byKey(const ValueKey('account-picker-dialog'));
    expect(
      find.descendant(of: dialog, matching: find.text('Alpha')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('Beta')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(ValueKey('account-picker-row-$slotB')));
    await tester.pumpAndSettle();

    // The account was switched and the request replayed on it: the switch
    // re-keyed the shell subtree and the replay opened the chat.
    expect(accounts.activeSlot, slotB);
    final replayed = deepLinks.consumePending();
    expect(
      replayed,
      isNull,
      reason: 'the replay is consumed by the shell; nothing may linger',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
  });

  testWidgets('the picker honours the hide-phone policy', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    final theme = ThemeController(prefs);
    final accounts = AccountStore(prefs);
    final auth = AuthManager();
    final translation = TranslationController(prefs);
    final drawer = dc.DrawerController();
    final deepLinks = ChatDeepLinkController.shared;
    addTearDown(theme.dispose);
    addTearDown(accounts.dispose);
    addTearDown(auth.dispose);
    addTearDown(translation.dispose);
    addTearDown(drawer.dispose);

    // Policy on: the account rows must not expose either phone number.
    theme.hideSidebarPhone = true;
    await tester.pumpWidget(_shell(theme, accounts, auth, translation, drawer));
    await tester.pump(const Duration(milliseconds: 300));

    deepLinks.openChat(
      chatId: -10042,
      title: 'Target chat',
      messageId: 7 << 20,
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    final dialog = find.byKey(const ValueKey('account-picker-dialog'));
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.text('Alpha')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.textContaining('5550100')),
      findsNothing,
      reason: 'a hidden phone must not be rendered by the picker',
    );
    expect(
      find.descendant(of: dialog, matching: find.text('+15550101')),
      findsNothing,
      reason: 'a hidden phone must not be rendered by the picker',
    );

    // Policy off: the phone subtitle is visible again.
    theme.hideSidebarPhone = false;
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.descendant(of: dialog, matching: find.textContaining('5550100')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
  });

  testWidgets('declining the choice drops the request without navigation', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    final theme = ThemeController(prefs);
    final accounts = AccountStore(prefs);
    final auth = AuthManager();
    final translation = TranslationController(prefs);
    final drawer = dc.DrawerController();
    final deepLinks = ChatDeepLinkController.shared;
    addTearDown(theme.dispose);
    addTearDown(accounts.dispose);
    addTearDown(auth.dispose);
    addTearDown(translation.dispose);
    addTearDown(drawer.dispose);

    await tester.pumpWidget(_shell(theme, accounts, auth, translation, drawer));
    await tester.pump(const Duration(milliseconds: 300));

    deepLinks.openChat(chatId: -10042, title: 'Target chat');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('account-picker-dialog')), findsOneWidget);

    await tester.tapAt(const Offset(10, 10)); // dismiss outside the dialog
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('account-picker-dialog')), findsNothing);
    // Declined: no chat view may be pushed for the ambiguous target.
    expect(find.text('Target chat'), findsNothing);
    expect(deepLinks.consumePending(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
  });
}

Widget _shell(
  ThemeController theme,
  AccountStore accounts,
  AuthManager auth,
  TranslationController translation,
  dc.DrawerController drawer,
) {
  final deepLinks = ChatDeepLinkController.shared;
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeController>.value(value: theme),
      ChangeNotifierProvider<AppLocaleController>.value(
        value: AppLocaleController(prefsSingleton),
      ),
      ChangeNotifierProvider<AccountStore>.value(value: accounts),
      ChangeNotifierProvider<AuthManager>.value(value: auth),
      ChangeNotifierProvider<TranslationController>.value(value: translation),
      ChangeNotifierProvider<ChatDeepLinkController>.value(value: deepLinks),
      ChangeNotifierProvider<dc.DrawerController>.value(value: drawer),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        brightness: Brightness.light,
        extensions: [AppColors.light],
      ),
      home: const MainSplitRootView(),
    ),
  );
}

// Set in setUp before the shell is built.
SharedPreferences? _prefs;
SharedPreferences get prefsSingleton => _prefs!;

late Directory supportDir;
late TdClient client;
late int slotA;
late int slotB;

class _FakeBindings implements TdBindings {
  _FakeBindings(this._client);

  final TdClient _client;

  @override
  int createClientId() => _nextId++;
  int _nextId = 100;

  @override
  void send(int clientId, String request) {
    final decoded = jsonDecode(request) as Map<String, dynamic>;
    if (decoded['@type'] == 'close') {
      _client.debugCompleteClientClosed(clientId);
    }
  }

  @override
  void importSessionString(String s, String path) =>
      File(path).writeAsBytesSync(Uint8List.fromList(const [1]));

  @override
  bool get supportsSessionStringBackup => false;

  @override
  bool get supportsTransferBoost => false;

  @override
  String? receive(double timeout) => throw UnimplementedError();

  @override
  Object? receiveJson(double timeout) => throw UnimplementedError();

  @override
  String? execute(String request) => throw UnimplementedError();

  @override
  String exportSessionString(
    String source, {
    required int apiId,
    required bool testMode,
    required int userId,
  }) => throw UnimplementedError();

  @override
  void configureTransferBoost({
    required int downloadChunkSize,
    required int downloadParallelism,
    required int uploadChunkSize,
    required int uploadParallelism,
  }) {}
}
