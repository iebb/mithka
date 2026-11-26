//
//  desktop_media_window_registry.dart
//
//  Remembers which independent window is showing which media file, so opening
//  the same photo or video twice raises the window that already has it instead
//  of stacking a second copy of the same content on screen.
//

class DesktopMediaWindowRegistry {
  final Map<Object, int> _windowsByMedia = {};
  final Set<Object> _opening = {};

  /// The window recorded for [mediaKey], if one was opened and not forgotten.
  /// A recorded window can still have been closed natively, so a caller treats
  /// this as a candidate to raise and falls back to opening a new one.
  int? windowFor(Object mediaKey) => _windowsByMedia[mediaKey];

  /// Whether a window for [mediaKey] is being created right now. A repeat click
  /// arrives long before the native window exists, and without this it would
  /// open its own.
  bool isOpening(Object mediaKey) => _opening.contains(mediaKey);

  void beginOpening(Object mediaKey) => _opening.add(mediaKey);

  /// Ends the in-flight state, recording [windowId] when one was created.
  void finishOpening(Object mediaKey, {int? windowId}) {
    _opening.remove(mediaKey);
    if (windowId != null) _windowsByMedia[mediaKey] = windowId;
  }

  void forget(Object mediaKey) => _windowsByMedia.remove(mediaKey);
}
