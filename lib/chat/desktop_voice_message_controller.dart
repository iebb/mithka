/// Pure input mapping for the desktop voice-message hold interaction.
///
/// Keeping this separate from the recorder makes the important QQ-style
/// behavior testable without requesting microphone access from widget tests.
enum DesktopVoiceMessageAction { none, start, stop, cancel }

DesktopVoiceMessageAction desktopVoiceMessageAction({
  required bool isSpace,
  required bool isEscape,
  required bool isKeyDown,
  required bool isRecording,
}) {
  if (isEscape && isKeyDown) return DesktopVoiceMessageAction.cancel;
  if (!isSpace) return DesktopVoiceMessageAction.none;
  if (isKeyDown && !isRecording) return DesktopVoiceMessageAction.start;
  if (!isKeyDown && isRecording) return DesktopVoiceMessageAction.stop;
  return DesktopVoiceMessageAction.none;
}
