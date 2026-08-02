import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/app_press_ripple.dart';

void main() {
  testWidgets('press ripple appears immediately and fades after release', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: AppPressRipple(
            child: SizedBox(
              key: ValueKey('press-target'),
              width: 240,
              height: 64,
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('press-target'))),
    );
    await tester.pump(const Duration(milliseconds: 32));

    expect(find.byKey(AppPressRipple.rippleLayerKey), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byKey(AppPressRipple.rippleLayerKey), findsNothing);
  });

  testWidgets('press ripple cancels once a scroll or swipe starts', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: AppPressRipple(
            child: SizedBox(
              key: ValueKey('drag-target'),
              width: 240,
              height: 64,
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('drag-target'))),
    );
    await tester.pump(const Duration(milliseconds: 32));
    await gesture.moveBy(const Offset(20, 0));
    await tester.pumpAndSettle();

    expect(find.byKey(AppPressRipple.rippleLayerKey), findsNothing);

    await gesture.up();
  });

  testWidgets('late pointer up after disposal is ignored', (tester) async {
    var showRipple = true;
    late StateSetter rebuild;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return Center(
              child: showRipple
                  ? const AppPressRipple(
                      child: SizedBox(
                        key: ValueKey('disposed-press-target'),
                        width: 240,
                        height: 64,
                      ),
                    )
                  : const SizedBox.shrink(),
            );
          },
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('disposed-press-target'))),
    );
    await tester.pump();

    rebuild(() => showRipple = false);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
