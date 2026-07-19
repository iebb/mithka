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
  'title': '$text title',
  'overview': text,
  'overview_evidence_ids': [evidenceId],
  'topics': [
    {
      'title': '$text topic',
      'summary': text,
      'start_date_unix': 0,
      'end_date_unix': 0,
      'evidence_ids': [evidenceId],
    },
  ],
  'rant': {
    'text': '$text take',
    'evidence_ids': [evidenceId],
  },
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

        final progress = <int>[];
        final transcript = await loader.load(
          _snapshot(),
          onProgress: progress.add,
        );

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
        expect(progress, [0, 3, 4]);
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
          maxChunkTokenEstimate: 100000,
          maxChunks: 3,
          maxInlineBurstMessages: 1,
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
        expect(provider.requests.first.payload['message_schema'], isA<List>());
        final promptMessages =
            provider.requests.first.payload['messages'] as List<Object?>;
        expect(promptMessages.first, isA<List<Object?>>());
        expect((promptMessages.first as List<Object?>).first, [
          provider.requests.first.allowedEvidenceIds.first,
        ]);
        expect(result.overview, 'Merged');
        expect(result.coverage.complete, isTrue);
        expect(result.coverage.summarizedMessageCount, 5);
      },
    );

    test('samples across the range when the chunk budget is capped', () async {
      final provider = _RecordingProvider();
      final service = UnreadChatSummaryService(
        historyLoader: UnreadChatHistoryLoader(
          query: (_, _) async => const {'@type': 'messages', 'messages': []},
        ),
        provider: provider,
        maxChunkMessages: 2,
        maxChunkTokenEstimate: 100000,
        maxChunks: 2,
        maxInlineBurstMessages: 1,
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

      expect(provider.requests.first.allowedEvidenceIds, {'m1', 'm3'});
      expect(provider.requests[1].allowedEvidenceIds, {'m5'});
      expect(result.coverage.processingCapped, isTrue);
      expect(result.coverage.summarizedMessageCount, 3);
      expect(result.coverage.complete, isFalse);
      expect(
        result.coverage.limitations,
        contains('summary_chunk_cap_reached'),
      );
      expect(provider.requests.first.payload['selection'], {
        'strategy': 'frequency_recency_signal_sample',
        'source_message_count': 5,
        'selected_message_count': 3,
        'ignored_duplicate_or_low_signal_count': 0,
      });
    });

    test(
      'hierarchically merges large chunk sets within the fan-in cap',
      () async {
        final provider = _RecordingProvider();
        final service = UnreadChatSummaryService(
          historyLoader: UnreadChatHistoryLoader(
            query: (_, _) async => const {'@type': 'messages', 'messages': []},
          ),
          provider: provider,
          maxChunkMessages: 1,
          maxChunkTokenEstimate: 100000,
          maxChunks: 20,
          maxMergeSummaries: 3,
          maxMergeTokenEstimate: 100000,
          maxInlineBurstMessages: 1,
        );
        final transcript = UnreadChatTranscript(
          snapshot: _snapshot(
            lastReadInboxId: 0,
            unreadCount: 7,
            upperMessageId: 7,
          ),
          messages: [
            for (var id = 1; id <= 7; id++)
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
        final mergeRequests = provider.requests
            .where((request) => request.stage == UnreadChatSummaryStage.merge)
            .toList();

        expect(mergeRequests, hasLength(3));
        expect(
          mergeRequests.map(
            (request) =>
                (request.payload['chunk_summaries'] as List<Object?>).length,
          ),
          everyElement(lessThanOrEqualTo(3)),
        );
        expect(result.overview, 'Merged');
        expect(result.coverage.complete, isTrue);
        expect(result.coverage.summarizedMessageCount, 7);
      },
    );

    test('derives a conservative prompt budget from the PCC context size', () {
      expect(unreadSummaryChunkTokenBudget(null), 8000);
      expect(unreadSummaryChunkTokenBudget(4096), 1200);
      expect(unreadSummaryChunkTokenBudget(32768), 20000);
      expect(
        estimateUnreadSummaryPromptTokens({
          'text': List.filled(100, '未读消息').join(),
        }),
        greaterThanOrEqualTo(100),
      );
    });

    test('inlines a 1600-message same-sender burst into one chunk', () async {
      final provider = _RecordingProvider();
      final service = UnreadChatSummaryService(
        historyLoader: UnreadChatHistoryLoader(
          query: (_, _) async => const {'@type': 'messages', 'messages': []},
        ),
        provider: provider,
        maxChunkTokenEstimate: unreadSummaryChunkTokenBudget(32768),
      );
      final transcript = UnreadChatTranscript(
        snapshot: _snapshot(
          lastReadInboxId: 0,
          unreadCount: 1600,
          upperMessageId: 1600,
        ),
        messages: [
          for (var id = 1; id <= 1600; id++)
            UnreadChatMessage(
              id: id,
              date: id,
              senderKey: 'user:7',
              isOutgoing: false,
              isService: false,
              contentType: 'messageText',
              text: '消息$id',
            ),
        ],
        historyRequestCount: 16,
        reachedReadBoundary: true,
        historyCapped: false,
        historyStalled: false,
      );

      final result = await service.summarizeTranscript(transcript);

      final chunkRequests = provider.requests.where(
        (request) => request.stage == UnreadChatSummaryStage.chunk,
      );
      expect(chunkRequests, hasLength(1));
      expect(
        provider.requests.where(
          (request) => request.stage == UnreadChatSummaryStage.merge,
        ),
        isEmpty,
      );
      expect(
        (chunkRequests.single.payload['messages'] as List<Object?>).length,
        200,
      );
      expect(result.coverage.summarizedMessageCount, 1600);
      expect(result.coverage.complete, isTrue);
    });

    test(
      'samples 2685 alternating messages across three parallel chunks',
      () async {
        final provider = _ConcurrentRecordingProvider();
        final service = UnreadChatSummaryService(
          historyLoader: UnreadChatHistoryLoader(
            query: (_, _) async => const {'@type': 'messages', 'messages': []},
          ),
          provider: provider,
          maxChunkTokenEstimate: unreadSummaryChunkTokenBudget(32768),
          maxChunks: 3,
        );
        final transcript = UnreadChatTranscript(
          snapshot: _snapshot(
            lastReadInboxId: 0,
            unreadCount: 2685,
            upperMessageId: 2685,
          ),
          messages: [
            for (var id = 1; id <= 2685; id++)
              UnreadChatMessage(
                id: id,
                date: 1000 + id,
                senderKey: 'user:${id.isEven ? 7 : 8}',
                isOutgoing: false,
                isService: false,
                contentType: 'messageText',
                text: id == 400 ? 'Important question?' : 'message $id',
                replyToMessageId: id == 400 ? 399 : null,
              ),
          ],
          historyRequestCount: 27,
          reachedReadBoundary: true,
          historyCapped: false,
          historyStalled: false,
        );

        final result = await service.summarizeTranscript(transcript);
        final chunkRequests = provider.requests
            .where((request) => request.stage == UnreadChatSummaryStage.chunk)
            .toList();
        final selectedIds = {
          for (final request in chunkRequests) ...request.allowedEvidenceIds,
        };

        expect(chunkRequests, hasLength(3));
        expect(provider.maximumActiveRequests, 2);
        expect(selectedIds, containsAll(['m1', 'm400', 'm2685']));
        expect(result.coverage.processingCapped, isTrue);
        expect(result.coverage.summarizedMessageCount, lessThan(2685));
      },
    );

    test(
      'locally assembles parallel chunks without another model call',
      () async {
        final provider = _ConcurrentRecordingProvider();
        final service = UnreadChatSummaryService(
          historyLoader: UnreadChatHistoryLoader(
            query: (_, _) async => const {'@type': 'messages', 'messages': []},
          ),
          provider: provider,
          maxChunkMessages: 2,
          maxChunkTokenEstimate: 100000,
          maxChunks: 2,
          maxInlineBurstMessages: 1,
          mergeChunkSummariesLocally: true,
        );
        final transcript = UnreadChatTranscript(
          snapshot: _snapshot(lastReadInboxId: 0, upperMessageId: 4),
          messages: [
            for (var id = 1; id <= 4; id++)
              UnreadChatMessage(
                id: id,
                date: id,
                senderKey: 'user:$id',
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
        final progress = <UnreadChatSummaryProgress>[];

        final result = await service.summarizeTranscript(
          transcript,
          onProgress: progress.add,
        );

        expect(provider.requests, hasLength(2));
        expect(
          provider.requests,
          everyElement(
            isA<UnreadChatSummaryProviderRequest>().having(
              (request) => request.stage,
              'stage',
              UnreadChatSummaryStage.chunk,
            ),
          ),
        );
        expect(provider.maximumActiveRequests, 2);
        expect(result.overview, 'Chunk m1 Chunk m3');
        expect(
          result.highlights.map((item) => item.text),
          containsAll(['Chunk m1', 'Chunk m3']),
        );
        expect(progress.first.completed, 0);
        expect(progress.first.total, 2);
        expect(
          progress.last.stage,
          UnreadChatSummaryProgressStage.assemblingSummary,
        );
      },
    );

    test('starts a new chunk after a meaningful chat time gap', () async {
      final provider = _RecordingProvider();
      final service = UnreadChatSummaryService(
        historyLoader: UnreadChatHistoryLoader(
          query: (_, _) async => const {'@type': 'messages', 'messages': []},
        ),
        provider: provider,
        maxChunkMessages: 100,
        maxChunkTokenEstimate: 100000,
        maxChunks: 3,
        maxChunkTimeGapSeconds: 300,
      );
      final transcript = UnreadChatTranscript(
        snapshot: _snapshot(lastReadInboxId: 0, upperMessageId: 4),
        messages: [
          for (final (id, date) in const [(1, 1), (2, 2), (3, 3605), (4, 3606)])
            UnreadChatMessage(
              id: id,
              date: date,
              senderKey: 'user:7',
              isOutgoing: false,
              isService: false,
              contentType: 'messageText',
              text: 'detail $id',
            ),
        ],
        historyRequestCount: 1,
        reachedReadBoundary: true,
        historyCapped: false,
        historyStalled: false,
      );

      await service.summarizeTranscript(transcript);

      final chunks = provider.requests
          .where((request) => request.stage == UnreadChatSummaryStage.chunk)
          .toList();
      expect(chunks, hasLength(2));
      expect(chunks.first.allowedEvidenceIds, {'m1', 'm2'});
      expect(chunks.last.allowedEvidenceIds, {'m3', 'm4'});
    });

    test(
      'omits close duplicates and low-information standalone replies',
      () async {
        final provider = _RecordingProvider();
        final service = UnreadChatSummaryService(
          historyLoader: UnreadChatHistoryLoader(
            query: (_, _) async => const {'@type': 'messages', 'messages': []},
          ),
          provider: provider,
          maxChunkTokenEstimate: 100000,
          maxInlineBurstMessages: 1,
        );
        final transcript = UnreadChatTranscript(
          snapshot: _snapshot(
            lastReadInboxId: 0,
            unreadCount: 5,
            upperMessageId: 5,
          ),
          messages: [
            const UnreadChatMessage(
              id: 1,
              date: 1,
              senderKey: 'user:7',
              isOutgoing: false,
              isService: false,
              contentType: 'messageText',
              text: 'Important launch detail',
            ),
            const UnreadChatMessage(
              id: 2,
              date: 2,
              senderKey: 'user:7',
              isOutgoing: false,
              isService: false,
              contentType: 'messageText',
              text: 'Important launch detail',
            ),
            const UnreadChatMessage(
              id: 3,
              date: 3,
              senderKey: 'user:8',
              isOutgoing: false,
              isService: false,
              contentType: 'messageText',
              text: 'ok',
            ),
            const UnreadChatMessage(
              id: 4,
              date: 4,
              senderKey: 'user:8',
              isOutgoing: false,
              isService: false,
              contentType: 'messageText',
              text: 'Another useful detail',
            ),
            const UnreadChatMessage(
              id: 5,
              date: 5,
              senderKey: 'user:9',
              isOutgoing: false,
              isService: false,
              contentType: 'messageText',
              text: 'Final useful detail',
            ),
          ],
          historyRequestCount: 1,
          reachedReadBoundary: true,
          historyCapped: false,
          historyStalled: false,
        );

        final result = await service.summarizeTranscript(transcript);

        expect(provider.requests.single.allowedEvidenceIds, {'m1', 'm4', 'm5'});
        expect(
          provider.requests.single.payload['selection'],
          containsPair('ignored_duplicate_or_low_signal_count', 2),
        );
        expect(result.coverage.complete, isTrue);
      },
    );

    test('keeps successful chunks when one parallel request fails', () async {
      final provider = _FailOneChunkProvider();
      final service = UnreadChatSummaryService(
        historyLoader: UnreadChatHistoryLoader(
          query: (_, _) async => const {'@type': 'messages', 'messages': []},
        ),
        provider: provider,
        maxChunkMessages: 1,
        maxChunkTokenEstimate: 100000,
        maxChunks: 3,
        maxInlineBurstMessages: 1,
        mergeChunkSummariesLocally: true,
      );
      final transcript = UnreadChatTranscript(
        snapshot: _snapshot(
          lastReadInboxId: 0,
          unreadCount: 3,
          upperMessageId: 3,
        ),
        messages: [
          for (var id = 1; id <= 3; id++)
            UnreadChatMessage(
              id: id,
              date: id,
              senderKey: 'user:$id',
              isOutgoing: false,
              isService: false,
              contentType: 'messageText',
              text: 'detail $id',
            ),
        ],
        historyRequestCount: 1,
        reachedReadBoundary: true,
        historyCapped: false,
        historyStalled: false,
      );

      final result = await service.summarizeTranscript(transcript);

      expect(result.overview, contains('m1'));
      expect(result.overview, contains('m3'));
      expect(result.coverage.summarizedMessageCount, 2);
      expect(result.coverage.failedRequestCount, 1);
      expect(result.coverage.complete, isFalse);
      expect(result.topics, isNotEmpty);
      expect(result.rant, isNotNull);
    });

    test(
      'falls back locally when merge fails and retries only the merge',
      () async {
        final provider = _FailFirstMergeProvider();
        var historyRequestCount = 0;
        final snapshot = _snapshot(
          lastReadInboxId: 0,
          unreadCount: 5,
          upperMessageId: 5,
        );
        final service = UnreadChatSummaryService(
          historyLoader: UnreadChatHistoryLoader(
            query: (_, request) async {
              historyRequestCount++;
              return request['from_message_id'] == 5
                  ? {
                      '@type': 'messages',
                      'messages': [
                        for (var id = 5; id >= 1; id--) _message(id),
                      ],
                    }
                  : const {'@type': 'messages', 'messages': []};
            },
          ),
          provider: provider,
          maxChunkMessages: 2,
          maxChunkTokenEstimate: 100000,
          maxInlineBurstMessages: 1,
        );

        final partial = await service.summarize(snapshot);
        final result = await service.summarize(snapshot);

        expect(historyRequestCount, 2);
        expect(partial.overview, 'Chunk');
        expect(partial.coverage.failedRequestCount, 1);
        expect(partial.coverage.complete, isFalse);
        expect(
          provider.requests.where(
            (request) => request.stage == UnreadChatSummaryStage.chunk,
          ),
          hasLength(3),
        );
        expect(
          provider.requests.where(
            (request) => request.stage == UnreadChatSummaryStage.merge,
          ),
          hasLength(2),
        );
        expect(result.overview, 'Merged');
        expect(result.coverage.failedRequestCount, 0);
      },
    );

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

class _FailFirstMergeProvider extends _RecordingProvider {
  var _failed = false;

  @override
  Future<Map<String, dynamic>> complete(
    UnreadChatSummaryProviderRequest request,
  ) async {
    requests.add(request);
    if (request.stage == UnreadChatSummaryStage.merge && !_failed) {
      _failed = true;
      throw StateError('merge failed');
    }
    return _summaryJson(
      request.allowedEvidenceIds.first,
      text: request.stage == UnreadChatSummaryStage.merge ? 'Merged' : 'Chunk',
    );
  }
}

class _FailOneChunkProvider extends _RecordingProvider {
  @override
  Future<Map<String, dynamic>> complete(
    UnreadChatSummaryProviderRequest request,
  ) async {
    requests.add(request);
    if (request.stage == UnreadChatSummaryStage.chunk &&
        request.allowedEvidenceIds.contains('m2')) {
      throw StateError('chunk failed');
    }
    return _summaryJson(
      request.allowedEvidenceIds.first,
      text: 'Chunk ${request.allowedEvidenceIds.first}',
    );
  }
}

class _ConcurrentRecordingProvider extends _RecordingProvider {
  var activeRequests = 0;
  var maximumActiveRequests = 0;

  @override
  Future<Map<String, dynamic>> complete(
    UnreadChatSummaryProviderRequest request,
  ) async {
    requests.add(request);
    activeRequests++;
    if (activeRequests > maximumActiveRequests) {
      maximumActiveRequests = activeRequests;
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
    activeRequests--;
    return _summaryJson(
      request.allowedEvidenceIds.first,
      text: request.stage == UnreadChatSummaryStage.merge
          ? 'Merged'
          : 'Chunk ${request.allowedEvidenceIds.first}',
    );
  }
}
