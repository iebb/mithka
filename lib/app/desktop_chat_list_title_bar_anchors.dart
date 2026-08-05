import 'package:flutter/widgets.dart';

/// Shared anchors between the persistent desktop title bar and chat-list-owned
/// menus rendered in the root Navigator overlay.
abstract final class DesktopChatListTitleBarAnchors {
  static final LayerLink add = LayerLink();

  /// The add button itself.
  ///
  /// The title bar is built inside its own Overlay, and a
  /// CompositedTransformFollower mounted in the root overlay resolved [add]
  /// with the right vertical offset but none horizontally — the menu landed
  /// against the window's left edge instead of under the button. Reading the
  /// button's global rect straight off its render object sidesteps the two
  /// overlays disagreeing about coordinate space.
  static final GlobalKey addButton = GlobalKey(
    debugLabel: 'desktop-title-bar-add-anchor',
  );

  /// Global rect of the add button, or null when the title bar is not mounted.
  static Rect? addButtonRect() {
    final context = addButton.currentContext;
    if (context == null) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }
}
