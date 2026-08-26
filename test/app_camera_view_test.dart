import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/media/app_camera_view.dart';

void main() {
  test('camera retries after returning from permission settings', () {
    expect(appCameraShouldRetryOnResume(recording: false), isTrue);
    expect(appCameraShouldRetryOnResume(recording: true), isFalse);
  });
}
