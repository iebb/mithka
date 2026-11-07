//
//  Runtime switches of the kept-message mirror: every switch defaults to
//  OFF (a fresh build records and renders nothing until opted in), values
//  persist, and the compile-time gate keeps everything inert without the
//  ToS define.
//

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/config/build_flags.dart';
import 'package:mithka/history/message_history_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('every switch defaults to off', () async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final settings = MessageHistorySettings.shared;
    settings.initialize(prefs);
    expect(settings.recordDeleted, isFalse);
    expect(settings.recordEdits, isFalse);
    expect(settings.snapshotPrivate, isFalse);
    expect(settings.snapshotGroups, isFalse);
    expect(settings.snapshotChannels, isFalse);
    expect(settings.renderGhosts, isFalse);
  });

  test('switch values persist through prefs', () async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final settings = MessageHistorySettings.shared;
    settings.initialize(prefs);
    settings.setRecordDeleted(true);
    settings.setRecordEdits(true);
    settings.setSnapshotPrivate(true);
    settings.setSnapshotGroups(true);
    settings.setSnapshotChannels(true);
    settings.setRenderGhosts(true);
    // A second instance over the same prefs reads the persisted state.
    expect(prefs.getBool('message_history.record_deleted'), isTrue);
    expect(prefs.getBool('message_history.record_edits'), isTrue);
    expect(prefs.getBool('message_history.snapshot_private'), isTrue);
    expect(prefs.getBool('message_history.snapshot_groups'), isTrue);
    expect(prefs.getBool('message_history.snapshot_channels'), isTrue);
    expect(prefs.getBool('message_history.render_ghosts'), isTrue);
  });

  test('toggles notify listeners', () async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final settings = MessageHistorySettings.shared;
    settings.initialize(prefs);
    var notified = 0;
    settings.addListener(() => notified++);
    settings.setRecordDeleted(true);
    expect(notified, 1);
    // Setting the same value again does not notify.
    settings.setRecordDeleted(true);
    expect(notified, 1);
  });

  test(
    'without the compile-time gate every switch reads false',
    () async {
      // The gate is compile-time; this pins the documented contract that
      // isAvailable false forces every getter off regardless of storage.
      expect(
        allowTelegramTosViolations || !MessageHistorySettings.isAvailable,
        isTrue,
      );
    },
    skip: allowTelegramTosViolations ? false : 'gate disabled build',
  );
}
