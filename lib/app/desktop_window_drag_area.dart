import 'package:flutter/widgets.dart';

import 'desktop_window_drag_area_stub.dart'
    if (dart.library.io) 'desktop_window_drag_area_io.dart'
    as implementation;

/// Adds native window dragging on supported desktop platforms while remaining
/// safe to import from mobile and web builds.
Widget desktopWindowDragArea({required Widget child}) =>
    implementation.desktopWindowDragArea(child: child);
