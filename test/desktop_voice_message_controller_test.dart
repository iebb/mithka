import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/desktop_voice_message_controller.dart';

void main() {
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
