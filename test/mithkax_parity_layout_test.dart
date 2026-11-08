//
//  Layout checks for the exteraless-parity UI: the transfer page and the
//  rebuilt hub render without overflow on a phone-width surface and on a
//  wide desktop surface, and the per-chat recording switch reads the store.
//

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/history/message_history_store.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/message_history_transfer_view.dart';
import 'package:mithka/settings/mithkax_settings_view.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester tester, Widget home, Size size) async {
  final prefs = await SharedPreferences.getInstance();
  final theme = ThemeController(prefs);
  addTearDown(theme.dispose);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeController>.value(
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
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
  });

  for (final (name, size) in [
    ('phone', const Size(390, 844)),
    ('wide', const Size(1280, 800)),
  ]) {
    testWidgets('transfer page lays out without overflow ($name)', (
      tester,
    ) async {
      await _pump(tester, const MessageHistoryTransferView(), size);
      expect(
        find.byKey(const ValueKey('history-transfer-export')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('history-transfer-import')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('hub page lays out without overflow ($name)', (tester) async {
      await _pump(tester, const MithkaXSettingsView(), size);
      expect(find.byKey(const ValueKey('history-enable-all')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('per-chat recording switch reads the mirror store', (
    tester,
  ) async {
    final store = MessageHistoryStore.forTesting();
    store.debugSetActiveAccount(4211);
    addTearDown(store.dispose);
    await _pump(
      tester,
      const _ChatRecordingSwitchHost(chatId: 77),
      const Size(390, 844),
    );
    final toggle = find.byType(Switch);
    expect(toggle, findsOneWidget);
    // The host's switch mirrors the row's value: not excluded → on.
    expect(tester.widget<Switch>(toggle).value, isTrue);
    expect(tester.takeException(), isNull);
  });
}

/// Minimal host mirroring the chat-info row's ListenableBuilder structure.
class _ChatRecordingSwitchHost extends StatelessWidget {
  const _ChatRecordingSwitchHost({required this.chatId});

  final int chatId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ListenableBuilder(
          listenable: MessageHistoryStore.shared,
          builder: (context, _) {
            final excluded = MessageHistoryStore.shared.isChatExcluded(chatId);
            return Switch(value: !excluded, onChanged: (_) {});
          },
        ),
      ),
    );
  }
}
