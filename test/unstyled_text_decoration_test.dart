//
//  material_ancestor_test.dart
//
//  Mithka's screens are Cupertino-rooted (CupertinoPageScaffold), which brings
//  no text style of their own, and neither MaterialApp nor MaterialPageRoute
//  supplies one. Every Text that omits a decoration then inherits Flutter's
//  yellow double-underline "unstyled" marker — it showed up across the desktop
//  search window's result rows.
//
//  Each window app therefore merges a decoration-free default text style over
//  its navigator. These tests pin that down at the mechanism level.
//

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TextStyle ambientStyle(WidgetTester tester, String probe) =>
    DefaultTextStyle.of(tester.element(find.text(probe))).style;

void main() {
  group('the bug this guards against', () {
    testWidgets('a bare Cupertino home inherits the unstyled decoration', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: CupertinoPageScaffold(child: Text('probe'))),
      );

      expect(
        ambientStyle(tester, 'probe').decoration,
        TextDecoration.underline,
        reason:
            'if this ever passes as none, Flutter changed the default '
            'and these tests can be simplified',
      );
    });

    testWidgets('a pushed MaterialPageRoute inherits it too', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const CupertinoPageScaffold(child: Text('pushed')),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(
        ambientStyle(tester, 'pushed').decoration,
        TextDecoration.underline,
      );
    });
  });

  group('the fix', () {
    testWidgets('merging a decoration-none default resets it', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DefaultTextStyle.merge(
            style: const TextStyle(decoration: TextDecoration.none),
            child: const CupertinoPageScaffold(child: Text('fixed')),
          ),
        ),
      );

      expect(ambientStyle(tester, 'fixed').decoration, TextDecoration.none);
    });

    testWidgets('it also covers routes pushed above it', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => DefaultTextStyle.merge(
            style: const TextStyle(decoration: TextDecoration.none),
            child: child ?? const SizedBox.shrink(),
          ),
          home: Builder(
            builder: (context) => CupertinoPageScaffold(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const CupertinoPageScaffold(child: Text('deep')),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(
        ambientStyle(tester, 'deep').decoration,
        TextDecoration.none,
        reason:
            'MaterialApp.builder wraps the navigator, so every route is '
            'covered — this is the shape each window app uses',
      );
    });
  });
}
