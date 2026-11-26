// The AI Settings switch that removes the composer's AI Reply button.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/ai_translation/ai_reply_service.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/composer/chat_input_bar.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/ai_translation/ai_settings_controller.dart';
import 'package:mithka/settings/ai_translation/ai_settings_view.dart';
import 'package:mithka/settings/ai_translation/apple_pcc_api.dart';
import 'package:mithka/settings/ai_translation/translation_controller.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _composerButton = ValueKey('composerAiReplyButton');
const _settingsRow = ValueKey('aiShowComposerButtonRow');

class _ComposerTestChatViewModel extends ChatViewModel {
  _ComposerTestChatViewModel({super.sessionMessages})
    : super(chatId: 1, title: 'Project', markReadOnOpen: false);

  @override
  void sendTyping() {}

  @override
  void setDraft(
    String value, {
    String? formattedText,
    List<Map<String, dynamic>> entities = const [],
  }) {
    draft = value;
  }
}

AiSettingsController _settings(SharedPreferences preferences) =>
    AiSettingsController(
      preferences,
      pccApi: ApplePccApi(invokeMethod: (_, _) async => {'available': false}),
      secureRead: (_) async => null,
      secureWrite: (_, _) async {},
    );

Widget _app({
  required ThemeController theme,
  required AiSettingsController settings,
  TranslationController? translation,
  required Widget home,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeController>.value(value: theme),
      ChangeNotifierProvider<AiSettingsController>.value(value: settings),
      if (translation != null)
        ChangeNotifierProvider<TranslationController>.value(value: translation),
    ],
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

void main() {
  test('defaults to showing the button and persists the choice', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final settings = _settings(preferences);
    addTearDown(settings.dispose);
    await settings.initialize();

    expect(settings.showComposerAiButton, isTrue);
    expect(
      preferences.getBool(
        AiSettingsController.showComposerAiButtonPreferenceKey,
      ),
      isNull,
    );

    var notifications = 0;
    settings.addListener(() => notifications++);
    await settings.setShowComposerAiButton(false);
    expect(settings.showComposerAiButton, isFalse);
    expect(notifications, 1);
    expect(
      preferences.getBool(
        AiSettingsController.showComposerAiButtonPreferenceKey,
      ),
      isFalse,
    );

    // A fresh controller restores the choice before it even initializes.
    final restored = _settings(preferences);
    addTearDown(restored.dispose);
    expect(restored.showComposerAiButton, isFalse);
    await restored.initialize();
    expect(restored.showComposerAiButton, isFalse);
  });

  test('refreshes an existing controller after preferences reload', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final settings = _settings(preferences);
    addTearDown(settings.dispose);
    await settings.initialize();
    final capabilities = settings.pccCapabilities;
    var notifications = 0;
    settings.addListener(() => notifications++);

    // Another engine writes to storage; this window still has its old cache.
    final store = SharedPreferencesStorePlatform.instance;
    const key =
        'flutter.${AiSettingsController.showComposerAiButtonPreferenceKey}';
    await store.setValue('Bool', key, false);
    expect(settings.showComposerAiButton, isTrue);
    settings.refreshComposerButtonPreference();
    expect(settings.showComposerAiButton, isTrue);
    expect(notifications, 0);

    await preferences.reload();
    settings.refreshComposerButtonPreference();
    expect(settings.showComposerAiButton, isFalse);
    expect(notifications, 1);
    settings.refreshComposerButtonPreference();
    expect(notifications, 1);

    // Removing the stored choice restores the default in the same controller.
    await store.remove(key);
    await preferences.reload();
    settings.refreshComposerButtonPreference();
    expect(settings.showComposerAiButton, isTrue);
    expect(notifications, 2);
    expect(settings.initialized, isTrue);
    expect(settings.pccCapabilities, same(capabilities));
    expect(
      preferences.getBool(
        AiSettingsController.showComposerAiButtonPreferenceKey,
      ),
      isNull,
    );
  });

  testWidgets('composer refreshes the AI button in an already-open window', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);
    final settings = _settings(preferences);
    addTearDown(settings.dispose);
    await settings.initialize();

    final vm = _ComposerTestChatViewModel(
      sessionMessages: [
        ChatMessage(
          id: 7,
          isOutgoing: false,
          text: 'Can you join at three?',
          date: 1,
          senderName: 'Alice',
          contentType: 'messageText',
        ),
      ],
    );
    addTearDown(vm.dispose);

    await tester.pumpWidget(
      _app(
        theme: theme,
        settings: settings,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatInputBar(
              vm: vm,
              onStartCall: (_) {},
              onMessageSent: () {},
              aiReplyHistoryLoader:
                  ({
                    required beforeMessageId,
                    required query,
                    required limit,
                  }) async => const AiReplyChatHistoryPage.empty(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(_composerButton), findsOneWidget);
    final fieldWidthWithButton = tester.getSize(find.byType(TextField)).width;

    final mainSettings = _settings(preferences);
    addTearDown(mainSettings.dispose);
    await mainSettings.setShowComposerAiButton(false);
    expect(settings.showComposerAiButton, isTrue);
    await preferences.reload();
    settings.refreshComposerButtonPreference();
    await tester.pump();

    expect(find.byKey(_composerButton), findsNothing);
    // No space is held back for the removed button.
    expect(
      tester.getSize(find.byType(TextField)).width,
      greaterThan(fieldWidthWithButton),
    );

    await mainSettings.setShowComposerAiButton(true);
    await preferences.reload();
    settings.refreshComposerButtonPreference();
    await tester.pump();

    expect(find.byKey(_composerButton), findsOneWidget);
  });

  testWidgets('AI Settings switch toggles and persists the button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);
    final translation = TranslationController(
      preferences,
      secureRead: (_) async => null,
      secureWrite: (_, _) async {},
    );
    addTearDown(translation.dispose);
    final settings = _settings(preferences);
    addTearDown(settings.dispose);
    await settings.initialize();

    await tester.pumpWidget(
      _app(
        theme: theme,
        settings: settings,
        translation: translation,
        home: const AiSettingsView(),
      ),
    );
    await tester.pump();

    final row = find.byKey(_settingsRow);
    expect(row, findsOneWidget);
    expect(find.text('Show AI Button in Message Box'), findsOneWidget);
    expect(
      find.text(
        'Turn off to remove the sparkle button next to the message field.',
      ),
      findsOneWidget,
    );
    expect(tester.widget<SettingsSwitchRow>(row).value, isTrue);

    await tester.tap(row);
    await tester.pump();

    expect(settings.showComposerAiButton, isFalse);
    expect(tester.widget<SettingsSwitchRow>(row).value, isFalse);
    expect(
      preferences.getBool(
        AiSettingsController.showComposerAiButtonPreferenceKey,
      ),
      isFalse,
    );

    await tester.tap(row);
    await tester.pump();

    expect(settings.showComposerAiButton, isTrue);
    expect(
      preferences.getBool(
        AiSettingsController.showComposerAiButtonPreferenceKey,
      ),
      isTrue,
    );
  });
}
