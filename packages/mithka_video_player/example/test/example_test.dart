import 'package:flutter_test/flutter_test.dart';
import 'package:mithka_video_player_example/main.dart';

void main() {
  test('example uses a secure network video source', () {
    expect(Uri.parse(sampleVideo).scheme, 'https');
  });
}
