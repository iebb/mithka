import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/unread_chat_summary_models.dart';
import 'package:mithka/chat/unread_chat_summary_service.dart';

Map<String, dynamic> _message(int id, {bool outgoing = false, String? text}) =>
    {
      '@type': 'message',
      'id': id,
      'chat_id': 42,
      'date': 1000 + id,
      'is_outgoing': outgoing,
      'sender_id': outgoing
          ? {'@type': 'messageSenderUser', 'user_id': 1}
          : {'@type': 'messageSenderUser', 'user_id': 7},
      'content': {
        '@type': 'messageText',
        'text': {
          '@type': 'formattedText',
          'text': text ?? 'message $id',
          'entities': <Map<String, dynamic>>[],
        },
      },
    };

UnreadChatRangeSnapshot _snapshot({
  int accountSlot = 2,
  int lastReadInboxId = 300,
  int unreadCount = 4,
  int upperMessageId = 500,
}) => UnreadChatRangeSnapshot(
  chatId: 42,
  accountSlot: accountSlot,
  lastReadInboxId: lastReadInboxId,
  unreadCount: unreadCount,
  upperMessageId: upperMessageId,
  capturedAt: DateTime.utc(2026, 7, 20, 12),
);

Map<String, dynamic> _summaryJson(
  String evidenceId, {
  String text = 'Catch up',
}) => {
  'overview': text,
  'overview_evidence_ids': [evidenceId],
  'highlights': [
    {
      'text': text,
      'evidence_ids': [evidenceId],
    },
  ],
  'needs_reply': <Map<String, dynamic>>[],
  'decisions': <Map<String, dynamic>>[],
  'actions': <Map<String, dynamic>>[],
  'questions': <Map<String, dynamic>>[],
  'uncertainties': <Map<String, dynamic>>[],
};

class _RecordingProvider implements UnreadChatSummaryProvider {
  final List<UnreadChatSummaryProviderRequest> requests = [];

  @override
  Future<Map<String, dynamic>> complete(
    UnreadChatSummaryProviderRequest request,
  ) async {
    requests.add(request);
    return _summaryJson(
      request.allowedEvidenceIds.first,
      text: request.stage == UnreadChatSummaryStage.merge ? 'Merged' : 'Chunk',
    );
  }
}

