//
//  chat_update_fanout_bench_test.dart
//
//  Measures what a live TDLib update costs the chat view model while a big
//  transcript is open. This is the lag a user actually feels: a reaction, an
//  edit, or a typing notice arriving in a conversation with thousands of
//  messages already loaded, folded on the same isolate that is trying to draw.
//
//  Most of these updates address exactly one message, but the view model finds
//  that message by scanning the transcript, so the work grows with the
//  conversation rather than with the update. The figure that matters is
//  therefore not the cost of one update but the scaling column: the same burst
//  against 500 and against 5000 loaded messages. A ratio near x1 is a lookup
//  that ignores transcript length; a ratio near x10 is one that walks it.
//
//  There is no timing assertion: absolute numbers depend on the machine, so a
//  threshold would only be flaky elsewhere. It asserts the shape of the run
//  instead — that every kind of update actually landed on the transcript — and
//  prints the costs for a human comparing two revisions:
//
//    flutter test test/chat_update_fanout_bench_test.dart
//
//  Each arm is measured twice, once in each order, because this machine speeds
//  up through a session and a fixed order would flatter whichever ran last.
//
//  Nothing here reaches TDLib. A stub proxy transport answers the history
//  query and swallows everything else, so no request touches the FFI bindings.
//

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_user_index.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _chatId = -1001;
const _senderIds = [9001, 9002, 9003, 9004];
const _senderNames = ['Mira Chen', 'Tomas Vogel', 'Aiko Sato', 'Rui Lima'];
const _firstMessageId = 100000;

/// One realistic burst: what a busy group delivers over a few seconds.
const _burstSize = 200;

/// The two arms of the scaling curve. Their ratio is the headline number.
const _smallTranscript = 500;
const _largeTranscript = 5000;

/// The history page the stub transport serves for the run being set up.
List<Map<String, dynamic>> _historyPage = const <Map<String, dynamic>>[];

enum _Kind {
  edited('updateMessageEdited'),
  interactionInfo('updateMessageInteractionInfo'),
  content('updateMessageContent'),
  chatAction('updateChatAction (typing)'),
  user('updateUser (sender changed)'),
  newMessage('updateNewMessage'),
  readReceipt('read receipts');

  const _Kind(this.label);
  final String label;
}

class _Result {
  const _Result(this.totalUs, this.applied);
  final int totalUs;
  final int applied;

  double get perUpdateUs => applied == 0 ? 0 : totalUs / applied;
}

Map<String, dynamic> _content(String text) => {
  '@type': 'messageText',
  'text': {'@type': 'formattedText', 'text': text, 'entities': []},
};

Map<String, dynamic> _sender(int userId) => {
  '@type': 'messageSenderUser',
  'user_id': userId,
};

Map<String, dynamic> _user(int userId, String surname) => {
  '@type': 'user',
  'id': userId,
  'first_name': _senderNames[_senderIds.indexOf(userId)].split(' ').first,
  'last_name': surname,
  'accent_color_id': 3,
};

Map<String, dynamic> _rawMessage(int index, String body) => {
  '@type': 'message',
  'id': _firstMessageId + index,
  'chat_id': _chatId,
  'is_outgoing': index % 3 == 0,
  'date': 1785862260 + index * 60,
  'sender_id': _sender(_senderIds[(index ~/ 3) % _senderIds.length]),
  'content': _content(body),
};

/// A transcript with the shape a real one has: mixed direction, senders
/// repeating in runs, ids ascending with time.
List<Map<String, dynamic>> _transcript(int count) => [
  for (var i = 0; i < count; i++) _rawMessage(i, 'message $i'),
];

/// Spreads the burst across the transcript instead of hammering one end: a
/// scan that always found its target on the first comparison would report a
/// cost no real conversation pays.
int _targetId(int step, int count) =>
    _firstMessageId + ((step + 1) * 997) % count;

