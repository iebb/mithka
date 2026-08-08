//
//  desktop_media_window_registry.dart
//
//  Remembers which independent window is showing which media file, so opening
//  the same photo or video twice raises the window that already has it instead
//  of stacking a second copy of the same content on screen.
//

class DesktopMediaWindowRegistry {
  final Map<int, int> _windowsByMedia = {};
  final Set<int> _opening = {};

  /// The window recorded for [mediaId], if one was opened and not forgotten.
  /// A recorded window can still have been closed natively, so a caller treats
  /// this as a candidate to raise and falls back to opening a new one.
  int? windowFor(int mediaId) => _windowsByMedia[mediaId];

  /// Whether a window for [mediaId] is being created right now. A repeat click
  /// arrives long before the native window exists, and without this it would
  /// open its own.
  bool isOpening(int mediaId) => _opening.contains(mediaId);

  void beginOpening(int mediaId) => _opening.add(mediaId);

  /// Ends the in-flight state, recording [windowId] when one was created.
  void finishOpening(int mediaId, {int? windowId}) {
    _opening.remove(mediaId);
    if (windowId != null) _windowsByMedia[mediaId] = windowId;
  }

  void forget(int mediaId) => _windowsByMedia.remove(mediaId);
}
