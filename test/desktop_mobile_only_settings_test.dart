import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/notifications/notification_preferences.dart';
import 'package:mithka/settings/auto_download_media_controller.dart';
import 'package:mithka/settings/auto_download_settings_view.dart';
import 'package:mithka/settings/general_settings_view.dart';
import 'package:mithka/settings/notification_settings_view.dart';
import 'package:mithka/settings/video_playback_settings_view.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ThemeController theme;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    AutoDownloadMediaController.shared.initialize(preferences);
    NotificationPreferences.shared.initialize(preferences);
    theme = ThemeController(preferences);
  });

  tearDown(() => theme.dispose());

  testWidgets('native desktop keeps Wi-Fi but hides cellular download modes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const GeneralSettingsView(),
        platform: TargetPlatform.macOS,
        theme: theme,
        autoDownloadProvider: true,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('general-auto-download-mobile')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('general-auto-download-wifi')),
      findsOneWidget,
    );

    await tester.pumpWidget(
      _app(
        const AutoDownloadSettingsView(),
        platform: TargetPlatform.macOS,
        theme: theme,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('auto-download-network-selector')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('auto-download-profile-networkTypeWiFi')),
      findsOneWidget,
    );
  });

  testWidgets('native desktop hides vibration and video swipe controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const NotificationSettingsView(),
        platform: TargetPlatform.macOS,
        theme: theme,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('mithka-notification-in-app-vibrate')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('mithka-notification-in-app-sounds')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mithka-notification-in-app-preview')),
      findsOneWidget,
    );

    await tester.pumpWidget(
      _app(
        const VideoPlaybackSettingsView(),
        platform: TargetPlatform.macOS,
        theme: theme,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('video-playback-horizontal-swipe-section')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('video-playback-left-vertical-swipe-section')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('video-playback-right-vertical-swipe-section')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('video-playback-completion-section')),
      findsOneWidget,
    );

    await tester.pumpWidget(
      _app(
        const ChatBehaviorSettingsView(),
        platform: TargetPlatform.macOS,
        theme: theme,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('chat-behavior-save-captured-photos')),
      findsNothing,
      reason: 'a desktop composer has no camera button to save a capture from',
    );
  });

  testWidgets('touch platforms retain mobile download and gesture controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const AutoDownloadSettingsView(),
        platform: TargetPlatform.android,
        theme: theme,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('auto-download-network-selector')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('auto-download-network-networkTypeMobileRoaming'),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(
      _app(
        const VideoPlaybackSettingsView(),
        platform: TargetPlatform.android,
        theme: theme,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('video-playback-horizontal-swipe-section')),
      findsOneWidget,
    );

    await tester.pumpWidget(
      _app(
        const ChatBehaviorSettingsView(),
        platform: TargetPlatform.android,
        theme: theme,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('chat-behavior-save-captured-photos')),
      findsOneWidget,
    );
  });
}

Widget _app(
  Widget home, {
  required TargetPlatform platform,
  required ThemeController theme,
  bool autoDownloadProvider = false,
}) {
  final app = MaterialApp(
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: ThemeData(platform: platform, extensions: [AppColors.light]),
    home: home,
  );
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeController>.value(value: theme),
      if (autoDownloadProvider)
        ChangeNotifierProvider<AutoDownloadMediaController>.value(
          value: AutoDownloadMediaController.shared,
        ),
    ],
    child: app,
  );
}