List<Map<String, dynamic>> _burst(_Kind kind, int count) => [
  for (var step = 0; step < _burstSize; step++)
    switch (kind) {
      _Kind.edited => {
        '@type': 'updateMessageEdited',
        'chat_id': _chatId,
        'message_id': _targetId(step, count),
        'edit_date': 1785999999,
      },
      _Kind.interactionInfo => {
        '@type': 'updateMessageInteractionInfo',
        'chat_id': _chatId,
        'message_id': _targetId(step, count),
        'interaction_info': {
          '@type': 'messageInteractionInfo',
          'view_count': 500 + step,
          'forward_count': step % 7,
          'reactions': {
            '@type': 'messageReactions',
            'reactions': [
              {
                '@type': 'messageReaction',
                'type': {'@type': 'reactionTypeEmoji', 'emoji': '👍'},
                'total_count': 1 + step % 5,
                'is_chosen': step.isEven,
              },
            ],
          },
        },
      },
      _Kind.content => {
        '@type': 'updateMessageContent',
        'chat_id': _chatId,
        'message_id': _targetId(step, count),
        'new_content': _content('edited body $step'),
      },
      _Kind.chatAction => {
        '@type': 'updateChatAction',
        'chat_id': _chatId,
        'sender_id': _sender(_senderIds[step % _senderIds.length]),
        'action': {
          '@type': step % 5 == 4 ? 'chatActionCancel' : 'chatActionTyping',
        },
      },
      _Kind.user => {
        '@type': 'updateUser',
        'user': _user(_senderIds[step % _senderIds.length], 'Rev$step'),
      },
      _Kind.newMessage => {
        '@type': 'updateNewMessage',
        'message': _rawMessage(count + step, 'arriving $step'),
      },
      _Kind.readReceipt =>
        step.isEven
            ? {
                '@type': 'updateChatReadInbox',
                'chat_id': _chatId,
                'last_read_inbox_message_id': _firstMessageId + step,
                'unread_count': _burstSize - step,
              }
            : {
                '@type': 'updateChatReadOutbox',
                'chat_id': _chatId,
                'last_read_outbox_message_id': _firstMessageId + step,
              },
    },
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  // A transport with nowhere to go. It serves the history page the view model
  // asks for and drops every other request, which keeps the whole benchmark
  // off the TDLib bindings.
  TdClient.shared.configureProxy(
    TdClientProxyTransport(
      accountSlot: 0,
      query: (request) async => request['@type'] == 'getChatHistory'
          ? {'@type': 'messages', 'messages': _historyPage}
          : const <String, dynamic>{'@type': 'ok'},
      send: (_) async {},
      updates: const Stream<Map<String, dynamic>>.empty(),
    ),
  );

  Future<_Result> run(_Kind kind, int count) async {
    _historyPage = _transcript(count);
    final viewModel = ChatViewModel(
      chatId: _chatId,
      title: 'Design Circle',
      markReadOnOpen: false,
    )..isGroup = true;
    for (var i = 0; i < _senderIds.length; i++) {
      TdUserIndex.shared.observe(TdClient.shared.activeSlot, {
        '@type': 'updateUser',
        'user': _user(_senderIds[i], _senderNames[i].split(' ').last),
      });
    }
    // Loaded the way the app loads it, so the transcript window really does
    // reach the latest message and live arrivals merge instead of being
    // dropped as a hole in the history.
    await viewModel.loadLatestHistory();
    // A cold sender cache would fire a getUser per update and measure the stub
    // transport instead of the fan-out.
    viewModel.primeCachedSenderIdentitiesForTesting();
    expect(viewModel.messages.length, count);

    // Built up front: this measures folding an update, not building its JSON.
    final updates = _burst(kind, count);
    final stopwatch = Stopwatch()..start();
    for (final update in updates) {
      viewModel.applyLiveUpdateForTesting(update);
    }
    stopwatch.stop();

    // An update the view model dropped costs nothing and would report a
    // flatteringly low figure, so prove each kind reached the transcript.
    switch (kind) {
      case _Kind.edited:
        expect(
          viewModel.messages.where((m) => m.isEdited).length,
          greaterThan(_burstSize ~/ 2),
        );
      case _Kind.interactionInfo:
        expect(
          viewModel.messages.where((m) => m.viewCount > 0).length,
          greaterThan(_burstSize ~/ 2),
        );
      case _Kind.content:
        expect(
          viewModel.messages.where((m) => m.text.startsWith('edited')).length,
          greaterThan(_burstSize ~/ 2),
        );
      case _Kind.chatAction:
        expect(viewModel.hasActiveChatAction, isTrue);
      case _Kind.user:
        expect(
          viewModel.messages.where(
            (m) => m.senderName?.contains('Rev') ?? false,
          ),
          isNotEmpty,
        );
      case _Kind.newMessage:
        expect(viewModel.messages.length, count + _burstSize);
      case _Kind.readReceipt:
        expect(viewModel.lastReadInboxId, greaterThan(0));
        expect(viewModel.lastReadOutboxId, greaterThan(0));
    }
    viewModel.dispose();
    return _Result(stopwatch.elapsedMicroseconds, updates.length);
  }

  test('live update fan-out against transcript length', () async {
    // Warm the JIT and the shared caches so the first kind measured is not
    // charged for everything the later ones get for free.
    for (final kind in _Kind.values) {
      await run(kind, _smallTranscript);
    }

    final small = <_Kind, double>{};
    final large = <_Kind, double>{};
    var burstUs = 0;
    for (final kind in _Kind.values) {
      final firstSmall = await run(kind, _smallTranscript);
      final firstLarge = await run(kind, _largeTranscript);
      final secondLarge = await run(kind, _largeTranscript);
      final secondSmall = await run(kind, _smallTranscript);
      small[kind] = (firstSmall.perUpdateUs + secondSmall.perUpdateUs) / 2;
      large[kind] = (firstLarge.perUpdateUs + secondLarge.perUpdateUs) / 2;
      burstUs += (firstLarge.totalUs + secondLarge.totalUs) ~/ 2;
    }

    for (final kind in _Kind.values) {
      // ignore: avoid_print
      print(
        'BENCH ${kind.label.padRight(30)} '
        '$_smallTranscript msg ${small[kind]!.toStringAsFixed(1).padLeft(7)}us  '
        '$_largeTranscript msg ${large[kind]!.toStringAsFixed(1).padLeft(7)}us  '
        'scaling x${(large[kind]! / small[kind]!).toStringAsFixed(1)}',
      );
    }
    // ignore: avoid_print
    print(
      'BENCH ${'every kind, $_largeTranscript msg'.padRight(30)} '
      '${_burstSize * _Kind.values.length} updates '
      '${(burstUs / 1000).toStringAsFixed(1)}ms',
    );
  });
}
