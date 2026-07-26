import 'package:flutter/widgets.dart';

const desktopVideoMinimumWindowSize = Size(420, 280);

Size preferredDesktopVideoWindowSize(int? width, int? height) {
  final aspect = width != null && height != null && width > 0 && height > 0
      ? (width / height).clamp(0.25, 4.0)
      : 16 / 9;
  const preferredWidth = 880.0;
  const maximumHeight = 720.0;
  final constrainedWidth = (maximumHeight * aspect).clamp(
    desktopVideoMinimumWindowSize.width,
    preferredWidth,
  );
  final constrainedHeight = (constrainedWidth / aspect).clamp(
    desktopVideoMinimumWindowSize.height,
    maximumHeight,
  );
  return Size(constrainedWidth, constrainedHeight);
}
