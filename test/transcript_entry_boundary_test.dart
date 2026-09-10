import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/transcript_entry_boundary.dart';

void main() {
  testWidgets('viewport tracking remains bounded as long history is scrolled', (
    tester,
  ) async {
    final mounted = <int, RenderBox>{};
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ListView.builder(
          controller: controller,
          itemExtent: 60,
          itemCount: 2000,
          itemBuilder: (context, index) => TranscriptEntryBoundary(
            messageId: index,
            mountedEntries: mounted,
            child: Text('Message $index'),
          ),
        ),
      ),
    );
    expect(mounted, contains(0));
    expect(mounted.length, lessThan(40));
    controller.jumpTo(60000);
    await tester.pump();
    expect(mounted, isNot(contains(0)));
    expect(mounted, contains(1000));
    expect(mounted.length, lessThan(40));
    expect(mounted.values.every((box) => box.attached), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(mounted, isEmpty);
  });
}
