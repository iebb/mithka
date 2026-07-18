import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/video_note_recorder_view.dart';

void main() {
  test('video-note recording gesture distinguishes lock and cancel', () {
    expect(
      videoNoteRecordGestureForDelta(dx: 0, dy: -71),
      VideoNoteRecordGesture.lock,
    );
    expect(
      videoNoteRecordGestureForDelta(dx: -91, dy: -100),
      VideoNoteRecordGesture.cancel,
    );
    expect(
      videoNoteRecordGestureForDelta(dx: -40, dy: -30),
      VideoNoteRecordGesture.continueRecording,
    );
  });
}
