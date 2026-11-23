//
//  desktop_child_window_startup.dart
//
//  Tells a child window that has closed from one that has not been shown yet.
//
//  The primary engine drops a child's registration once the window manager no
//  longer lists the window as active, which is how it learns that a window
//  was closed. On Linux a child is created hidden and closing one only hides
//  it, so the window manager reports a window that is still starting exactly
//  like one that was closed: registered, but not active. Treating the two
//  alike dropped every Linux child before it could ask the primary for its
//  TDLib transport, and the window stayed blank.
//

class DesktopChildWindowStartup {
  final Set<int> _awaitingFirstShow = {};

  /// [windowId] was just created and has not been shown yet.
  void begin(int windowId) => _awaitingFirstShow.add(windowId);

  /// [windowId] is gone; nothing is owed to it any more.
  void end(int windowId) => _awaitingFirstShow.remove(windowId);

  void clear() => _awaitingFirstShow.clear();

  /// The windows that are still alive: the ones the window manager reports as
  /// [active], plus every window that has not appeared in that list yet.
  ///
  /// A window stops being protected the first time it is reported active.
  /// From then on its absence means it was closed.
  Set<int> live(Iterable<int> active) {
    final live = active.toSet();
    _awaitingFirstShow.removeAll(live);
    return live..addAll(_awaitingFirstShow);
  }
}
