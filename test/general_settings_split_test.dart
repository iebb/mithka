import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/link_preview_fixer.dart';
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
      'linkOpenMode.v1': LinkOpenMode.defaultBrowser.name,
    });
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);
    // The row reads the shared fixer, which the app initializes at startup.
    LinkPreviewFixer.shared.initialize(prefs);
    addTearDown(() async => LinkPreviewFixer.shared.setEnabled(false));

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
      'chat-behavior-context-pane',
      'chat-behavior-saved-messages-identity',
      'chat-behavior-preserve-sender',
      'chat-behavior-forward-rich-markdown',
      'chat-behavior-fix-link-previews',
      'chat-behavior-save-captured-photos',
      'chat-behavior-quick-replies',
      'chat-behavior-link-browser',
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
      findsNWidgets(11),
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

    expect(
      theme.hideChatContextPane,
      isFalse,
      reason:
          'the group context pane stays opt-out so nothing changes for '
          'the layouts that already rely on it',
    );
    await tester.tap(find.byKey(const ValueKey('chat-behavior-context-pane')));
    await tester.pump();
    expect(theme.hideChatContextPane, isTrue);
    expect(prefs.getBool('hideChatContextPane'), isTrue);

    final restoredPaneTheme = ThemeController(prefs);
    addTearDown(restoredPaneTheme.dispose);
    expect(restoredPaneTheme.hideChatContextPane, isTrue);

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

    // One row longer than before, so the tail of the list needs a scroll
    // before its switches are hittable.
    final quickRepliesRow = find.byKey(
      const ValueKey('chat-behavior-quick-replies'),
    );
    await tester.ensureVisible(quickRepliesRow);
    await tester.pump();
    await tester.tap(quickRepliesRow);
    await tester.pump();
    expect(theme.quickRepliesEnabled, isFalse);

    // The preview fix keeps its own preference store, so the row is the only
    // thing that can flip it.
    final previewRow = find.byKey(
      const ValueKey('chat-behavior-fix-link-previews'),
    );
    await tester.ensureVisible(previewRow);
    await tester.pump();
    expect(LinkPreviewFixer.shared.enabled, isFalse);
    await tester.tap(previewRow);
    await tester.pump();
    expect(LinkPreviewFixer.shared.enabled, isTrue);
    expect(prefs.getBool(LinkPreviewFixer.preferenceKey), isTrue);

    LinkPreviewFixer.shared.initialize(prefs);
    expect(
      LinkPreviewFixer.shared.enabled,
      isTrue,
      reason: 'a later surface reads the same stored choice back',
    );

    final browserRow = find.byKey(const ValueKey('chat-behavior-link-browser'));
    await tester.ensureVisible(browserRow);
    // The jump needs a frame before the row's on-screen position is real.
    await tester.pump();
    expect(
      find.descendant(
        of: browserRow,
        matching: find.text(
          AppStrings.tForLocale('en', AppStringKeys.linkBrowserDefaultBrowser),
        ),
      ),
      findsOneWidget,
    );
    await tester.tap(browserRow);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('link-browser-mode-internalBrowser')),
    );
    await tester.pumpAndSettle();
    expect(theme.linkOpenMode, LinkOpenMode.internalBrowser);
    expect(prefs.getString('linkOpenMode.v1'), 'internalBrowser');

    final restoredLinkModeTheme = ThemeController(prefs);
    addTearDown(restoredLinkModeTheme.dispose);
    expect(restoredLinkModeTheme.linkOpenMode, LinkOpenMode.internalBrowser);

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
    final playbackRow = find.byKey(
      const ValueKey('chat-behavior-video-playback'),
    );
    await tester.ensureVisible(playbackRow);
    await tester.pump();
    await tester.tap(playbackRow);
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
