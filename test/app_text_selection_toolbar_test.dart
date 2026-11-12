import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/app_text_selection_toolbar.dart';

void main() {
  testWidgets(
    'only Apple and desktop platforms leave the Android-style toolbar',
    (tester) async {
      // Fork-only targets such as HarmonyOS's TargetPlatform.ohos fall
      // through like fuchsia does here.
      final items = [ContextMenuButtonItem(label: 'Copy', onPressed: () {})];
      await _pumpToolbar(
        tester,
        items: items,
        platform: TargetPlatform.fuchsia,
      );
      expect(find.byType(AppTextSelectionToolbar), findsOneWidget);

      await _pumpToolbar(tester, items: items, platform: TargetPlatform.iOS);
      expect(find.byType(AppTextSelectionToolbar), findsNothing);
    },
  );
}

Future<void> _pumpToolbar(
  WidgetTester tester, {
  required List<ContextMenuButtonItem> items,
  TextDirection direction = TextDirection.ltr,
  TargetPlatform platform = TargetPlatform.android,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(240, 640);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
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
