//
//  Experimental settings hub: the feature switches answer taps immediately
//  (rows rebuild from the store's own notifications) and the local premium
//  knob flips without any outside setState. Regression: the original rows in
//  Advanced/Privacy were stateless and looked dead until an unrelated row
//  triggered a page rebuild.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/config/build_flags.dart';
import 'package:mithka/history/message_history_settings.dart';
import 'package:mithka/history/message_history_store.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/ghost_mode_controller.dart';
import 'package:mithka/settings/ghost_mode_settings_view.dart';
import 'package:mithka/settings/kept_messages_settings_view.dart';
import 'package:mithka/settings/local_premium.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _enabled = allowTelegramTosViolations;

Future<void> _pump(WidgetTester tester, Widget home) async {
  final prefs = await SharedPreferences.getInstance();
  final theme = ThemeController(prefs);
  addTearDown(theme.dispose);
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
        home: home,
      ),
    ),
  );
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpAndSettle();
}

Future<void> pumpHub(WidgetTester tester) =>
    _pump(tester, const KeptMessagesSettingsView());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    MessageHistorySettings.shared.initialize(prefs);
    LocalPremium.shared.initialize(prefs);
    GhostModeController.shared.initialize(prefs);
  });

  testWidgets('history switches flip on tap', (tester) async {
    await _pump(tester, const KeptMessagesSettingsView());
    if (!_enabled) {
      // The hub shrinks to nothing in non-opted builds: no row exists.
      expect(
        find.byKey(const ValueKey('history-record-deleted')),
        findsNothing,
      );
      return;
    }
    {
      // The master switch gates every record switch now.
      final master = find.byKey(const ValueKey('history-enable-all'));
      await tester.scrollUntilVisible(master, 200);
      await tester.tap(master);
      await tester.pumpAndSettle();
    }
    final row = find.byKey(const ValueKey('history-record-deleted'));
    await tester.scrollUntilVisible(row, 200);
    expect(row, findsOneWidget);

    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(MessageHistorySettings.shared.recordDeleted, isTrue);

    // The row's knob reflects the new value with no outside rebuild: the
    // rebuilt AppSwitch aligns its handle right when on.
    {
      final handle = find.descendant(
        of: row,
        matching: find.byType(AnimatedAlign),
      );
      expect(handle, findsOneWidget);
      expect(
        tester.widget<AnimatedAlign>(handle).alignment,
        Alignment.centerRight,
      );
    }
    MessageHistorySettings.shared.setEnableAll(false);
    MessageHistorySettings.shared.setRecordDeleted(false);
  });

  testWidgets('local premium knob answers its own tap', (tester) async {
    await _pump(tester, const KeptMessagesSettingsView());
    if (!_enabled) {
      expect(find.byKey(const ValueKey('kept-local-premium')), findsNothing);
      return;
    }
    final row = find.byKey(const ValueKey('kept-local-premium'));
    await tester.scrollUntilVisible(row, 200);
    expect(row, findsOneWidget);

    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(LocalPremium.shared.enabled, isTrue);
  });

  testWidgets('master switch gates the sub-switches visually', (tester) async {
    await _pump(tester, const KeptMessagesSettingsView());
    if (!_enabled) {
      expect(find.byKey(const ValueKey('history-enable-all')), findsNothing);
      return;
    }
    final master = find.byKey(const ValueKey('history-enable-all'));
    await tester.scrollUntilVisible(master, 200);
    expect(master, findsOneWidget);

    // Sub-switches are dimmed while the master is off.
    final sub = find.byKey(const ValueKey('history-record-deleted'));
    await tester.scrollUntilVisible(sub, 200);
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: sub, matching: find.byType(Opacity)).first,
    );
    expect(opacity.opacity, 0.45);

    await tester.tap(master);
    await tester.pumpAndSettle();
    final opacityAfter = tester.widget<Opacity>(
      find.ancestor(of: sub, matching: find.byType(Opacity)).first,
    );
    expect(opacityAfter.opacity, 1.0);
    MessageHistorySettings.shared.setEnableAll(false);
  });

  testWidgets('the transfer entry and badge style row exist', (tester) async {
    await _pump(tester, const KeptMessagesSettingsView());
    if (!_enabled) {
      expect(find.byKey(const ValueKey('kept-history-transfer')), findsNothing);
      return;
    }
    final transfer = find.byKey(const ValueKey('kept-history-transfer'));
    await tester.scrollUntilVisible(transfer, 300);
    expect(transfer, findsOneWidget);
    final badge = find.byKey(const ValueKey('kept-badge-style'));
    await tester.scrollUntilVisible(badge, 300);
    expect(badge, findsOneWidget);
  });

  testWidgets('clear database wipes the kept mirror behind a confirm', (
    tester,
  ) async {
    await _pump(tester, const KeptMessagesSettingsView());
    if (!_enabled) {
      expect(find.byKey(const ValueKey('kept-clear-database')), findsNothing);
      return;
    }
    final store = MessageHistoryStore.shared;
    store.debugSetActiveAccount(42);
    store.debugSeed(const [
      MessageHistoryEntry(
        accountUserId: 42,
        chatId: 7,
        messageId: 1,
        senderId: 7,
        date: 1700000000,
        text: 'kept copy',
        kindKey: '',
        state: MessageHistoryState.deleted,
        deletedAt: 1700000001,
        events: [],
      ),
    ]);
    expect(store.entries, isNotEmpty);

    final row = find.byKey(const ValueKey('kept-clear-database'));
    await tester.scrollUntilVisible(row, 300);
    // The size value comes from real file I/O behind path_provider, whose
    // first platform answer only lands on the real event loop inside the
    // test's fake clock. One real turn settles the row's own scan.
    await tester.runAsync(MessageHistoryStore.shared.databaseBytes);
    await tester.pumpAndSettle();
    expect(row, findsOneWidget);
    // The row carries the database's on-disk size, like the reference client's row.
    expect(
      find.descendant(of: row, matching: find.textContaining(' B')),
      findsOneWidget,
    );

    // Cancelling the confirm keeps the mirror untouched.
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('app-confirm-cancel')));
    await tester.pumpAndSettle();
    expect(store.entries, isNotEmpty);

    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('app-confirm-accept')));
    await tester.pumpAndSettle();
    expect(store.entries, isEmpty);
    expect(find.text('Message database cleared'), findsOneWidget);

    // Flush the toast's hold/fade and the debounced persist inside the test's
    // fake clock, or the run ends with timers still pending.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('badge style picker updates the settings store', (tester) async {
    await _pump(tester, const KeptMessagesSettingsView());
    if (!_enabled) {
      expect(find.byKey(const ValueKey('kept-badge-style')), findsNothing);
      return;
    }
    final badge = find.byKey(const ValueKey('kept-badge-style'));
    await tester.scrollUntilVisible(badge, 300);
    await tester.tap(badge);
    await tester.pumpAndSettle();
    final option = find.byKey(const ValueKey('kept-badge-style-text'));
    await tester.tap(option);
    await tester.pumpAndSettle();
    expect(MessageHistorySettings.shared.badgeStyle, GhostBadgeStyle.text);
    MessageHistorySettings.shared.setBadgeStyle(GhostBadgeStyle.icon);
  });

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

  testWidgets('dimmed rows refuse taps (media snapshots)', (tester) async {
    // The dim was opacity-only once: a dimmed row still answered taps and
    // flipped its setting. The gate now also disables the row.
    await pumpHub(tester);
    if (!_enabled) return;
    final s = MessageHistorySettings.shared;
    s.setEnableAll(false);
    await tester.pumpAndSettle();
    final dim = find.byKey(const ValueKey('history-snapshot-private'));
    await tester.scrollUntilVisible(dim, 400);
    final row = tester.widget<SettingsSwitchRow>(dim);
    expect(row.enabled, isFalse, reason: 'a dimmed row must be disabled');
    expect(s.snapshotPrivate, isFalse, reason: 'snapshot dims default to off');

    await tester.tap(dim, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
      s.snapshotPrivate,
      isFalse,
      reason: 'tapping a dimmed row must not change its setting',
    );

    // Lit again under both gates: taps flip it.
    s.setEnableAll(true);
    s.setRecordDeleted(true);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(dim, 400);
    final rowAfter = tester.widget<SettingsSwitchRow>(dim);
    expect(
      rowAfter.enabled,
      isTrue,
      reason: 'the row lights up with its gates',
    );
    await tester.tap(dim);
    await tester.pumpAndSettle();
    expect(s.snapshotPrivate, isTrue);
    s.setSnapshotPrivate(false);
    s.setEnableAll(false);
    s.setRecordDeleted(false);
  });

  testWidgets('sections carry headers so cards never sit flush', (
    tester,
  ) async {
    await pumpHub(tester);
    if (!_enabled) return;
    // Every block is a titled section now; the transfer card must be
    // preceded by a section header, not glued to the switches card.
    final transfer = find.byKey(const ValueKey('kept-history-transfer'));
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

  group('ghost mode settings', () {
    Future<void> pumpGhost(WidgetTester tester) =>
        _pump(tester, const GhostModeSettingsView());

    testWidgets('gated switches refuse taps while the master is off', (
      tester,
    ) async {
      await pumpGhost(tester);
      if (!_enabled) return;
      final controller = GhostModeController.shared;
      await controller.setGlobalEnabled(false);
      await tester.pumpAndSettle();

      // All four dimensions are disabled with the master off: tapping one
      // must not flip its stored value.
      final receipts = find.text(
        AppStrings.t(AppStringKeys.ghostModeReadReceipts),
      );
      await tester.scrollUntilVisible(receipts, 200);
      final row = find.ancestor(
        of: receipts,
        matching: find.byType(SettingsSwitchRow),
      );
      expect(tester.widget<SettingsSwitchRow>(row).enabled, isFalse);
      await tester.tap(receipts);
      await tester.pumpAndSettle();
      expect(
        controller.blockReadReceipts,
        isTrue,
        reason: 'a dimmed row must not change its setting',
      );

      // Turning the master on lights the rows and taps work again.
      final master = find.byKey(const ValueKey('ghost-mode-master'));
      await tester.tap(master);
      await tester.pumpAndSettle();
      await tester.tap(receipts);
      await tester.pumpAndSettle();
      expect(controller.blockReadReceipts, isFalse);
      await controller.setGlobalEnabled(false);
      await controller.setBlockReadReceipts(true);
    });

    testWidgets('the sidebar entry switch flips and persists', (tester) async {
      await pumpGhost(tester);
      if (!_enabled) return;
      final controller = GhostModeController.shared;
      expect(
        controller.showSidebarEntry,
        isTrue,
        reason: 'the sidebar entry defaults to on',
      );

      final entry = find.byKey(const ValueKey('ghost-mode-sidebar-entry'));
      await tester.scrollUntilVisible(entry, 200);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(controller.showSidebarEntry, isFalse);

      // The preference survives re-initialization (a restart).
      final prefs = await SharedPreferences.getInstance();
      GhostModeController.shared.initialize(prefs);
      await tester.pumpAndSettle();
      expect(GhostModeController.shared.showSidebarEntry, isFalse);
      unawaited(GhostModeController.shared.setShowSidebarEntry(true));
    });
  });
}
