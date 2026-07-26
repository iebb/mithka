import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('video controls use the owned slider renderer', () {
    final appSource = File(
      'lib/chat/video_player_view.dart',
    ).readAsStringSync();
    final source = File(
      'packages/mithka_video_player/lib/src/video_slider.dart',
    ).readAsStringSync();

    expect(appSource, contains('MithkaVideoSlider('));
    expect(source, contains('class MithkaVideoSlider'));
    expect(source, contains('CustomPaint('));
    expect(source, isNot(contains('SliderTheme(')));
    expect(source, isNot(contains('child: Slider(')));
  });
}