void main() {
  group('UnreadChatHistoryLoader', () {
    test(
      'paginates short pages, deduplicates boundaries, and freezes the range',
      () async {
        final requests = <(int, Map<String, dynamic>)>[];
        final loader = UnreadChatHistoryLoader(
          query: (accountSlot, request) async {
            requests.add((accountSlot, request));
            return switch (request['from_message_id']) {
              500 => {
                '@type': 'messages',
                // A post-snapshot arrival must never enter the transcript.
                'messages': [
                  _message(600),
                  _message(500),
                  _message(450),
                  _message(400),
                ],
              },
              400 => {
                '@type': 'messages',
                // 400 is deliberately repeated by offset=0 pagination.
                'messages': [
                  _message(400),
                  _message(350),
                  _message(300),
                  _message(250),
                ],
              },
              _ => throw StateError('Unexpected request $request'),
            };
          },
        );

        final transcript = await loader.load(_snapshot());

        expect(transcript.messages.map((message) => message.id), [
          350,
          400,
          450,
          500,
        ]);
        expect(transcript.reachedReadBoundary, isTrue);
        expect(transcript.historyCapped, isFalse);
        expect(transcript.historyStalled, isFalse);
        expect(transcript.historyRequestCount, 2);
        expect(requests.map((entry) => entry.$1), everyElement(2));
        expect(requests.map((entry) => entry.$2['@type']).toSet(), {
          'getChatHistory',
        });
        expect(
          requests.expand((entry) => entry.$2.keys),
          isNot(contains('message_ids')),
        );
        expect(requests.first.$2['limit'], 100);
        expect(requests.first.$2['offset'], 0);
        expect(requests.first.$2['only_local'], isFalse);
      },
    );

    test(
      'reports incomplete coverage when the history cap is reached',
      () async {
        final loader = UnreadChatHistoryLoader(
          maxMessages: 2,
          query: (_, _) async => {
            '@type': 'messages',
            'messages': [
              _message(500),
              _message(450),
              _message(400),
              _message(300),
            ],
          },
        );

        final transcript = await loader.load(_snapshot(unreadCount: 3));

        expect(transcript.messages, hasLength(2));
        expect(transcript.historyCapped, isTrue);
        final result = await UnreadChatSummaryService(
          historyLoader: loader,
          provider: _RecordingProvider(),
        ).summarizeTranscript(transcript);
        expect(result.coverage.complete, isFalse);
        expect(
          result.coverage.limitations,
          contains('history_message_cap_reached'),
        );
      },
    );

    test('an empty frozen range performs no TDLib request', () async {
      var called = false;
      final loader = UnreadChatHistoryLoader(
        query: (_, _) async {
          called = true;
          return const {};
        },
      );

      final transcript = await loader.load(
        _snapshot(unreadCount: 0, upperMessageId: 300),
      );

      expect(called, isFalse);
      expect(transcript.messages, isEmpty);
      expect(transcript.reachedReadBoundary, isTrue);
    });
  });

  group('UnreadChatSummaryService', () {
    test(
      'chunks then merges with grounded same-language instructions',
      () async {
        final provider = _RecordingProvider();
        final service = UnreadChatSummaryService(
          historyLoader: UnreadChatHistoryLoader(
            query: (_, _) async => const {'@type': 'messages', 'messages': []},
          ),
          provider: provider,
          maxChunkMessages: 2,
          maxChunkCharacters: 100000,
          maxChunks: 3,
        );
        final messages = [
          for (var id = 1; id <= 5; id++)
            UnreadChatMessage(
              id: id,
              date: id,
              senderKey: 'user:7',
              isOutgoing: false,
              isService: false,
              contentType: 'messageText',
              text: '消息 $id',
            ),
        ];
        final transcript = UnreadChatTranscript(
          snapshot: _snapshot(
            lastReadInboxId: 0,
            unreadCount: 5,
            upperMessageId: 5,
          ),
          messages: messages,
          historyRequestCount: 1,
          reachedReadBoundary: true,
          historyCapped: false,
          historyStalled: false,
        );

        final result = await service.summarizeTranscript(transcript);

        expect(provider.requests, hasLength(4));
        expect(provider.requests.map((request) => request.stage), [
          UnreadChatSummaryStage.chunk,
          UnreadChatSummaryStage.chunk,
          UnreadChatSummaryStage.chunk,
          UnreadChatSummaryStage.merge,
        ]);
        expect(
          provider.requests.first.trustedInstructions,
          contains('same language or languages used by the chat messages'),
        );
        expect(
          provider.requests.first.payload['output_language'],
          'same_as_chat',
        );
        expect(result.overview, 'Merged');
        expect(result.coverage.complete, isTrue);
        expect(result.coverage.summarizedMessageCount, 5);
      },
    );

    test('keeps newest bounded chunks and discloses processing cap', () async {
      final provider = _RecordingProvider();
      final service = UnreadChatSummaryService(
        historyLoader: UnreadChatHistoryLoader(
          query: (_, _) async => const {'@type': 'messages', 'messages': []},
        ),
        provider: provider,
        maxChunkMessages: 2,
        maxChunkCharacters: 100000,
        maxChunks: 2,
      );
      final transcript = UnreadChatTranscript(
        snapshot: _snapshot(
          lastReadInboxId: 0,
          unreadCount: 5,
          upperMessageId: 5,
        ),
        messages: [
          for (var id = 1; id <= 5; id++)
            UnreadChatMessage(
              id: id,
              date: id,
              senderKey: 'user:7',
              isOutgoing: false,
              isService: false,
              contentType: 'messageText',
              text: 'message $id',
            ),
        ],
        historyRequestCount: 1,
        reachedReadBoundary: true,
        historyCapped: false,
        historyStalled: false,
      );

      final result = await service.summarizeTranscript(transcript);

      expect(provider.requests.first.allowedEvidenceIds, {'m3', 'm4'});
      expect(provider.requests[1].allowedEvidenceIds, {'m5'});
      expect(result.coverage.processingCapped, isTrue);
      expect(result.coverage.summarizedMessageCount, 3);
      expect(result.coverage.complete, isFalse);
      expect(
        result.coverage.limitations,
        contains('summary_chunk_cap_reached'),
      );
    });

    test('rejects evidence IDs outside the supplied transcript', () async {
      final provider = _InvalidEvidenceProvider();
      final service = UnreadChatSummaryService(
        historyLoader: UnreadChatHistoryLoader(
          query: (_, _) async => const {'@type': 'messages', 'messages': []},
        ),
        provider: provider,
      );
      final transcript = UnreadChatTranscript(
        snapshot: _snapshot(
          lastReadInboxId: 0,
          unreadCount: 1,
          upperMessageId: 1,
        ),
        messages: [
          const UnreadChatMessage(
            id: 1,
            date: 1,
            senderKey: 'user:7',
            isOutgoing: false,
            isService: false,
            contentType: 'messageText',
            text: 'hello',
          ),
        ],
        historyRequestCount: 1,
        reachedReadBoundary: true,
        historyCapped: false,
        historyStalled: false,
      );

      expect(
        () => service.summarizeTranscript(transcript),
        throwsA(isA<UnreadChatSummaryFormatException>()),
      );
    });
  });
}

class _InvalidEvidenceProvider implements UnreadChatSummaryProvider {
  @override
  Future<Map<String, dynamic>> complete(
    UnreadChatSummaryProviderRequest request,
  ) async => _summaryJson('m999');
}
