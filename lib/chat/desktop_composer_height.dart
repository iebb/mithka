import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

const desktopComposerMinimumCanvasHeight = 80.0;
const desktopComposerDefaultCanvasHeight = 112.0;
const desktopComposerMaximumCanvasHeight = 360.0;

double desktopComposerCanvasMaximumForViewport(double viewportHeight) =>
    math.max(
      desktopComposerMinimumCanvasHeight,
      math.min(desktopComposerMaximumCanvasHeight, viewportHeight * 0.55),
    );

double clampDesktopComposerCanvasHeight(
  double requested, {
  required double viewportHeight,
}) => requested.clamp(
  desktopComposerMinimumCanvasHeight,
  desktopComposerCanvasMaximumForViewport(viewportHeight),
);

double desktopComposerCanvasHeightAfterDrag({
  required double currentHeight,
  required double verticalDelta,
  required double viewportHeight,
}) => clampDesktopComposerCanvasHeight(
  currentHeight - verticalDelta,
  viewportHeight: viewportHeight,
);

String desktopComposerHeightPreferenceKey({
  required int accountSlot,
  required int chatId,
}) => 'desktop.composer.height.v1.$accountSlot.$chatId';

typedef DesktopComposerHeightLoader = Future<double?> Function(String key);
typedef DesktopComposerHeightSaver =
    Future<void> Function(String key, double height);

abstract final class DesktopComposerHeightStore {
  static Future<double?> load(String key) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getDouble(key);
    } on Object {
      return null;
    }
  }

  static Future<void> save(String key, double height) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setDouble(key, height);
    } on Object {
      // A missing preferences plugin must never make the composer unusable.
    }
  }
}
