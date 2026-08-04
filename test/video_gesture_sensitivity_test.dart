import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/chat/video_player_view.dart').readAsStringSync();

  test('vertical volume and brightness gestures use a reduced sensitivity', () {
    expect(source, contains('const _verticalGestureSensitivity = 0.5;'));
    expect(
      RegExp(
        r'delta\.dy / size\.height \* _verticalGestureSensitivity',
      ).allMatches(source),
      hasLength(2),
    );
  });
}
