//
//  chat_list_connection_status_test.dart
//
//  The chat list header's connection status line: the dot keeps its size and
//  the word beside it shrinks to an ellipsis. Without the flexible label the
//  row overflowed the header — the split shell's sidebar at 200% text is the
//  narrow case that reported it (a 194pt column, label wider than the slot).
//

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  // The header column the split shell's sidebar gives the status line. The
  // test font is wide, so the label overflows it without the flexible word.
  const columnWidth = 194.0;
  for (final status in ChatListConnectionStatus.values) {
    testWidgets(
      'connection status ${status.name} ellipsizes instead of overflowing',
      (tester) async {
        await _pump(tester, status: status, width: columnWidth);
        expect(tester.takeException(), isNull);
        final label = find.byKey(ChatListConnectionStatusView.labelKey);
        expect(label, findsOneWidget);
        expect(tester.widget<Text>(label).maxLines, 1);
        expect(tester.widget<Text>(label).overflow, TextOverflow.ellipsis);
        // The word stays inside the header column instead of painting past it.
        final column = tester.getRect(
          find.byType(ChatListConnectionStatusView),
        );
        expect(tester.getRect(label).right, lessThanOrEqualTo(column.right));
        expect(tester.getSize(label).width, lessThanOrEqualTo(columnWidth));
        // The dot keeps its size; only the word gives way.
        expect(
          tester.getSize(find.byKey(ChatListConnectionStatusView.indicatorKey)),
          Size.square(
            status == ChatListConnectionStatus.connecting
                ? AppMetric.onlineDot + 2
                : AppMetric.onlineDot,
          ),
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('a short status keeps its full label', (tester) async {
    await _pump(tester, status: ChatListConnectionStatus.online, width: 900);
    final label = find.byKey(ChatListConnectionStatusView.labelKey);
    expect(tester.getSize(label).width, greaterThanOrEqualTo(20));
    expect(tester.widget<Text>(label).data, 'online');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required ChatListConnectionStatus status,
  required double width,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(extensions: [AppColors.light]),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: ChatListConnectionStatusView(status: status),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // The connecting state's spinner never settles, so one layout frame is the
  // whole contract here.
  await tester.pump();
}
