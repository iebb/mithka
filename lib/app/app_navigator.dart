import 'package:flutter/widgets.dart';

import '../components/full_page_back_swipe.dart';
import '../theme/app_motion.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

const double _maximumBackSwipeScrimOpacity = 0.16;

/// The shared route for app-level conversation surfaces.
///
/// Its controller is also the single source of truth for a full-page back
/// swipe, so the navigator can paint the real previous route as soon as the
/// current page starts moving.
class AppChatPageRoute<T> extends PageRoute<T>
    implements FullPageBackSwipeDriver {
  AppChatPageRoute({
    required this.builder,
    super.settings,
    super.requestFocus,
    this.maintainState = true,
  }) : super(allowSnapshotting: false);

  final WidgetBuilder builder;

  @override
  final bool maintainState;

  NavigatorState? _gestureNavigator;
  AnimationController? _gestureController;
  AnimationStatusListener? _gestureStatusListener;
  bool _fullPageBackSwipeActive = false;

  @override
  Duration get transitionDuration => AppMotion.route;

  @override
  Duration get reverseTransitionDuration => AppMotion.routeReverse;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get canStartFullPageBackSwipe =>
      !_fullPageBackSwipeActive &&
      popGestureEnabled &&
      (controller?.isCompleted ?? false);

  @override
  bool startFullPageBackSwipe() {
    final animationController = controller;
    final routeNavigator = navigator;
    if (!canStartFullPageBackSwipe ||
        animationController == null ||
        routeNavigator == null) {
      return false;
    }
    animationController.stop();
    _fullPageBackSwipeActive = true;
    _gestureNavigator = routeNavigator;
    _gestureController = animationController;
    routeNavigator.didStartUserGesture();
    return true;
  }

  @override
  void updateFullPageBackSwipe(double progress) {
    if (!_fullPageBackSwipeActive || !isCurrent) return;
    controller?.value = 1 - progress.clamp(0.0, 1.0);
  }

  @override
  void cancelFullPageBackSwipe() {
    final animationController = _gestureController;
    if (!_fullPageBackSwipeActive || animationController == null) return;
    final restoreRoute = isCurrent || isActive;
    final target = restoreRoute ? 1.0 : 0.0;
    final distance = (target - animationController.value).abs();
    if (restoreRoute) {
      animationController.animateTo(
        target,
        duration: _settleDuration(distance),
        curve: AppMotion.standard,
      );
    } else {
      animationController.animateBack(
        target,
        duration: _settleDuration(distance),
        curve: AppMotion.standard,
      );
    }
    _finishGestureWhenSettled(animationController);
  }

  @override
  void commitFullPageBackSwipe(VoidCallback? beforePop) {
    final animationController = _gestureController;
    final routeNavigator = _gestureNavigator;
    if (!_fullPageBackSwipeActive ||
        animationController == null ||
        routeNavigator == null) {
      return;
    }
    if (!isCurrent ||
        willHandlePopInternally ||
        popDisposition != RoutePopDisposition.pop) {
      cancelFullPageBackSwipe();
      return;
    }
    final distance = animationController.value;
    try {
      beforePop?.call();
      routeNavigator.pop<T>();
    } catch (_) {
      cancelFullPageBackSwipe();
      rethrow;
    }
    if (animationController.isAnimating) {
      animationController.animateBack(
        0,
        duration: _settleDuration(distance),
        curve: AppMotion.standard,
      );
    }
    _finishGestureWhenSettled(animationController);
  }

  Duration _settleDuration(double distance) =>
      Duration(milliseconds: (120 + 100 * distance.clamp(0.0, 1.0)).round());

  void _finishGestureWhenSettled(AnimationController animationController) {
    final existingListener = _gestureStatusListener;
    if (existingListener != null) {
      animationController.removeStatusListener(existingListener);
    }
    if (!animationController.isAnimating) {
      _finishFullPageBackSwipe();
      return;
    }
    late final AnimationStatusListener listener;
    listener = (status) {
      if (status != AnimationStatus.completed &&
          status != AnimationStatus.dismissed) {
        return;
      }
      animationController.removeStatusListener(listener);
      if (identical(_gestureStatusListener, listener)) {
        _gestureStatusListener = null;
      }
      _finishFullPageBackSwipe();
    };
    _gestureStatusListener = listener;
    animationController.addStatusListener(listener);
  }

  void _finishFullPageBackSwipe() {
    if (!_fullPageBackSwipeActive) return;
    final listener = _gestureStatusListener;
    final animationController = _gestureController;
    if (listener != null && animationController != null) {
      animationController.removeStatusListener(listener);
    }
    _gestureStatusListener = null;
    _gestureController = null;
    _fullPageBackSwipeActive = false;
    final routeNavigator = _gestureNavigator;
    _gestureNavigator = null;
    if (routeNavigator?.mounted ?? false) {
      routeNavigator!.didStopUserGesture();
    }
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: builder(context),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (AppMotion.usesInPlaceDesktopNavigation(context)) {
      return AppMotion.desktopRouteSurface(context, child);
    }
    if (AppMotion.isReduced(context) && !_fullPageBackSwipeActive) {
      return child;
    }
    final leaving = _fullPageBackSwipeActive;
    if (leaving) {
      final effectiveAnimation = popGestureInProgress
          ? animation
          : CurvedAnimation(
              parent: animation,
              curve: AppMotion.standard,
              reverseCurve: AppMotion.accelerate,
            );
      return Stack(
        fit: StackFit.expand,
        children: [
          FadeTransition(
            opacity: Tween<double>(
              begin: 0,
              end: _maximumBackSwipeScrimOpacity,
            ).animate(effectiveAnimation),
            child: const IgnorePointer(
              child: ColoredBox(color: Color(0xFF000000)),
            ),
          ),
          SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(effectiveAnimation),
            transformHitTests: false,
            child: child,
          ),
        ],
      );
    }

    final entrance = CurvedAnimation(
      parent: animation,
      curve: AppMotion.standard,
      reverseCurve: AppMotion.accelerate,
    );
    final covered = CurvedAnimation(
      parent: secondaryAnimation,
      curve: AppMotion.standard,
      reverseCurve: AppMotion.accelerate,
    );
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.96).animate(covered),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(-0.018, 0),
        ).animate(covered),
        transformHitTests: false,
        child: _EntranceFade(
          animation: entrance,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.045, 0),
              end: Offset.zero,
            ).animate(entrance),
            transformHitTests: false,
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _finishFullPageBackSwipe();
    super.dispose();
  }

  @override
  String get debugLabel => '${super.debugLabel}(${settings.name})';
}

