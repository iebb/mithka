/// Pure input mapping for the desktop voice-message hold interaction.
///
/// Keeping this separate from the recorder makes the important QQ-style
/// behavior testable without requesting microphone access from widget tests.
enum DesktopVoiceMessageAction { none, start, stop, cancel }

/// Waits for macOS microphone permission and recorder creation before starting
/// the press that requested it. Releasing while the system permission sheet is
/// open cancels that pending start instead of recording after the gesture ends.
Future<void> prepareDesktopVoiceRecording({
  required Future<void> Function() prepare,
  required bool Function() shouldStart,
  required Future<void> Function() start,
}) async {
  await prepare();
  if (!shouldStart()) return;
  await start();
}

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
