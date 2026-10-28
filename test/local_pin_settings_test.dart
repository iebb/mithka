//
//  The device-only pin switch in Advanced settings: the row shows the server's
//  pin cap in its explanatory line, and toggling it persists the preference and
//  flips the store's state. The inertness half of the contract lives in
//  local_pins_test.dart.
//

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/local_pin_store.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/advanced_settings_view.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async => switch (request['@type']) {
          'getOption' => <String, dynamic>{
            '@type': 'optionValueInteger',
            'value': 5,
          },
          _ => <String, dynamic>{'@type': 'ok'},
        },
        send: (_) async {},
        updates: const Stream<Map<String, dynamic>>.empty(),
      ),
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDownAll(() async {
    await LocalPinStore.shared.setUnlimitedEnabled(false);
    LocalPinStore.shared.setActiveAccountUserId(null);
    await TdClient.shared.closeProxy();
  });

  testWidgets('the advanced settings switch drives the device-only pins', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    LocalPinStore.shared.initialize(prefs);
    // A store left in an earlier test's state must not leak in; the switch
    // starts from the pristine (off) state.
    expect(LocalPinStore.shared.unlimitedEnabled, isFalse);

    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);
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
          home: AdvancedSettingsView(),
        ),
      ),
    );
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('local-pins-unlimited'));
    await tester.scrollUntilVisible(row, 200);
    expect(row, findsOneWidget);
    // The explanatory line names the server's cap (answered as 5 above).
    expect(
      find.textContaining('keep more than 5 pinned chats'),
      findsOneWidget,
    );

    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(LocalPinStore.shared.unlimitedEnabled, isTrue);
    expect(prefs.getBool(LocalPinStore.unlimitedPreferenceKey), isTrue);

    // And back off again.
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(LocalPinStore.shared.unlimitedEnabled, isFalse);
    expect(prefs.getBool(LocalPinStore.unlimitedPreferenceKey), isNull);
  });
}
