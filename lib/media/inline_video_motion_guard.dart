import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

/// Keeps Android's separate native video layer out of moving inline content.
///
/// A SurfaceView can trail its Flutter row during scrolling or a route gesture.
/// Show the existing still preview while moving or covered by another route,
/// then mount a fresh view at the settled position. The owner keeps its
/// player/decoder and playback position; this must not disable the device's
/// direct-surface compatibility workaround.
class InlineVideoMotionGuard extends StatelessWidget {
  const InlineVideoMotionGuard({
    super.key,
    required this.viewType,
    required this.child,
    this.placeholder = const SizedBox.shrink(),
  });

  final VideoViewType viewType;
  final Widget child;
  final Widget placeholder;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        viewType != VideoViewType.platformView) {
      return child;
    }
    final vertical = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    final horizontal = Scrollable.maybeOf(
      context,
      axis: Axis.horizontal,
    )?.position;
    final route = ModalRoute.of(context);
    final entrance = route?.animation;
    final covering = route?.secondaryAnimation;
    return AnimatedBuilder(
      animation: Listenable.merge([
        vertical?.isScrollingNotifier,
        horizontal?.isScrollingNotifier,
        entrance,
        covering,
      ]),
      child: child,
      builder: (context, child) {
        final obscuredOrMoving =
            // Popup routes (including comments) do not drive a page route's
            // secondaryAnimation. Keep their underlying SurfaceView detached
            // while the popup is current, even after its animation settles.
            (route != null && !route.isCurrent) ||
            (vertical?.isScrollingNotifier.value ?? false) ||
            (horizontal?.isScrollingNotifier.value ?? false) ||
            (entrance != null && !entrance.isCompleted) ||
            (covering != null && !covering.isDismissed);
        // Do not use Opacity/Offstage: the native SurfaceView must detach while
        // Flutter transforms its parent, not merely stop painting Dart content.
        return obscuredOrMoving ? placeholder : child!;
      },
    );
  }
}
