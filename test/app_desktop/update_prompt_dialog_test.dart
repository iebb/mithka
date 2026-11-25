//
//  update_prompt_dialog_test.dart
//
//  The update prompt is the app's own card: mark, title, the current → latest
//  pair, an optional note and two tall stacked actions — and it answers true
//  only for the confirm row.
//

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/update/update_prompt_dialog.dart';

import '../support/l10n_fixtures.dart';

void main() {
  setUpAll(() => L10nFixtures.load().install());

  /// Opens the prompt from a host button; every answer the dialog returns is
  /// appended to [answers].
  Future<void> openPrompt(
    WidgetTester tester, {
    String? note,
    required List<bool> answers,
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
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  final answer = await showUpdatePromptDialog(
                    context,
                    title: AppStrings.t(AppStringKeys.updateNewVersionFound),
                    current: '1.13.0',
                    latest: '1.14.0',
                    confirmText: AppStrings.t(AppStringKeys.updateAction),
                    note: note,
                  );
                  answers.add(answer);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('reads as a card: mark, title, version pair, stacked actions', (
    tester,
  ) async {
    await openPrompt(tester, answers: []);

    expect(find.text('New Version Available'), findsOneWidget);
    expect(find.text('1.13.0'), findsOneWidget);
    expect(find.text('1.14.0'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
    expect(find.byKey(const ValueKey('update-prompt-confirm')), findsOneWidget);
    expect(find.byKey(const ValueKey('update-prompt-cancel')), findsOneWidget);
    // Stacked, not side by side: the confirm row sits above the cancel row.
    final confirmY = tester
        .getTopLeft(find.byKey(const ValueKey('update-prompt-confirm')))
        .dy;
    final cancelY = tester
        .getTopLeft(find.byKey(const ValueKey('update-prompt-cancel')))
        .dy;
    expect(confirmY, lessThan(cancelY));
  });

  testWidgets('confirm answers true and cancel answers false', (tester) async {
    final answers = <bool>[];
    await openPrompt(tester, answers: answers);
    await tester.tap(find.byKey(const ValueKey('update-prompt-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('New Version Available'), findsNothing);
    expect(answers, [true]);

    await openPrompt(tester, answers: answers);
    await tester.tap(find.byKey(const ValueKey('update-prompt-cancel')));
    await tester.pumpAndSettle();
    expect(find.text('New Version Available'), findsNothing);
    expect(answers, [true, false]);
  });

  testWidgets('renders an optional note under the version pair', (
    tester,
  ) async {
    await openPrompt(
      tester,
      answers: [],
      note: 'This copy is managed by your system.',
    );
    expect(find.text('This copy is managed by your system.'), findsOneWidget);
  });
}
