import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/unread_chat_summary_models.dart';
import 'package:mithka/chat/unread_chat_summary_service.dart';
import 'package:mithka/chat/unread_chat_summary_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('summary surface mirrors progress and preserves model language', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);
    final completion = Completer<UnreadChatSummary>();
    late UnreadChatSummaryProgressCallback reportProgress;
    final snapshot = UnreadChatRangeSnapshot(
      chatId: 1,
      accountSlot: 0,
      lastReadInboxId: 100,
      unreadCount: 1972,
      upperMessageId: 3000,
      capturedAt: DateTime(2026, 7, 19, 22, 18),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
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
          home: UnreadChatSummaryView(
            snapshot: snapshot,
            summarize: (onProgress) {
              reportProgress = onProgress;
              return completion.future;
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Summarizing 1972 unread messages'), findsOneWidget);
    expect(find.text('Reading unread messages…'), findsOneWidget);
    expect(find.text('Found 1972 unread messages'), findsOneWidget);

    reportProgress(
      const UnreadChatSummaryProgress(
        stage: UnreadChatSummaryProgressStage.loadingMessages,
        messageCount: 300,
      ),
    );
    await tester.pump();
    expect(find.text('Reading unread messages… 300 found'), findsOneWidget);

    reportProgress(
      const UnreadChatSummaryProgress(
        stage: UnreadChatSummaryProgressStage.summarizingChunks,
        completed: 1,
        total: 2,
        messageCount: 900,
      ),
    );
    await tester.pump();
    expect(find.text('Summarizing chunks in parallel · 1/2'), findsOneWidget);

    reportProgress(
      const UnreadChatSummaryProgress(
        stage: UnreadChatSummaryProgressStage.assemblingSummary,
        completed: 2,
        total: 2,
        messageCount: 900,
      ),
    );
    await tester.pump();
    expect(find.text('Assembling the summary…'), findsOneWidget);

    completion.complete(
      UnreadChatSummary(
        content: UnreadChatSummaryContent(
          title: '发布安排与群聊近况',
          overview: '这是未读消息的中文总结。',
          overviewEvidenceIds: const ['m200'],
          topics: [
            UnreadChatSummaryTopic(
              title: '发布时间讨论',
              summary: '成员讨论了发布时间。',
              evidenceIds: const ['m200', 'm201'],
              firstDate: 1752969600,
              lastDate: 1752971400,
            ),
          ],
          rant: UnreadChatSummaryItem(
            text: '消息很多，真正要拍板的只有发布时间。',
            evidenceIds: const ['m201'],
          ),
          highlights: [
            UnreadChatSummaryItem(
              text: '需要确认发布时间。',
              evidenceIds: const ['m201'],
            ),
          ],
          needsReply: const [],
          decisions: const [],
          actions: const [],
          questions: const [],
          uncertainties: const [],
        ),
        coverage: const UnreadChatSummaryCoverage(
          expectedUnreadCount: 1972,
          fetchedMessageCount: 1972,
          fetchedUnreadMessageCount: 1972,
          summarizedMessageCount: 1972,
          summarizedUnreadMessageCount: 1972,
          reachedReadBoundary: true,
          historyCapped: false,
          processingCapped: false,
          historyStalled: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('这是未读消息的中文总结。'), findsOneWidget);
    expect(find.text('发布安排与群聊近况'), findsOneWidget);
    expect(find.textContaining('发布时间讨论'), findsOneWidget);
    expect(find.text('成员讨论了发布时间。'), findsOneWidget);
    expect(find.textContaining('Processed 1972 messages'), findsOneWidget);
    expect(find.textContaining('AI take'), findsOneWidget);
    expect(find.textContaining('消息很多，真正要拍板的只有发布时间。'), findsOneWidget);
    expect(find.text('需要确认发布时间。'), findsOneWidget);
    expect(find.text('Assembling the summary…'), findsNothing);
  });

  testWidgets('failure surface shows actionable request diagnostics', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
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
          home: UnreadChatSummaryView(
            snapshot: UnreadChatRangeSnapshot(
              chatId: 1,
              accountSlot: 0,
              lastReadInboxId: 1,
              unreadCount: 2685,
              upperMessageId: 3000,
              capturedAt: DateTime(2026, 7, 20),
            ),
            summarize: (_) async => throw UnreadChatSummaryFailure(
              providerCode: 'apple_pcc',
              stage: 'summarizing_chunks',
              causes: const [
                UnreadChatSummaryFailureCause(
                  code: 'pcc_busy/request_in_progress',
                  message: 'The Apple model is busy.',
                ),
              ],
              sourceMessageCount: 2685,
              selectedMessageCount: 640,
              chunkCount: 5,
              successfulChunkCount: 0,
              contextWindowTokens: 32768,
              initialPromptTokenEstimate: 1180,
              reservedNonPayloadTokenEstimate: 3760,
              chunkTokenBudget: 7000,
              largestChunkTokenEstimate: 6880,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Technical details'), findsOneWidget);
    expect(find.textContaining('provider: apple_pcc'), findsOneWidget);
    expect(find.textContaining('chunks_succeeded: 0/5'), findsOneWidget);
    expect(find.textContaining('context_window_tokens: 32768'), findsOneWidget);
    expect(
      find.textContaining('initial_prompt_token_estimate: 1180'),
      findsOneWidget,
    );
    expect(
      find.textContaining('reserved_non_payload_tokens: 3760'),
      findsOneWidget,
    );
    expect(find.textContaining('pcc_busy/request_in_progress'), findsOneWidget);
  });
}
