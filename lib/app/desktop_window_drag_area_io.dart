import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:multi_window_manager/multi_window_manager.dart';

Widget desktopWindowDragArea({required Widget child}) =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux
    ? DragToMoveArea(child: child)
    : child;
