import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('video controls use the owned slider renderer', () {
    final source = File('lib/chat/video_player_view.dart').readAsStringSync();

    expect(source, contains('class _OwnedVideoSlider'));
    expect(source, contains('CustomPaint('));
    expect(source, isNot(contains('SliderTheme(')));
    expect(source, isNot(contains('child: Slider(')));
  });
}
