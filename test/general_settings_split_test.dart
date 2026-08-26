import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/general_settings_view.dart';
import 'package:mithka/settings/video_playback_settings_view.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('chat behavior owns the former General chat controls', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'enterToSend': true,
      'openChatsAtLatest': false,
      'showSavedMessagesIdentity': false,
      'preserveSenderWhenRepeating': true,
      'quickRepliesEnabled': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);

    await tester.pumpWidget(_app(theme, const ChatBehaviorSettingsView()));
    await tester.pump();

    expect(
      find.text(
        AppStrings.tForLocale('en', AppStringKeys.settingsChatBehavior),
      ),
      findsOneWidget,
    );
    for (final key in const [
      'chat-behavior-enter-to-send',
      'chat-behavior-open-at-latest',
      'chat-behavior-saved-messages-identity',
      'chat-behavior-preserve-sender',
      'chat-behavior-save-captured-photos',
      'chat-behavior-quick-replies',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }
    expect(
      find.byKey(const ValueKey('chat-behavior-video-playback')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<SettingsSwitchRow>(
            find.byKey(const ValueKey('chat-behavior-enter-to-send')),
          )
          .value,
      isTrue,
    );
    expect(
      find.text(AppStrings.tForLocale('en', AppStringKeys.generalStorage)),
      findsNothing,
    );
    expect(
      find.byType(SettingsLeadingIcon),
      findsNWidgets(7),
      reason: 'detail rows use the shared accent line-icon treatment',
    );
    expect(
      find.byType(SettingsIconTile),
      findsNothing,
      reason: 'coloured destination tiles do not belong inside a detail page',
    );

    await tester.tap(find.byKey(const ValueKey('chat-behavior-enter-to-send')));
    await tester.pump();
    expect(theme.enterToSend, isFalse);
    expect(prefs.getBool('enterToSend'), isFalse);

    final restoredTheme = ThemeController(prefs);
    addTearDown(restoredTheme.dispose);
    expect(restoredTheme.enterToSend, isFalse);

    await tester.tap(
      find.byKey(const ValueKey('chat-behavior-open-at-latest')),
    );
    await tester.pump();
    expect(theme.openChatsAtLatest, isTrue);

    await tester.tap(
      find.byKey(const ValueKey('chat-behavior-saved-messages-identity')),
    );
    await tester.pump();
    expect(theme.showSavedMessagesIdentity, isTrue);
    expect(prefs.getBool('showSavedMessagesIdentity'), isTrue);

    final restoredSavedMessagesTheme = ThemeController(prefs);
    addTearDown(restoredSavedMessagesTheme.dispose);
    expect(restoredSavedMessagesTheme.showSavedMessagesIdentity, isTrue);

    await tester.tap(
      find.byKey(const ValueKey('chat-behavior-preserve-sender')),
    );
    await tester.pump();
    expect(theme.preserveSenderWhenRepeating, isFalse);

    await tester.tap(find.byKey(const ValueKey('chat-behavior-quick-replies')));
    await tester.pump();
    expect(theme.quickRepliesEnabled, isFalse);

    expect(
      theme.saveCapturedPhotosToAlbum,
      isFalse,
      reason: 'sending a photo does not grow the album until the user asks',
    );
    await tester.tap(
      find.byKey(const ValueKey('chat-behavior-save-captured-photos')),
    );
    await tester.pump();
    expect(theme.saveCapturedPhotosToAlbum, isTrue);
    expect(prefs.getBool('saveCapturedPhotosToAlbum'), isTrue);

    final restoredCaptureTheme = ThemeController(prefs);
    addTearDown(restoredCaptureTheme.dispose);
    expect(restoredCaptureTheme.saveCapturedPhotosToAlbum, isTrue);
  });

  testWidgets('chat behavior keeps video playback navigation', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);

    await tester.pumpWidget(_app(theme, const ChatBehaviorSettingsView()));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('chat-behavior-video-playback')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(VideoPlaybackSettingsView), findsOneWidget);
  });
}

Widget _app(ThemeController theme, Widget home) =>
    ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [AppLocalizations.delegate],
        theme: ThemeData(
          brightness: Brightness.light,
          extensions: [AppColors.light],
        ),
        home: home,
      ),
    );
