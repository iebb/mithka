import 'dart:math' as math;
import 'dart:ui';

/// Telegram Desktop keeps ordinary chat media inside a 430 x 430 logical-pixel
/// box and reserves at least 100 logical pixels for either preview dimension.
const double telegramDesktopMediaPreviewMaxSide = 430;
const double telegramDesktopMediaPreviewMinSide = 100;

class MediaPreviewGeometry {
  const MediaPreviewGeometry({
    required this.contentSize,
    required this.frameSize,
  });

  /// Aspect-preserving source size, never enlarged beyond its source pixels.
  final Size contentSize;

  /// Stable layout box. Very small or extremely narrow media can use a
  /// low-resolution blurred fill around [contentSize].
  final Size frameSize;

  bool get needsBlurredFill =>
      (contentSize.width - frameSize.width).abs() > 0.5 ||
      (contentSize.height - frameSize.height).abs() > 0.5;
}

/// Mirrors Telegram Desktop's photo-preview geometry at Flutter logical-pixel
/// scale: downscale into the fixed media box, downscale again for a narrow chat
/// pane, never upscale the source, then enforce a small stable layout box.
MediaPreviewGeometry telegramDesktopMediaPreviewGeometry({
  required int? sourceWidth,
  required int? sourceHeight,
  required double availableWidth,
}) {
  final available = availableWidth.isFinite && availableWidth > 0
      ? math.min(availableWidth, telegramDesktopMediaPreviewMaxSide)
      : telegramDesktopMediaPreviewMaxSide;
  final boundedAvailable = math.max(1.0, available);
  final width = sourceWidth ?? 0;
  final height = sourceHeight ?? 0;
  if (width <= 0 || height <= 0) {
    final fallback = Size.square(boundedAvailable);
    return MediaPreviewGeometry(contentSize: fallback, frameSize: fallback);
  }

  final downscale = math.min(
    1.0,
    math.min(
      telegramDesktopMediaPreviewMaxSide / width,
      telegramDesktopMediaPreviewMaxSide / height,
    ),
  );
  var contentWidth = width * downscale;
  var contentHeight = height * downscale;
  final paneScale = math.min(
    1.0,
    math.min(boundedAvailable / contentWidth, boundedAvailable / contentHeight),
  );
  contentWidth = math.max(1.0, contentWidth * paneScale);
  contentHeight = math.max(1.0, contentHeight * paneScale);

  final minimum = math.min(
    telegramDesktopMediaPreviewMinSide,
    boundedAvailable,
  );
  final content = Size(contentWidth, contentHeight);
  final frame = Size(
    math.max(contentWidth, minimum),
    math.max(contentHeight, minimum),
  );
  return MediaPreviewGeometry(contentSize: content, frameSize: frame);
}
