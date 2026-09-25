import 'package:flutter/services.dart';

/// Bare-key controls must leave modified keystrokes to platform shortcuts.
bool keyboardModifiersPressed({bool allowShift = false}) {
  final keyboard = HardwareKeyboard.instance;
  return keyboard.isControlPressed ||
      keyboard.isMetaPressed ||
      keyboard.isAltPressed ||
      (!allowShift && keyboard.isShiftPressed);
}
