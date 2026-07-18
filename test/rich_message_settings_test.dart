import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_input_bar.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/rich_message_source.dart';
import 'package:mithka/chat/rich_text_composer_view.dart';
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
import 'package:mithka/settings/rich_message_relay_config.dart';
import 'package:mithka/settings/rich_message_relay_view.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NonPremiumChatViewModel extends ChatViewModel {
  _NonPremiumChatViewModel()
    : super(chatId: 1, title: 'Test chat', markReadOnOpen: false);

  @override
  Future<bool> currentUserIsPremium() async => false;
}

class _UnsupportedPremiumChatViewModel extends ChatViewModel {
  _UnsupportedPremiumChatViewModel()
    : super(chatId: 1, title: 'Test chat', markReadOnOpen: false);

  var sendAttempts = 0;

  @override
  Future<bool> currentUserIsPremium() async => true;

  @override
  Future<void> sendRichMessageHtml(
    String html, {
    List<RichMessageSendFile> files = const [],
    List<Map<String, dynamic>> blocks = const [],
  }) async {
    sendAttempts++;
    throw TdError({
      'code': 400,
      'message': 'Unknown class "richMessageSourceBlocks"',
    });
  }
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

  test(
    'relay token storage is optional when secure storage is unavailable',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorage, null);

      expect(await RichMessageRelayConfig.readToken(), isNull);
      expect(await RichMessageRelayConfig.isConfigured(), isFalse);
      await RichMessageRelayConfig.saveToken('123:abc');
      await RichMessageRelayConfig.clear();
    },
  );

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

  testWidgets('relay token input exposes the platform paste menu', (
    tester,
  ) async {
    final theme = await _themeController();
    addTearDown(theme.dispose);
    await tester.pumpWidget(_app(theme, const RichMessageRelayView()));
    await tester.pumpAndSettle();

    final textFieldFinder = find.byType(TextField);
    expect(textFieldFinder, findsOneWidget);
    final fieldFinder = find.descendant(
      of: textFieldFinder,
      matching: find.byType(EditableText),
    );
    final field = tester.widget<EditableText>(fieldFinder);
    final editableTextState = tester.state<EditableTextState>(fieldFinder);
    final toolbar = field.contextMenuBuilder?.call(
      tester.element(fieldFinder),
      editableTextState,
    );

    expect(toolbar, isA<AdaptiveTextSelectionToolbar>());
  });

  testWidgets('Premium rich-text send never falls back to the relay bot', (
    tester,
  ) async {
    final theme = await _themeController();
    final vm = _UnsupportedPremiumChatViewModel();
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

    const draft = 'Keep this unsent rich-text draft';
    final initialComposer = find.byType(RichTextComposerView);
    final initialInput = find
        .descendant(of: initialComposer, matching: find.byType(TextField))
        .first;
    await tester.enterText(initialInput, draft);
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(vm.sendAttempts, 1);
    expect(find.text('Configure a relay bot?'), findsNothing);
    final reopenedComposer = find.byType(RichTextComposerView);
    expect(reopenedComposer, findsOneWidget);
    final reopenedInput = tester.widget<TextField>(
      find
          .descendant(of: reopenedComposer, matching: find.byType(TextField))
          .first,
    );
    expect(reopenedInput.controller?.text, draft);
    await tester.pump(const Duration(seconds: 2));
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
