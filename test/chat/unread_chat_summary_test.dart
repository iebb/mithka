import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mithka/chat/ai_translation/apple_pcc_unread_summary_provider.dart';
import 'package:mithka/chat/ai_translation/openai_compatible_unread_summary_provider.dart';
import 'package:mithka/chat/ai_translation/unread_chat_summary_models.dart';
import 'package:mithka/chat/ai_translation/unread_chat_summary_service.dart';
import 'package:mithka/chat/ai_translation/unread_chat_summary_view.dart';
import 'package:mithka/chat/chat_unread_progress.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/ai_translation/ai_settings_controller.dart';
import 'package:mithka/settings/ai_translation/apple_pcc_api.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('summary attachment is opt-in and only applies to the entry badge', () {
    bool offered({
      int remaining = 100,
      bool liveBadge = false,
      bool enabled = true,
      bool provider = true,
    }) => shouldShowUnreadChatSummaryAttachment(
      capturedUnreadRemaining: remaining,
      showingLiveUnread: liveBadge,
      summaryEnabled: enabled,
      providerAvailable: provider,
    );

    expect(offered(), isTrue);
    expect(offered(remaining: 99), isFalse);
    expect(offered(liveBadge: true), isFalse);
    expect(offered(remaining: 1, liveBadge: true), isFalse);
    expect(offered(enabled: false), isFalse);
    expect(offered(provider: false), isFalse);
  });

  test(
    'invalidation during deferred history prevents provider dispatch',
    () async {
      final page = Completer<Map<String, dynamic>>();
      final provider = _RecordingProvider();
      var available = true;
      final service = UnreadChatSummaryService(
        historyLoader: UnreadChatHistoryLoader(query: (_, _) => page.future),
        provider: provider,
        isAvailable: () => available,
      );
      final result = service.summarize(_snapshot());
      final rejected = expectLater(
        result,
        throwsA(isA<UnreadChatSummaryUnavailable>()),
      );
      available = false;
      page.complete({
        'messages': [
          {
            'id': 200,
            'chat_id': 1,
            'date': 1700000000,
            'content': {
              '@type': 'messageText',
              'text': {'text': 'A message that should never leave this chat.'},
            },
          },
          {'id': 10},
        ],
      });
      await rejected;
      expect(provider.stages, isEmpty);
    },
  );

  test('invalidation after chunks prevents dispatch of the remote merge', () async {
    final provider = _RecordingProvider();
    var available = true;
    final service = UnreadChatSummaryService(
      historyLoader: UnreadChatHistoryLoader(query: (_, _) async => {}),
      provider: provider,
      isAvailable: () => available,
      maxChunkMessages: 1,
    );
    final transcript = UnreadChatTranscript(
      snapshot: _snapshot(),
      messages: const [
        UnreadChatMessage(
          id: 101,
          date: 100,
          senderKey: 'first',
          isOutgoing: false,
          isService: false,
          contentType: 'messageText',
          text:
              'The team reviewed the initial proposal and decided on a budget.',
        ),
        UnreadChatMessage(
          id: 102,
          date: 200,
          senderKey: 'second',
          isOutgoing: false,
          isService: false,
          contentType: 'messageText',
          text:
              'The vendor will deliver materials and confirm the exact delivery date.',
        ),
      ],
      historyRequestCount: 1,
      reachedReadBoundary: true,
      historyCapped: false,
      historyStalled: false,
    );
    await expectLater(
      service.summarizeTranscript(
        transcript,
        onProgress: (progress) {
          if (progress.stage ==
              UnreadChatSummaryProgressStage.assemblingSummary) {
            available = false;
          }
        },
      ),
      throwsA(isA<UnreadChatSummaryUnavailable>()),
    );
    expect(provider.stages, [
      UnreadChatSummaryStage.chunk,
      UnreadChatSummaryStage.chunk,
    ]);
  });

  test('hosted provider does not retry after invalidation', () async {
    final response = Completer<http.Response>();
    final sent = Completer<void>();
    var requests = 0;
    var available = true;
    final httpClient = MockClient((_) {
      if (++requests == 1) sent.complete();
      return response.future;
    });
    addTearDown(httpClient.close);
    final provider = OpenAiCompatibleUnreadSummaryProvider(
      serverBaseUri: Uri.parse('https://example.invalid'),
      model: 'fake',
      httpClient: httpClient,
      isAvailable: () => available,
      transientRetryDelays: const [Duration.zero],
    );
    final rejected = expectLater(
      provider.complete(_providerRequest()),
      throwsA(isA<UnreadChatSummaryUnavailable>()),
    );
    await sent.future;
    available = false;
    response.complete(http.Response('Unavailable', 503));
    await rejected;
    expect(requests, 1);
  });

  test('Apple provider does not retry after invalidation', () async {
    final response = Completer<Object?>();
    var requests = 0;
    var available = true;
    final provider = ApplePccUnreadSummaryProvider(
      api: ApplePccApi(
        invokeMethod: (_, _) {
          requests++;
          return response.future;
        },
      ),
      isAvailable: () => available,
      transientRetryDelays: const [Duration.zero],
    );
    final rejected = expectLater(
      provider.complete(_providerRequest()),
      throwsA(isA<UnreadChatSummaryUnavailable>()),
    );
    expect(requests, 1);
    available = false;
    response.completeError(PlatformException(code: 'pcc_busy'));
    await rejected;
    expect(requests, 1);
  });

  testWidgets('retry uses current model and prompt and honors opt-out', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      AiSettingsController.enabledPreferenceKey: true,
    });
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);
    final settings = AiSettingsController(
      preferences,
      pccApi: ApplePccApi(
        invokeMethod: (_, _) async => {
          'sdkAvailable': true,
          'available': true,
          'contextSize': 32768,
        },
      ),
      secureRead: (_) async => null,
      secureWrite: (_, _) async {},
    );
    addTearDown(settings.dispose);
    await settings.initialize();

    final calls = <(AiModelCandidateKind, String)>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppColors.light]),
        builder: (_, child) =>
            ChangeNotifierProvider.value(value: theme, child: child),
        home: UnreadChatSummaryView(
          snapshot: _snapshot(),
          settings: settings,
          isChatAvailable: () => true,
          summarize: (configuration, guidance, _, _) async {
            calls.add((configuration.candidate.kind, guidance));
            throw StateError('Simulated failure');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, [(AiModelCandidateKind.applePcc, settings.aiSummaryPrompt)]);

    await settings.setFeatureModelCandidate(
      AiFeature.summary,
      AiSettingsController.telegramCocoonModelCandidateId,
    );
    await settings.setAiSummaryPrompt('Focus on decisions.');
    final retry = find.text(AppStrings.t(AppStringKeys.aiSummaryRetry));
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(calls, hasLength(2));
    expect(calls.last, (
      AiModelCandidateKind.telegramCocoon,
      'Focus on decisions.',
    ));

    await settings.setEnabled(false);
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(calls, hasLength(2));
  });
}

UnreadChatRangeSnapshot _snapshot() => UnreadChatRangeSnapshot(
  chatId: 1,
  accountSlot: 0,
  lastReadInboxId: 10,
  unreadCount: 100,
  upperMessageId: 200,
  capturedAt: DateTime.utc(2026, 11, 28),
);

class _RecordingProvider implements UnreadChatSummaryProvider {
  final stages = <UnreadChatSummaryStage>[];

  @override
  Future<Map<String, dynamic>> complete(
    UnreadChatSummaryProviderRequest request,
  ) async {
    stages.add(request.stage);
    return {
      'title': 'A grounded summary',
      'overview': 'The message describes a decision.',
      'overview_evidence_ids': request.allowedEvidenceIds.toList(),
    };
  }
}

UnreadChatSummaryProviderRequest _providerRequest() =>
    UnreadChatSummaryProviderRequest(
      stage: UnreadChatSummaryStage.chunk,
      trustedInstructions: 'Summarize.',
      allowedEvidenceIds: const {'m200'},
      payload: const {'text': 'Test data'},
    );
