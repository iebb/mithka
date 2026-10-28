import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/components/app_text_selection_toolbar.dart';

void main() {
  for (final direction in TextDirection.values) {
    testWidgets('selection overflow stays usable in $direction', (
      tester,
    ) async {
      final invoked = <int>[];
      await _pumpToolbar(
        tester,
        direction: direction,
        items: [
          for (var index = 0; index < 6; index++)
            ContextMenuButtonItem(
              label: 'Action $index',
              onPressed: () => invoked.add(index),
            ),
        ],
      );
      final more = find.byKey(StandardComponentType.moreButton.key);
      await tester.tap(more);
      await tester.pumpAndSettle();

      final back = find.byKey(StandardComponentType.backButton.key);
      final icon = tester.widget<Icon>(
        find.descendant(of: back, matching: find.byType(Icon)),
      );
      expect(
        icon.icon,
        direction == TextDirection.rtl
            ? HeroAppIcons.chevronRight.data
            : HeroAppIcons.chevronLeft.data,
      );
      for (final item in [back, find.text('Action 5')]) {
        final bounds = tester.getRect(item);
        expect(bounds.left, greaterThanOrEqualTo(8));
        expect(bounds.right, lessThanOrEqualTo(232));
        expect(bounds.top, greaterThanOrEqualTo(8));
        expect(bounds.bottom, lessThanOrEqualTo(632));
      }
      await tester.tap(find.text('Action 5'));
      expect(invoked, [5]);
      await tester.tap(back);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Action 0'));
      expect(invoked, [5, 0]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty selection actions show no toolbar controls', (
    tester,
  ) async {
    await _pumpToolbar(tester, items: const []);
    expect(find.byType(IconButton), findsNothing);
    expect(find.byType(TextSelectionToolbarTextButton), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpToolbar(
  WidgetTester tester, {
  required List<ContextMenuButtonItem> items,
  TextDirection direction = TextDirection.ltr,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(240, 640);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.android),
      home: Scaffold(
        body: Directionality(
          textDirection: direction,
          child: Builder(
            builder: (context) => AppTextSelectionToolbar.fromButtonItems(
              context: context,
              anchors: const TextSelectionToolbarAnchors(
                primaryAnchor: Offset(120, 320),
                secondaryAnchor: Offset(120, 340),
              ),
              items: items,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
