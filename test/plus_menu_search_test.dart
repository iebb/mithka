import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';

import 'support/l10n_fixtures.dart';

/// PlusMenu's first item: the exteraless-parity search entry that jumps
/// straight to the search surface.
void main() {
  setUpAll(() => L10nFixtures.load().install());

  Future<void> pumpMenu(WidgetTester tester) async {
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
        home: Scaffold(body: PlusMenu(onSelect: (_) {})),
      ),
    );
    await tester.pump();
  }

  testWidgets('search is the first plus-menu item and taps report it', (
    tester,
  ) async {
    // Failing-first: the menu began at 扫描二维码; the search jump did not
    // exist. The first row must now be the search entry, above QR.
    await pumpMenu(tester);
    expect(find.byType(PlusMenu), findsOneWidget);

    final selected = <String>[];
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
        home: Scaffold(body: PlusMenu(onSelect: selected.add)),
      ),
    );
    await tester.pump();

    final rows = find.byType(GestureDetector);
    expect(rows, findsWidgets);
    await tester.tap(find.text('Search'));
    expect(selected, isNotEmpty);
    // The reported label is the search key the handler switches on.
    expect(selected.single, 'topicChatSearch');
  });

  testWidgets('search row renders above the QR row', (tester) async {
    await pumpMenu(tester);
    final searchRect = tester.getTopLeft(find.text('Search'));
    final qrRect = tester.getTopLeft(find.text('Scan QR Code'));
    expect(searchRect.dy, lessThan(qrRect.dy));
  });

  testWidgets('community renders second, right after search', (tester) async {
    // The user's ordering: search first, community immediately after it,
    // ahead of every create action (it used to append last).
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
        home: Scaffold(body: PlusMenu(onSelect: (_) {}, showCommunities: true)),
      ),
    );
    await tester.pump();

    final searchRect = tester.getTopLeft(find.text('Search'));
    final communityRect = tester.getTopLeft(find.text('Community'));
    expect(
      searchRect.dy,
      lessThan(communityRect.dy),
      reason: 'search stays first',
    );
    // Community is the SECOND row: below search, above the QR entry.
    final qrRect = tester.getTopLeft(find.text('Scan QR Code'));
    expect(
      communityRect.dy,
      lessThan(qrRect.dy),
      reason: 'community sits between search and the create actions',
    );
  });
}
