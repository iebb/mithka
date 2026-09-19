import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/terms_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> openSheet(
    WidgetTester tester, {
    required Future<void> Function() onAccept,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    showTelegramTermsSheet(context, onAccept: onAccept),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    // The sheet content is taller than the default test surface.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder acceptButton() => find.descendant(
    of: find.byKey(termsAcceptButtonKey),
    matching: find.byType(GestureDetector),
  );

  void tapAccept(WidgetTester tester) =>
      tester.widget<GestureDetector>(acceptButton()).onTap!();

  testWidgets('accept button resets its spinner when onAccept throws', (
    tester,
  ) async {
    var attempts = 0;
    final gate = Completer<void>();
    await openSheet(
      tester,
      onAccept: () async {
        attempts++;
        if (attempts == 1) {
          await gate.future;
          throw StateError('network down');
        }
      },
    );

    expect(acceptButton(), findsOneWidget);
    tapAccept(tester);
    await tester.pump();
    // While the first attempt runs the spinner replaces the label.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // The failure must still reset the button for a retry.
    gate.complete();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);

    tapAccept(tester);
    await tester.pumpAndSettle();

    expect(attempts, 2);
  });
}
