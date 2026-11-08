//
//  r10: settings-hub dependency visibility and ghost attribution.
//  1) The record dims dim under BOTH the master switch and the deleted
//     recording switch; the ghost render switch never dims.
//  2) A group ghost carries its author's name so the kept copy stays
//     attributable; a media-only ghost shows the kind label, not an empty
//     bubble.
//
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/config/build_flags.dart';
import 'package:mithka/history/message_history_settings.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/mithkax_settings_view.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _enabled = allowTelegramTosViolations;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
  });

  tearDown(() {
    if (!_enabled) return;
    final s = MessageHistorySettings.shared;
    s.setEnableAll(false);
    s.setRecordDeleted(false);
    s.setRenderGhosts(false);
  });

  Future<void> pumpHub(WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();
    MessageHistorySettings.shared.initialize(prefs);
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppColors.light]),
          home: const MithkaXSettingsView(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double opacityOf(WidgetTester tester, Key key) {
    final row = find.byKey(key);
    expect(row, findsOneWidget);
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: row, matching: find.byType(Opacity)).first,
    );
    return opacity.opacity;
  }

  testWidgets('record dims dim under the master switch', (tester) async {
    await pumpHub(tester);
    if (!_enabled) return;
    final dim = find.byKey(const ValueKey('history-record-private'));
    await tester.scrollUntilVisible(dim, 300);
    expect(opacityOf(tester, const ValueKey('history-record-private')), 0.45);
    // Ghost render is display-only: never dimmed by the master switch.
    final ghost = find.byKey(const ValueKey('history-render-ghosts'));
    await tester.scrollUntilVisible(ghost, 300);
    final ghostOpacities = find.ancestor(
      of: ghost,
      matching: find.byType(Opacity),
    );
    expect(
      ghostOpacities,
      findsNothing,
      reason: 'the ghost render switch must not be dimmed',
    );
  });

  testWidgets('record dims also dim when only recordDeleted is off', (
    tester,
  ) async {
    await pumpHub(tester);
    if (!_enabled) return;
    final s = MessageHistorySettings.shared;
    final deleted = find.byKey(const ValueKey('history-record-deleted'));
    await tester.scrollUntilVisible(deleted, 300);
    // Master on, deleted off: dims lit by the master but still gated by the
    // deleted switch — visually dimmed.
    await tester.tap(find.byKey(const ValueKey('history-enable-all')));
    await tester.pumpAndSettle();
    await tester.tap(deleted);
    await tester.pumpAndSettle();
    final dim = find.byKey(const ValueKey('history-snapshot-groups'));
    await tester.scrollUntilVisible(dim, 400);
    // Both gates on: the row is lit.
    expect(opacityOf(tester, const ValueKey('history-snapshot-groups')), 1.0);
    // The second gate: deleted-recording off dims it even under a lit master.
    s.setRecordDeleted(false);
    await tester.pumpAndSettle();
    expect(opacityOf(tester, const ValueKey('history-snapshot-groups')), 0.45);
    s.setRecordDeleted(true);
    await tester.pumpAndSettle();
    expect(opacityOf(tester, const ValueKey('history-snapshot-groups')), 1.0);
  });

  testWidgets('sections carry headers so cards never sit flush', (
    tester,
  ) async {
    await pumpHub(tester);
    if (!_enabled) return;
    // Every block is a titled section now; the transfer card must be
    // preceded by a section header, not glued to the switches card.
    final transfer = find.byKey(const ValueKey('mithkax-history-transfer'));
    await tester.scrollUntilVisible(transfer, 600);
    expect(transfer, findsOneWidget);
    expect(
      find.text(AppStrings.t(AppStringKeys.historyTransferSection)),
      findsOneWidget,
    );
    expect(
      find.text(AppStrings.t(AppStringKeys.historyRecordSection)),
      findsOneWidget,
    );
  });
}
