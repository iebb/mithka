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
    'Mithka notification settings contains only on-device preferences',
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
            home: MithkaNotificationSettingsView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('mithka-notification-settings')),
        findsOneWidget,
      );
      expect(find.text('IN-APP NOTIFICATIONS'), findsOneWidget);
      expect(find.text('In-App Sounds'), findsOneWidget);
      expect(find.text('In-App Vibrate'), findsOneWidget);
      expect(find.text('In-App Preview'), findsOneWidget);
      expect(find.text('Names on Lock Screen'), findsOneWidget);

      expect(find.text('Private Chats'), findsNothing);
      expect(find.text('Group Chats'), findsNothing);
      expect(find.text('Channels'), findsNothing);
      expect(find.text('Stories'), findsNothing);
      expect(find.text('Reactions'), findsNothing);

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
