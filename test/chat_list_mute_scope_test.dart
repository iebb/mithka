// Regression tests for the cold-start mute race: a chat that follows its
// scope's default mute settings was computed as unmuted when the chat list
// hydrated before the scope cache filled, and nothing corrected it afterwards
// (TDLib does not resend updateChatNotificationSettings for chats whose own
// settings did not change).
//
// Root cause chain (all TDLib facts verified against upstream td sources):
//  * A default-following chat carries no mute state of its own —
//    `DialogNotificationSettings::fix_mute_until` zeroes its mute_until, so
//    getChat answers `use_default_mute_for=true, mute_for=0`.
//  * The effective value lives in the scope settings, which on a cold start
//    answer from a server round trip (GetScopeNotificationSettingsRequest
//    waits for sync), so chat-list hydration can land first.
//  * mithka froze `isMuted` at parse time from a possibly-empty cache with no
//    invalidation, so the wrong state survived the whole session.
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view_model.dart';
import 'package:mithka/notifications/scope_notification_settings.dart';
import 'package:mithka/tdlib/td_models.dart';

const _privateScope = 'notificationSettingsScopePrivateChats';

Map<String, dynamic> _chat({
  int id = 42,
  bool useDefaultMuteFor = true,
  int muteFor = 0,
}) => {
  '@type': 'chat',
  'id': id,
  'title': 'Chat $id',
  'type': {'@type': 'chatTypePrivate', 'user_id': 7},
  'notification_settings': {
    '@type': 'chatNotificationSettings',
    'use_default_mute_for': useDefaultMuteFor,
    'mute_for': muteFor,
  },
  'last_message': {
    '@type': 'message',
    'id': 10,
    'date': 10,
    'content': {
      '@type': 'messageText',
      'text': {'@type': 'formattedText', 'text': 'hi'},
    },
  },
  'positions': [
    {
      '@type': 'chatPosition',
      'list': {'@type': 'chatListMain'},
      'order': 100,
      'is_pinned': false,
    },
  ],
};

/// Drives the model's 50 ms resort/badge debounce to completion.
Future<void> _settle(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 120));

void main() {
  setUp(() {
    // A cold start begins with nothing cached.
    ScopeNotificationSettings.shared.update(_privateScope, 0);
  });

  testWidgets(
    'default-following rows re-derive mute state when the scope loads later',
    (tester) async {
      final model = ChatListViewModel();
      addTearDown(model.dispose);

      // Cold start: hydrate before the scope cache knows the scope is muted.
      await model.ingestRawChatForTesting(_chat());
      await _settle(tester);
      expect(model.chats.single.isMuted, isFalse, reason: 'scope unknown yet');

      // The scope round trip lands (load() or updateScopeNotificationSettings).
      ScopeNotificationSettings.shared.update(_privateScope, 2147483647);
      await _settle(tester);

      expect(model.chats.single.isMuted, isTrue);
    },
  );

  testWidgets('chat-level mute overrides keep winning over the scope', (
    tester,
  ) async {
    final model = ChatListViewModel();
    addTearDown(model.dispose);

    // A chat muted for itself stays muted even while its scope is unmuted…
    await model.ingestRawChatForTesting(
      _chat(useDefaultMuteFor: false, muteFor: 2147483647),
    );
    await _settle(tester);
    expect(model.chats.single.isMuted, isTrue);

    // …and a scope flip does not steal the row's own override.
    ScopeNotificationSettings.shared.update(_privateScope, 0);
    await _settle(tester);
    expect(model.chats.single.isMuted, isTrue);
  });

  testWidgets(
    'updateChatNotificationSettings switching back to default follows the scope',
    (tester) async {
      final model = ChatListViewModel();
      addTearDown(model.dispose);

      await model.ingestRawChatForTesting(
        _chat(useDefaultMuteFor: false, muteFor: 2147483647),
      );
      await _settle(tester);
      expect(model.chats.single.isMuted, isTrue);
      // Scope is unmuted in this fixture.

      // The user resets the chat to follow the default.
      model.applyUpdateForTesting({
        '@type': 'updateChatNotificationSettings',
        'chat_id': 42,
        'notification_settings': {
          '@type': 'chatNotificationSettings',
          'use_default_mute_for': true,
          'mute_for': 0,
        },
      });
      await _settle(tester);

      expect(model.chats.single.isMuted, isFalse);
    },
  );

  testWidgets('scope unmute flips default-following rows back', (tester) async {
    final model = ChatListViewModel();
    addTearDown(model.dispose);

    ScopeNotificationSettings.shared.update(_privateScope, 2147483647);
    await model.ingestRawChatForTesting(_chat());
    await _settle(tester);
    expect(model.chats.single.isMuted, isTrue);

    // The user unmutes the whole scope from settings.
    ScopeNotificationSettings.shared.update(_privateScope, 0);
    await _settle(tester);

    expect(model.chats.single.isMuted, isFalse);
  });

  test('summary parse keeps the derivation inputs', () {
    final summary = TDParse.chat(_chat())!;
    expect(summary.useDefaultMuteFor, isTrue);
    expect(summary.muteForOverride, 0);

    final overridden = TDParse.chat(
      _chat(useDefaultMuteFor: false, muteFor: 2147483647),
    )!;
    expect(overridden.useDefaultMuteFor, isFalse);
    expect(overridden.muteForOverride, 2147483647);
  });
}
