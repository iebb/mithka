import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/unread_chat_summary_models.dart';
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
            summarize: () => completion.future,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Summarizing 1972 unread messages'), findsOneWidget);
    expect(find.text('Thinking…'), findsOneWidget);
    expect(find.text('Found 1972 unread messages'), findsOneWidget);

    completion.complete(
      UnreadChatSummary(
        content: UnreadChatSummaryContent(
          overview: '这是未读消息的中文总结。',
          overviewEvidenceIds: const ['m200'],
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
    expect(find.text('需要确认发布时间。'), findsOneWidget);
    expect(find.text('Thinking…'), findsNothing);
  });
}
