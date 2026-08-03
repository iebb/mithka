import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/moments/moments_view.dart';
import 'package:mithka/moments/short_video_availability.dart';
import 'package:mithka/settings/feature_settings_view.dart';
import 'package:mithka/settings/safety_notice_controller.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('short videos stay off native desktop Moments surfaces', () {
    for (final platform in [
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      expect(
        shortVideosAvailableOnPlatform(platform: platform, isWeb: false),
        isFalse,
      );
    }

    expect(
      shortVideosAvailableOnPlatform(
        platform: TargetPlatform.iOS,
        isWeb: false,
      ),
      isTrue,
    );
    expect(
      shortVideosAvailableOnPlatform(
        platform: TargetPlatform.macOS,
        isWeb: true,
      ),
      isTrue,
    );
  });

  testWidgets('desktop Moments uses a centered 760 point timeline lane', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<Rect> pumpFor(TargetPlatform platform) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(platform),
          theme: ThemeData(extensions: [AppColors.light]),
          home: const MomentsDesktopFeedLane(
            child: ColoredBox(
              key: ValueKey('moments-timeline-content'),
              color: Colors.blue,
            ),
          ),
        ),
      );
      return tester.getRect(
        find.byKey(const ValueKey('moments-timeline-content')),
      );
    }

    final desktopRect = await pumpFor(TargetPlatform.macOS);
    expect(desktopRect.width, desktopMomentsFeedMaxWidth);
    expect(desktopRect.left, 260);
    expect(
      find.byKey(const ValueKey('desktop-moments-feed-lane')),
      findsOneWidget,
    );

    final mobileRect = await pumpFor(TargetPlatform.iOS);
    expect(mobileRect.width, 1280);
    expect(mobileRect.left, 0);
    expect(
      find.byKey(const ValueKey('desktop-moments-feed-lane')),
      findsNothing,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop feature settings removes the short-video switch', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    final safety = SafetyNoticeController(prefs);
    addTearDown(theme.dispose);
    addTearDown(safety.dispose);

    Future<void> pumpFor(TargetPlatform platform) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(
        MultiProvider(
          key: ValueKey(platform),
          providers: [
            ChangeNotifierProvider<ThemeController>.value(value: theme),
            ChangeNotifierProvider<SafetyNoticeController>.value(value: safety),
          ],
          child: const MaterialApp(
            locale: Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: FeatureSettingsView(),
          ),
        ),
      );
    }

    await pumpFor(TargetPlatform.macOS);
    expect(find.text('Short videos'), findsNothing);

    await pumpFor(TargetPlatform.iOS);
    expect(find.text('Short videos'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
