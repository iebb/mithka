import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/privacy_security_view.dart';
import 'package:mithka/settings/sensitive_content_controller.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'localizes security actions and keeps account deletion in danger zone',
    (tester) async {
      final previousLocale = Intl.defaultLocale;
      Intl.defaultLocale = 'zh_Hans';
      addTearDown(() => Intl.defaultLocale = previousLocale);
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final theme = ThemeController(preferences);
      addTearDown(theme.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeController>.value(value: theme),
            ChangeNotifierProvider<SensitiveContentController>.value(
              value: SensitiveContentController.shared,
            ),
          ],
          child: const MaterialApp(
            locale: Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: PrivacySecurityView(),
          ),
        ),
      );

      expect(find.text('Change Phone Number'), findsNothing);
      expect(find.text('Delete Account If Away For'), findsNothing);
      expect(find.text('更换手机号码'), findsOneWidget);
      expect(find.text('危险区域'), findsOneWidget);
      expect(find.text('侧边栏隐藏手机号'), findsNothing);
      expect(find.text('解锁设置'), findsNothing);
      expect(find.text('账号备份'), findsNothing);

      final dangerZone = find.byKey(const ValueKey('privacy-danger-zone'));
      expect(dangerZone, findsOneWidget);
      expect(
        find.descendant(of: dangerZone, matching: find.text('离开多久后删除账号')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dangerZone, matching: find.text('删除 Telegram 账号')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dangerZone, matching: find.text('自动删除消息')),
        findsNothing,
      );
      expect(find.text('自动删除消息'), findsOneWidget);

      final dangerTitle = tester.widget<Text>(find.text('危险区域'));
      final deleteAccount = tester.widget<Text>(find.text('删除 Telegram 账号'));
      expect(dangerTitle.style?.color, AppTheme.tagRed);
      expect(deleteAccount.style?.color, AppTheme.tagRed);
      expect(find.byType(SettingsCard), findsNWidgets(3));
      expect(find.byType(SettingsRow), findsWidgets);
      expect(find.byType(SettingsLeadingIcon), findsWidgets);
      expect(find.byType(SettingsPanel), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
