import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/desktop_voice_message_controller.dart';

void main() {
  test('modified Space does not start voice recording', () {
    expect(
      desktopVoiceMessageAction(
        isSpace: true,
        isEscape: false,
        isKeyDown: true,
        isRecording: false,
        hasModifiers: true,
      ),
      DesktopVoiceMessageAction.none,
    );
    expect(
      desktopVoiceMessageAction(
        isSpace: false,
        isEscape: true,
        isKeyDown: true,
        isRecording: true,
        hasModifiers: true,
      ),
      DesktopVoiceMessageAction.none,
    );
  });

  test(
    'Space release cancels a pending held recording even with a modifier',
    () {
      expect(
        desktopVoiceMessageAction(
          isSpace: true,
          isEscape: false,
          isKeyDown: false,
          isRecording: false,
          spaceHeld: true,
          hasModifiers: true,
        ),
        DesktopVoiceMessageAction.stop,
      );
      expect(
        desktopVoiceMessageAction(
          isSpace: true,
          isEscape: false,
          isKeyDown: false,
          isRecording: true,
        ),
        DesktopVoiceMessageAction.none,
      );
    },
  );
  test('permission preparation resumes the held microphone press', () async {
    final permission = Completer<void>();
    const held = true;
    var starts = 0;

    final recording = prepareDesktopVoiceRecording(
      prepare: () => permission.future,
      shouldStart: () => held,
      start: () async => starts++,
    );

    await Future<void>.delayed(Duration.zero);
    expect(starts, 0);
    permission.complete();
    await recording;
    expect(starts, 1);
  });

  test(
    'releasing during the permission sheet cancels the pending start',
    () async {
      final permission = Completer<void>();
      var held = true;
      var starts = 0;

      final recording = prepareDesktopVoiceRecording(
        prepare: () => permission.future,
        shouldStart: () => held,
        start: () async => starts++,
      );

      held = false;
      permission.complete();
      await recording;
      expect(starts, 0);
    },
  );

  test('Space down starts a desktop voice recording', () {
    expect(
      desktopVoiceMessageAction(
        isSpace: true,
        isEscape: false,
        isKeyDown: true,
        isRecording: false,
      ),
      DesktopVoiceMessageAction.start,
    );
  });

  test('Space up stops an active desktop voice recording', () {
    expect(
      desktopVoiceMessageAction(
        isSpace: true,
        isEscape: false,
        isKeyDown: false,
        isRecording: true,
        spaceHeld: true,
      ),
      DesktopVoiceMessageAction.stop,
    );
  });

  test('Escape cancels without depending on recording state', () {
    expect(
      desktopVoiceMessageAction(
        isSpace: false,
        isEscape: true,
        isKeyDown: true,
        isRecording: false,
      ),
      DesktopVoiceMessageAction.cancel,
    );
    expect(
      desktopVoiceMessageAction(
        isSpace: false,
        isEscape: true,
        isKeyDown: true,
        isRecording: true,
      ),
      DesktopVoiceMessageAction.cancel,
    );
  });

  test('unrelated keys and key repeats are ignored', () {
    expect(
      desktopVoiceMessageAction(
        isSpace: false,
        isEscape: false,
        isKeyDown: true,
        isRecording: false,
      ),
      DesktopVoiceMessageAction.none,
    );
    expect(
      desktopVoiceMessageAction(
        isSpace: true,
        isEscape: false,
        isKeyDown: true,
        isRecording: true,
      ),
      DesktopVoiceMessageAction.none,
    );
  });
}
