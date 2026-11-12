//
//  Section 1.4 gate for the message-history feature: without the compile-time
//  opt-in the mirror must be a complete no-op — no TDLib subscription, no
//  file or preference reads or writes, no visible effect from stale saved
//  state — and with it on, recording must actually work.
//
//  Mirrors the build_flags_test pattern: CI runs this file once per define
//  state (false, true+EXPECT_TOS_VIOLATIONS, invalid). The `true` leg
//  additionally requires EXPECT_TOS_VIOLATIONS so the enabled assertions can
//  only run in the explicitly expected build.
//

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/config/build_flags.dart';
import 'package:mithka/history/message_history_settings.dart';
import 'package:mithka/history/message_history_store.dart';
import 'package:mithka/settings/local_premium.dart';
import 'package:shared_preferences/shared_preferences.dart';

const enabled = allowTelegramTosViolations;
const expectedEnabled = bool.fromEnvironment('EXPECT_TOS_VIOLATIONS');

void main() {
  test('build flag matches the expected variant', () {
    expect(enabled, expectedEnabled);
  });

  if (!enabled) {
    test('flag off: the runtime switches stay inert on saved state', () async {
      const saved = {
        'message_history.enable_all': true,
        'message_history.record_deleted': true,
        'message_history.render_ghosts': true,
        'local_premium.enabled': true,
      };
      SharedPreferences.setMockInitialValues(saved);
      final prefs = await SharedPreferences.getInstance();
      final settings = MessageHistorySettings.shared;
      settings.initialize(prefs);
      LocalPremium.shared.initialize(prefs);
      expect(settings.enableAll, isFalse);
      expect(settings.recordDeleted, isFalse);
      expect(settings.renderGhosts, isFalse);
      expect(LocalPremium.shared.enabled, isFalse);
      expect(LocalPremium.shared.premiumForMe(true), isTrue);
      expect(LocalPremium.shared.premiumForMe(false), isFalse);
      // Mutators refuse and leave the saved keys untouched.
      settings.setEnableAll(false);
      LocalPremium.shared.setEnabled(true);
      expect({for (final key in prefs.getKeys()) key: prefs.get(key)}, saved);
    });

    test(
      'flag off: the mirror is inert and stale saved state has no effect',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'mithka-history-gate-off',
        );
        addTearDown(() => dir.delete(recursive: true));

        SharedPreferences.setMockInitialValues(const {
          // A previous opted-in build left both a pre-existing exclusion
          // pref and a mirror file behind.
          'messageHistory.excludedChats.v1': <String>['11'],
        });
        File('${dir.path}/message-history.json').writeAsStringSync(
          '{"version":1,"entries":[{"chat":11,"id":100,"sender":42,'
          '"date":1700000000,"text":"stale","kind":"","state":"active",'
          '"deletedAt":0,"events":[]}]}',
        );

        final store = MessageHistoryStore.forTesting();
        store.fileDir = dir;
        var notified = 0;
        store.addListener(() => notified++);
        addTearDown(store.dispose);

        store.initialize(await SharedPreferences.getInstance());
        await store.ensureLoaded();
        store.startObserving();
        await store.persistNowForTesting();
        store.debugSeed([
          const MessageHistoryEntry(
            accountUserId: 42,
            chatId: 11,
            messageId: 100,
            senderId: 42,
            date: 1700000000,
            text: 'x',
            kindKey: '',
            state: MessageHistoryState.active,
            deletedAt: 0,
            events: [],
          ),
        ]);

        expect(store.entries, isEmpty);
        expect(store.entryCount, 0);
        expect(store.isChatExcluded(11), isFalse);
        expect(store.excludedChats, isEmpty);
        expect(notified, 0);
        expect(
          File('${dir.path}/message-history.json').readAsStringSync(),
          contains('"stale"'),
          reason: 'an inert store must not rewrite the mirror file',
        );
        expect(
          File('${dir.path}/message-history.json.tmp').existsSync(),
          isFalse,
          reason: 'an inert store must not stage writes',
        );
      },
    );
  } else {
    test('flag on: recording works end to end', () async {
      final dir = await Directory.systemTemp.createTemp(
        'mithka-history-gate-on',
      );
      addTearDown(() => dir.delete(recursive: true));

      final controller = StreamController<Map<String, dynamic>>.broadcast();
      addTearDown(controller.close);

      SharedPreferences.setMockInitialValues(const {});
      final store = MessageHistoryStore.forTesting();
      store.fileDir = dir;
      store.updateSource = (_) => controller.stream;
      store.activeSlotChangeSource = () => const Stream<int>.empty();
      // Real updates are stamped with the client that observed them; the
      // gate pins the single-account case where that client is the account.
      store.accountUserIdResolver = _SingleAccountIdentity();
      store.activeClientIdProvider = () => 101;
      addTearDown(store.dispose);
      // The runtime switches ship OFF; the end-to-end leg opts in first,
      // the way a user of a self-build would.
      final settings = MessageHistorySettings.shared;
      settings.setEnableAll(true);
      settings.setRecordDeleted(true);
      addTearDown(() {
        settings.setEnableAll(false);
        settings.setRecordDeleted(false);
      });
      store.initialize(await SharedPreferences.getInstance());
      await store.ensureLoaded();
      store.startObserving();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      controller.add({
        '@type': 'updateNewMessage',
        '@client_id': 101,
        'message': {
          '@type': 'message',
          'chat_id': '11',
          'id': 100,
          'date': 1700000000,
          'sender_id': {'@type': 'messageSenderUser', 'user_id': '42'},
          'content': {
            '@type': 'messageText',
            'text': {'@type': 'formattedText', 'text': 'kept'},
          },
        },
      });
      await Future<void>.delayed(Duration.zero);
      await store.persistNowForTesting();

      expect(store.entryCount, 1);
      expect(store.entry(11, 100)!.text, 'kept');
      expect(
        File('${dir.path}/message-history.json').readAsStringSync(),
        contains('"kept"'),
      );
    });
  }
}

/// Maps every TDLib client to the one test account; the gate pins the
/// single-account path end to end.
class _SingleAccountIdentity implements TosAccountUserIdResolver {
  @override
  Future<int?> resolve(int clientId) async => 42;
}
