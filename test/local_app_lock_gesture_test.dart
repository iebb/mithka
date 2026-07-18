import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/security/local_app_lock_views.dart';

void main() {
  testWidgets('gesture grid inserts a skipped middle node', (tester) async {
    List<int>? completed;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            child: GesturePatternPad(onCompleted: (value) => completed = value),
          ),
        ),
      ),
    );

    final rect = tester.getRect(find.byType(GesturePatternPad));
    final cell = rect.width / 4;
    final gesture = await tester.startGesture(
      Offset(rect.left + cell, rect.top + cell),
    );
    await gesture.moveTo(Offset(rect.left + cell * 3, rect.top + cell));
    await gesture.up();
    await tester.pump();

    expect(completed, [0, 1, 2]);
  });
}