/// Fades a conversation in as it arrives and holds it fully opaque as it leaves.
///
/// Replaying the arrival fade in reverse kept a full-screen [OpacityLayer] alive
/// for the whole 240 ms pop, at an alpha below 255 on every frame. An [Opacity]
/// over a group of widgets costs an offscreen buffer plus a render target switch
/// (see the [Opacity] docs), and a pop is exactly when the chat list underneath
/// is re-rasterizing itself. At 1.0 `RenderOpacity` paints its child directly
/// and builds no opacity layer at all, so the departure becomes a plain slide.
///
/// The value a completed route starts its reverse at is 1.0, which is also the
/// value this holds it at, so nothing jumps when a pop begins — including an
/// interactive one, where the page now stays crisp while it follows the finger.
/// The `covered` dim in `buildTransitions` cannot do the same: it sits at 0.96
/// while a conversation is on top, so pinning it would brighten the returning
/// page in a single frame.
class _EntranceFade extends AnimatedWidget {
  const _EntranceFade({
    required Animation<double> animation,
    required this.child,
  }) : super(listenable: animation);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final entrance = listenable as Animation<double>;
    final leaving = switch (entrance.status) {
      AnimationStatus.reverse || AnimationStatus.dismissed => true,
      AnimationStatus.forward || AnimationStatus.completed => false,
    };
    return Opacity(
      opacity: leaving ? 1.0 : 0.92 + 0.08 * entrance.value,
      child: child,
    );
  }
}

Future<T?> pushAppChatRoute<T>(BuildContext context, Route<T> route) {
  final navigator =
      appNavigatorKey.currentState ??
      Navigator.of(context, rootNavigator: true);
  return navigator.push(route);
}

/// Replaces the current conversation route. If the caller is still on a
/// tab-local utility page (for example the create-group form), close that page
/// before opening the conversation in the app-level chat navigator.
Future<T?> replaceWithAppChatRoute<T, TO>(
  BuildContext context,
  Route<T> route, {
  TO? result,
}) {
  final sourceNavigator = Navigator.of(context);
  final rootNavigator =
      appNavigatorKey.currentState ??
      Navigator.of(context, rootNavigator: true);
  if (identical(sourceNavigator, rootNavigator)) {
    // A pane can share the root navigator without owning its route. Keep the
    // shell underneath the conversation, including roots with local history.
    if (ModalRoute.of(context)?.isFirst != false) {
      return rootNavigator.push<T>(route);
    }
    return sourceNavigator.pushReplacement<T, TO>(route, result: result);
  }
  if (sourceNavigator.canPop()) sourceNavigator.pop<TO>(result);
  return rootNavigator.push<T>(route);
}
