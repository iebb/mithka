import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/voice_audio.dart';

void main() {
  test(
    'resumes only when an interruption ends with should-resume semantics',
    () {
      final policy = AudioInterruptionResumePolicy();

      policy.onBegin(
        AudioInterruptionEvent(true, AudioInterruptionType.unknown),
        wasPlaying: true,
      );
      expect(
        policy.onEnd(
          AudioInterruptionEvent(false, AudioInterruptionType.unknown),
        ),
        isFalse,
      );

      policy.onBegin(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
        wasPlaying: true,
      );
      expect(
        policy.onEnd(
          AudioInterruptionEvent(false, AudioInterruptionType.pause),
        ),
        isTrue,
      );
      expect(
        policy.onEnd(
          AudioInterruptionEvent(false, AudioInterruptionType.pause),
        ),
        isFalse,
      );
    },
  );

  test('ducking and manual clears never resume playback', () {
    final policy = AudioInterruptionResumePolicy();

    policy.onBegin(
      AudioInterruptionEvent(true, AudioInterruptionType.duck),
      wasPlaying: true,
    );
    expect(
      policy.onEnd(AudioInterruptionEvent(false, AudioInterruptionType.duck)),
      isFalse,
    );

    policy.onBegin(
      AudioInterruptionEvent(true, AudioInterruptionType.pause),
      wasPlaying: true,
    );
    policy.clear();
    expect(
      policy.onEnd(AudioInterruptionEvent(false, AudioInterruptionType.pause)),
      isFalse,
    );
  });
}
