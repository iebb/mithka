import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/notifications/notification_preferences.dart';
import 'package:mithka/settings/notification_settings_view.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'notification settings merges Telegram and usable on-device controls',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final notificationPreferences = NotificationPreferences.shared;
      notificationPreferences.initialize(preferences);
      final theme = ThemeController(preferences);
      addTearDown(theme.dispose);

      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: const MaterialApp(
            locale: Locale('en'),
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: NotificationSettingsView(),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('notification-settings')),
        findsOneWidget,
      );
      expect(find.byType(ListView), findsOneWidget);
      final telegramSection = find.byKey(
        const ValueKey('notification-section-telegram'),
      );
      final deviceSection = find.byKey(
        const ValueKey('notification-section-device'),
      );
      expect(telegramSection, findsOneWidget);
      expect(deviceSection, findsOneWidget);
      expect(
        tester.getTopLeft(telegramSection).dy,
        lessThan(tester.getTopLeft(deviceSection).dy),
      );
      expect(find.text('MESSAGE NOTIFICATIONS'), findsOneWidget);
      expect(find.text('NOTIFICATIONS ON THIS DEVICE'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('notification-telegram-loading')),
        findsOneWidget,
      );
      expect(find.text('IN-APP NOTIFICATIONS'), findsNothing);
      expect(find.text('In-App Sounds'), findsOneWidget);
      expect(find.text('In-App Vibrate'), findsOneWidget);
      expect(find.text('In-App Preview'), findsOneWidget);
      expect(find.text('Names on Lock Screen'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('mithka-notification-in-app-sounds')),
      );
      await tester.pump();

      expect(notificationPreferences.inAppSounds, isFalse);
      expect(
        preferences.getBool('mithka.notifications.inAppSounds.v1'),
        isFalse,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
