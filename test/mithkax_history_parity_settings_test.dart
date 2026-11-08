//
//  Mithka X exteraless-parity settings tests: the master switch gates the
//  record switches without wiping them, per-type defaults behave, and the
//  badge style persists.
//

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/history/message_history_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
    prefs = await SharedPreferences.getInstance();
    MessageHistorySettings.shared.initialize(prefs);
  });

  tearDown(() {
    final s = MessageHistorySettings.shared;
    s.setEnableAll(false);
    s.setRecordDeleted(false);
    s.setRecordEdits(false);
    s.setRecordReadTimes(false);
    s.setRecordPrivate(true);
    s.setRecordGroups(true);
    s.setRecordChannels(true);
    s.setRecordBots(false);
    s.setBadgeStyle(GhostBadgeStyle.icon);
  });

  test('everything is off by default (fresh install records nothing)', () {
    final s = MessageHistorySettings.shared;
    expect(s.enableAll, isFalse);
    expect(s.recordDeleted, isFalse);
    expect(s.recordEdits, isFalse);
    expect(s.recordReadTimes, isFalse);
    // Type dims default on but sit under the master switch.
    expect(s.recordPrivate, isFalse);
    expect(s.recordGroups, isFalse);
    expect(s.recordChannels, isFalse);
    expect(s.recordBots, isFalse);
    expect(s.renderGhosts, isFalse);
  });

  test('the master switch pauses recording but keeps sub-switch choices', () {
    final s = MessageHistorySettings.shared;
    s.setEnableAll(true);
    s.setRecordDeleted(true);
    s.setRecordPrivate(false);
    expect(s.recordDeleted, isTrue);
    expect(s.recordPrivate, isFalse);
    expect(s.recordGroups, isTrue); // per-type default on

    // Master off: every record getter goes dark…
    s.setEnableAll(false);
    expect(s.recordDeleted, isFalse);
    expect(s.recordGroups, isFalse);

    // …but the choices survive and come back with the master switch.
    s.setEnableAll(true);
    expect(s.recordDeleted, isTrue);
    expect(s.recordPrivate, isFalse);
    expect(s.recordGroups, isTrue);
  });

  test('bot recording needs both the private dim and its own switch', () {
    final s = MessageHistorySettings.shared;
    s.setEnableAll(true);
    s.setRecordDeleted(true);
    s.setRecordBots(true);
    expect(s.recordBots, isTrue);

    // Private dim off kills bot recording too — a bot dialog is private.
    s.setRecordPrivate(false);
    expect(s.recordBots, isFalse);
  });

  test('ghost rendering ignores the master switch (display-only)', () {
    final s = MessageHistorySettings.shared;
    s.setRenderGhosts(true);
    expect(s.renderGhosts, isTrue);
    s.setEnableAll(true);
    s.setEnableAll(false);
    expect(
      s.renderGhosts,
      isTrue,
      reason: 'turning recording off must not hide kept ghosts',
    );
  });

  test('badge style persists and reloads', () async {
    final s = MessageHistorySettings.shared;
    expect(s.badgeStyle, GhostBadgeStyle.icon);
    s.setBadgeStyle(GhostBadgeStyle.text);
    expect(s.badgeStyle, GhostBadgeStyle.text);

    final reloaded = MessageHistorySettings.shared;
    // shared keeps its state; verifying persistence through the prefs value
    // the setter wrote instead.
    expect(prefs.getString('message_history.badge_style'), 'text');
    expect(reloaded.badgeStyle, GhostBadgeStyle.text);
  });
}
