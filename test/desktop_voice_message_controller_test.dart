import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/desktop_voice_message_controller.dart';

void main() {
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
}
