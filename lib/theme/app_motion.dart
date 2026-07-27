import 'package:flutter/material.dart';

/// Shared timing, easing, navigation, and scrolling behavior for Mithka.
///
/// Keeping these values in one place prevents screens, tabs, menus, and
/// dialogs from each inventing a slightly different motion language.
abstract final class AppMotion {
  static const Duration instant = Duration.zero;
  static const Duration quick = Duration(milliseconds: 140);
  static const Duration responsive = Duration(milliseconds: 190);
  static const Duration deliberate = Duration(milliseconds: 280);
  static const Duration route = Duration(milliseconds: 300);
  static const Duration routeReverse = Duration(milliseconds: 240);

  /// Smoothly decelerates without the abrupt stop of easeOutCubic.
  static const Curve standard = Cubic(0.20, 0.0, 0.0, 1.0);

  /// Used when content is leaving and should get out of the way quickly.
  static const Curve accelerate = Cubic(0.30, 0.0, 1.0, 1.0);

  /// A slightly more expressive arrival for floating and modal surfaces.
  static const Curve emphasized = Cubic(0.05, 0.70, 0.10, 1.0);

  static bool isReduced(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  static Duration duration(BuildContext context, Duration normal) =>
      isReduced(context) ? instant : normal;

  static Widget dialogTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (isReduced(context)) return child;
    final entrance = CurvedAnimation(
      parent: animation,
      curve: emphasized,
      reverseCurve: accelerate,
    );
    return FadeTransition(
      opacity: entrance,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1).animate(entrance),
        child: child,
      ),
    );
  }
}

/// Opens a native draggable modal sheet while applying Mithka's shared motion.
/// All other arguments intentionally match [showModalBottomSheet].
Future<T?> showAppModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  String? barrierLabel,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  Color? barrierColor,
  bool isScrollControlled = false,
  double scrollControlDisabledMaxHeightRatio = 9.0 / 16.0,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  bool useSafeArea = false,
  RouteSettings? routeSettings,
  AnimationController? transitionAnimationController,
  Offset? anchorPoint,
  AnimationStyle? sheetAnimationStyle,
  bool? requestFocus,
}) {
  final effectiveAnimationStyle =
      sheetAnimationStyle ??
      (AppMotion.isReduced(context)
          ? AnimationStyle.noAnimation
          : const AnimationStyle(
              curve: AppMotion.emphasized,
              reverseCurve: AppMotion.accelerate,
              duration: AppMotion.deliberate,
              reverseDuration: AppMotion.responsive,
            ));
  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    backgroundColor: backgroundColor,
    barrierLabel: barrierLabel,
    elevation: elevation,
    shape: shape,
    clipBehavior: clipBehavior,
    constraints: constraints,
    barrierColor: barrierColor,
    isScrollControlled: isScrollControlled,
    scrollControlDisabledMaxHeightRatio: scrollControlDisabledMaxHeightRatio,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: showDragHandle,
    useSafeArea: useSafeArea,
    routeSettings: routeSettings,
    transitionAnimationController: transitionAnimationController,
    anchorPoint: anchorPoint,
    sheetAnimationStyle: effectiveAnimationStyle,
    requestFocus: requestFocus,
  );
}

/// A consistent shared-axis transition for ordinary app routes.
///
/// Conversation routes keep their interactive full-page back gesture in
/// [AppChatPageRoute], but use the same timing and easing constants.
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Duration get transitionDuration => AppMotion.route;

  @override
  Duration get reverseTransitionDuration => AppMotion.routeReverse;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _buildAppPageTransition(
    context: context,
    animation: animation,
    secondaryAnimation: secondaryAnimation,
    child: child,
    fullscreenDialog: route.fullscreenDialog,
  );
}

/// A route for app-owned screens that would otherwise use PageRouteBuilder's
/// jump-cut default transition.
///
/// MaterialPageRoute keeps the platform navigation contract, including the
/// interactive native edge-back gesture on Apple platforms. The theme supplies
/// Mithka's transition elsewhere.
class AppPageRoute<T> extends MaterialPageRoute<T> {
  AppPageRoute({
    super.settings,
    super.requestFocus,
    required this.pageBuilder,
    super.maintainState = true,
    super.fullscreenDialog = false,
    super.allowSnapshotting = true,
    super.barrierDismissible = false,
    super.traversalEdgeBehavior,
    super.directionalTraversalEdgeBehavior,
  }) : super(
         builder: (context) => pageBuilder(
           context,
           kAlwaysCompleteAnimation,
           kAlwaysDismissedAnimation,
         ),
       );

  final RoutePageBuilder pageBuilder;

  @override
  Widget buildContent(BuildContext context) =>
      pageBuilder(context, animation!, secondaryAnimation!);

  @override
  Duration get transitionDuration => AppMotion.route;

  @override
  Duration get reverseTransitionDuration => AppMotion.routeReverse;
}

/// A compact fade route for pickers and visual editors where spatial motion
/// would imply a hierarchy that does not exist.
class AppFadePageRoute<T> extends PageRouteBuilder<T> {
  AppFadePageRoute({
    super.settings,
    super.requestFocus,
    required super.pageBuilder,
    super.opaque = true,
    super.barrierDismissible = false,
    super.barrierColor,
    super.barrierLabel,
    super.maintainState = true,
    super.fullscreenDialog = false,
    super.allowSnapshotting = true,
  }) : super(
         transitionDuration: AppMotion.responsive,
         reverseTransitionDuration: AppMotion.quick,
         transitionsBuilder: (context, animation, _, child) {
           if (AppMotion.isReduced(context)) return child;
           final entrance = CurvedAnimation(
             parent: animation,
             curve: AppMotion.standard,
             reverseCurve: AppMotion.accelerate,
           );
           return FadeTransition(opacity: entrance, child: child);
         },
       );
}

Widget _buildAppPageTransition({
  required BuildContext context,
  required Animation<double> animation,
  required Animation<double> secondaryAnimation,
  required Widget child,
  required bool fullscreenDialog,
}) {
  if (AppMotion.isReduced(context)) return child;

  final entering = CurvedAnimation(
    parent: animation,
    curve: AppMotion.standard,
    reverseCurve: AppMotion.accelerate,
  );
  final covered = CurvedAnimation(
    parent: secondaryAnimation,
    curve: AppMotion.standard,
    reverseCurve: AppMotion.accelerate,
  );

  if (fullscreenDialog) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.9, end: 1).animate(entering),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(entering),
        transformHitTests: false,
        child: child,
      ),
    );
  }

  return FadeTransition(
    opacity: Tween<double>(begin: 1, end: 0.96).animate(covered),
    child: SlideTransition(
      position: Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(-0.018, 0),
      ).animate(covered),
      transformHitTests: false,
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.92, end: 1).animate(entering),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.045, 0),
            end: Offset.zero,
          ).animate(entering),
          transformHitTests: false,
          child: child,
        ),
      ),
    ),
  );
}

/// Platform-adaptive scroll physics and native edge feedback.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();
}
