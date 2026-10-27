//
//  scaled_app_view.dart
//
//  Applies the interface-size preference to a whole window: the subtree lays
//  out in a virtual viewport of `size / interfaceScale` and is scaled back up,
//  so geometry and text grow together.
//

import 'package:flutter/widgets.dart';

import '../components/keyboard_dismiss_on_tap.dart';
import '../platform/adaptive_platform.dart';
import '../theme/content_size.dart';

class ScaledAppView extends StatelessWidget {
  const ScaledAppView({
    super.key,
    required this.textScale,
    required this.interfaceScale,
    required this.child,
  });

  /// App content scale only; chrome shares the touch-floored OS scaler.
  final double textScale;
  final double interfaceScale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scale = interfaceScale;
    final virtualSize = media.size / scale;
    final scaledMedia = media.copyWith(
      // Floor the OS scaler once, before ContentSizeRoot captures it. Clamp
      // per font size so nonlinear accessibility growth remains intact; never
      // fold the app content scale into this window-wide/chrome scaler.
      textScaler: isTouchTargetPlatform()
          ? media.textScaler.clamp(minScaleFactor: 1.0)
          : media.textScaler,
      size: virtualSize,
      padding: media.padding / scale,
      viewPadding: media.viewPadding / scale,
      viewInsets: media.viewInsets / scale,
      systemGestureInsets: media.systemGestureInsets / scale,
    );

    return AppKeyboardDismissOnTap(
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: virtualSize.width,
          maxWidth: virtualSize.width,
          minHeight: virtualSize.height,
          maxHeight: virtualSize.height,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: virtualSize.width,
              height: virtualSize.height,
              child: MediaQuery(
                data: scaledMedia,
                child: ContentSizeRoot(appScale: textScale, child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
