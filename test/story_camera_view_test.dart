import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/moments/story_camera_view.dart';

void main() {
  test('camera retries after returning from permission settings', () {
    expect(storyCameraShouldRetryOnResume(recording: false), isTrue);
    expect(storyCameraShouldRetryOnResume(recording: true), isFalse);
  });
}
