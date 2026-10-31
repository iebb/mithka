//
//  proxy_edit_view_leaf_test.dart
//
//  The add-proxy editor offers encrypted protocols only where the engine is
//  built, and shows each control only where its protocol supports it, so an
//  impossible combination (Vision over WebSocket, Shadowsocks over TLS) can
//  never be entered.
//

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/proxy_config.dart';
import 'package:mithka/settings/proxy_view.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

void main() {
  L10nFixtures.load().install();

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => ProxyConfig.debugEncryptedProxiesSupported = null);

  Future<void> pumpEditor(WidgetTester tester) async {
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
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
          theme: ThemeData(extensions: [AppColors.light]),
          home: const ProxyEditView(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> chooseType(WidgetTester tester, String type) async {
    await tester.tap(find.byKey(const ValueKey('proxy-type-selector')));
    await tester.pumpAndSettle();
    final option = find.byKey(ValueKey('proxy-type-$type'));
    await tester.ensureVisible(option);
    await tester.pumpAndSettle();
    await tester.tap(option);
    await tester.pumpAndSettle();
  }

  Finder field(String labelKey) => find.descendant(
    of: find
        .ancestor(
          of: find.text(AppStrings.t(labelKey)),
          matching: find.byType(Row),
        )
        .first,
    matching: find.byType(TextField),
  );

  testWidgets('offers only TDLib types where the engine is not built', (
    tester,
  ) async {
    ProxyConfig.debugEncryptedProxiesSupported = false;
    await pumpEditor(tester);
    await tester.tap(find.byKey(const ValueKey('proxy-type-selector')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('proxy-type-mtproto')), findsOneWidget);
    expect(find.byKey(const ValueKey('proxy-type-vless')), findsNothing);
    expect(find.byKey(const ValueKey('proxy-type-ss')), findsNothing);
  });

  testWidgets('VLESS shows Vision only over TLS without WebSocket', (
    tester,
  ) async {
    ProxyConfig.debugEncryptedProxiesSupported = true;
    await pumpEditor(tester);
    await chooseType(tester, 'vless');

    expect(find.text(AppStrings.t(AppStringKeys.proxyUuid)), findsOneWidget);
    expect(find.byKey(const ValueKey('proxy-vision')), findsNothing);
    expect(
      find.text(AppStrings.t(AppStringKeys.proxyServerName)),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('proxy-tls')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('proxy-vision')), findsOneWidget);
    expect(
      find.text(AppStrings.t(AppStringKeys.proxyServerName)),
      findsOneWidget,
    );

    await tester.ensureVisible(find.byKey(const ValueKey('proxy-websocket')));
    await tester.tap(find.byKey(const ValueKey('proxy-websocket')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('proxy-vision')), findsNothing);
    expect(
      find.text(AppStrings.t(AppStringKeys.proxyWebSocketPath)),
      findsOneWidget,
    );
  });

  testWidgets('Shadowsocks has a cipher and no transport controls', (
    tester,
  ) async {
    ProxyConfig.debugEncryptedProxiesSupported = true;
    await pumpEditor(tester);
    await chooseType(tester, 'ss');

    expect(find.byKey(const ValueKey('proxy-cipher-selector')), findsOneWidget);
    expect(find.byKey(const ValueKey('proxy-tls')), findsNothing);
    expect(find.byKey(const ValueKey('proxy-websocket')), findsNothing);
    expect(
      find.text(AppStrings.t(AppStringKeys.proxyEncryptedNote)),
      findsOneWidget,
    );
  });

  testWidgets('Trojan is always TLS and needs its password to save', (
    tester,
  ) async {
    ProxyConfig.debugEncryptedProxiesSupported = true;
    await pumpEditor(tester);
    await chooseType(tester, 'trojan');

    expect(find.byKey(const ValueKey('proxy-tls')), findsNothing);
    expect(
      find.text(AppStrings.t(AppStringKeys.proxyServerName)),
      findsOneWidget,
    );

    Color saveColor() => tester
        .widget<Text>(
          find.text(AppStrings.t(AppStringKeys.accentColorPickerSave)),
        )
        .style!
        .color!;
    final disabled = saveColor();
    await tester.enterText(field(AppStringKeys.proxyServer), 'trojan.example');
    await tester.enterText(field(AppStringKeys.proxyPort), '443');
    await tester.pump();
    expect(saveColor(), disabled);
    await tester.enterText(field(AppStringKeys.proxyPassword), 'secret');
    await tester.pump();
    expect(saveColor(), isNot(disabled));
  });
}
