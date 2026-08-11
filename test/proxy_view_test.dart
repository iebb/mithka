import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/proxy_view.dart';
import 'package:mithka/theme/app_motion.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('desktop proxy type uses an anchored in-place selector', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: theme,
        child: _shell(const ProxyEditView(allowOfflineSave: true)),
      ),
    );
    await tester.pumpAndSettle();

    final selector = find.byKey(const ValueKey('proxy-type-selector'));
    final selectorRect = tester.getRect(selector);
    expect(find.byType(TabBar), findsNothing);

    await tester.tap(selector);
    await tester.pumpAndSettle();

    final menu = find.byKey(const ValueKey('proxy-type-menu'));
    expect(menu, findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byKey(appCenteredModalFrameKey), findsNothing);
    final menuRect = tester.getRect(menu);
    expect(menuRect.top, greaterThanOrEqualTo(selectorRect.bottom));
    expect(menuRect.right, closeTo(selectorRect.right, 0.01));

    await tester.tap(find.byKey(const ValueKey('proxy-type-http')));
    await tester.pumpAndSettle();
    expect(find.text('HTTP'), findsOneWidget);
    expect(menu, findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}

Widget _shell(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData(
    platform: TargetPlatform.macOS,
    extensions: [AppColors.light],
  ),
  home: child,
);
