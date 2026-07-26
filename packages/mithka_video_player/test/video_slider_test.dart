import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka_video_player/mithka_video_player.dart';

void main() {
  testWidgets('timeline maps taps across its usable width', (tester) async {
    double? changed;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 200,
            height: 30,
            child: MithkaVideoSlider(
              value: 0,
              trackHeight: 4,
              thumbRadius: 8,
              activeColor: const Color(0xFFFFFFFF),
              inactiveColor: const Color(0x44000000),
              onChanged: (value) => changed = value,
            ),
          ),
        ),
      ),
    );

    final rect = tester.getRect(find.byType(MithkaVideoSlider));
    await tester.tapAt(Offset(rect.left + rect.width / 2, rect.center.dy));
    expect(changed, closeTo(0.5, 0.01));
  });
}
