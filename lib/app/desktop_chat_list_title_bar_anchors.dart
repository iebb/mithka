import 'package:flutter/widgets.dart';

/// Shared compositor anchors between the persistent desktop title bar and
/// chat-list-owned menus rendered in the root Navigator overlay.
abstract final class DesktopChatListTitleBarAnchors {
  static final LayerLink add = LayerLink();
}
