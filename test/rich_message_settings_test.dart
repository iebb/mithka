import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_input_bar.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/l10n/messages/de.dart';
import 'package:mithka/l10n/messages/en.dart';
import 'package:mithka/l10n/messages/es.dart';
import 'package:mithka/l10n/messages/fr.dart';
import 'package:mithka/l10n/messages/ja.dart';
import 'package:mithka/l10n/messages/ko.dart';
import 'package:mithka/l10n/messages/zh_hans.dart';
import 'package:mithka/l10n/messages/zh_hant.dart';
import 'package:mithka/settings/advanced_settings_view.dart';
import 'package:mithka/settings/rich_message_relay_view.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NonPremiumChatViewModel extends ChatViewModel {
  _NonPremiumChatViewModel()
    : super(chatId: 1, title: 'Test chat', markReadOnOpen: false);

  @override
  Future<bool> currentUserIsPremium() async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (call) async {
          if (call.method == 'containsKey') return false;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  test('relay setup copy exists in every supported locale', () {
    const tables = [
      enMessages,
      deMessages,
      esMessages,
      frMessages,
      jaMessages,
      koMessages,
      zhHansMessages,
      zhHantMessages,
    ];
    const keys = [
      'advancedInput',
      'advancedTitle',
      'richTextRelayBotCreateDescription',
      'richTextRelayBotOpenBotFather',
      'richTextRelayBotSetupTitle',
      'richTextRelayBotSetupDescription',
      'richTextRelayBotConfigure',
    ];

    for (final table in tables) {
      for (final key in keys) {
        expect(table[key]?.trim(), isNotEmpty, reason: 'missing $key');
      }
    }
  });

  testWidgets('Advanced settings owns the rich message relay entry', (
    tester,
  ) async {
    final theme = await _themeController();
    addTearDown(theme.dispose);
    await tester.pumpWidget(_app(theme, const AdvancedSettingsView()));
    await tester.pumpAndSettle();

    expect(find.text('Advanced'), findsOneWidget);
    expect(find.text('Input'), findsOneWidget);
    expect(find.text('Rich message relay bot'), findsOneWidget);
    expect(find.text('Not configured'), findsOneWidget);
  });

  testWidgets('non-Premium rich message action offers relay setup', (
    tester,
  ) async {
    final theme = await _themeController();
    final vm = _NonPremiumChatViewModel();
    addTearDown(theme.dispose);
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      _app(
        theme,
        Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatInputBar(
              vm: vm,
              onStartCall: (_) {},
              onMessageSent: () {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(HeroAppIcons.circlePlus.data));
    await tester.pump();
    await tester.tap(find.text('Rich text'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.text('Configure a relay bot?'), findsOneWidget);
    expect(find.text('Configure'), findsOneWidget);

    await tester.tap(find.text('Configure'));
    await tester.pumpAndSettle();

    expect(find.text('Rich message relay bot'), findsOneWidget);
    expect(find.text('Create a bot with @BotFather'), findsOneWidget);
    expect(
      tester
          .widget<GestureDetector>(
            find.byKey(const ValueKey('rich-message-open-botfather')),
          )
          .onTap,
      isNotNull,
    );
  });

  testWidgets('relay header paints through the system status area', (
    tester,
  ) async {
    final theme = await _themeController();
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      _app(
        theme,
        const MediaQuery(
          data: MediaQueryData(padding: EdgeInsets.only(top: 44)),
          child: RichMessageRelayView(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final header = find.byType(NavHeader);
    expect(tester.getTopLeft(header).dy, 0);
    expect(tester.getSize(header).height, theme.navHeaderHeight + 44);
  });
}

Future<ThemeController> _themeController() async {
  SharedPreferences.setMockInitialValues({});
  return ThemeController(await SharedPreferences.getInstance());
}

Widget _app(ThemeController theme, Widget home) {
  return ChangeNotifierProvider<ThemeController>.value(
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
  );
}
