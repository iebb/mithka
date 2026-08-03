import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/theme/app_motion.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  test('app page routes use the shared navigation contract', () {
    final route = AppPageRoute<void>(
      fullscreenDialog: true,
      pageBuilder: (_, _, _) => const SizedBox.shrink(),
    );

    expect(route.transitionDuration, AppMotion.route);
    expect(route.reverseTransitionDuration, AppMotion.routeReverse);
    expect(route.fullscreenDialog, isTrue);

    final fadeRoute = AppFadePageRoute<void>(
      pageBuilder: (_, _, _) => const SizedBox.shrink(),
    );
    expect(fadeRoute.transitionDuration, AppMotion.responsive);
    expect(fadeRoute.reverseTransitionDuration, AppMotion.quick);
  });

  testWidgets('app page routes render without motion when it is disabled', (
    tester,
  ) async {
    const child = SizedBox(key: ValueKey('reduced-route-child'));
    late Widget transition;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Theme(
          data: ThemeData(platform: TargetPlatform.android),
          child: Builder(
            builder: (context) {
              final route = AppPageRoute<void>(pageBuilder: (_, _, _) => child);
              transition = const AppPageTransitionsBuilder().buildTransitions(
                route,
                context,
                const AlwaysStoppedAnimation<double>(0.4),
                const AlwaysStoppedAnimation<double>(0.2),
                child,
              );
              return transition;
            },
          ),
        ),
      ),
    );

    expect(identical(transition, child), isTrue);
    expect(find.byKey(const ValueKey('reduced-route-child')), findsOneWidget);
  });

  testWidgets(
    'desktop routes replace content in place on a continuously painted surface',
    (tester) async {
      const childKey = ValueKey('desktop-route-child');
      const background = Color(0xFF17324D);
      late Widget transition;

      await tester.pumpWidget(
        MaterialApp(
          themeAnimationDuration: Duration.zero,
          theme: ThemeData(
            platform: TargetPlatform.macOS,
            extensions: [AppColors.light.copyWith(background: background)],
          ),
          home: Builder(
            builder: (context) {
              const child = ColoredBox(key: childKey, color: Color(0xFF2A4D69));
              final route = AppPageRoute<void>(pageBuilder: (_, _, _) => child);
              transition = const AppPageTransitionsBuilder().buildTransitions(
                route,
                context,
                const AlwaysStoppedAnimation<double>(0.08),
                const AlwaysStoppedAnimation<double>(0.6),
                child,
              );
              return SizedBox.expand(child: transition);
            },
          ),
        ),
      );

      final surface = find.byKey(AppMotion.desktopRouteSurfaceKey);
      expect(surface, findsOneWidget);
      expect(tester.widget<ColoredBox>(surface).color, background);
      expect(tester.getRect(surface), tester.getRect(find.byKey(childKey)));
      expect(
        find.descendant(of: surface, matching: find.byType(SlideTransition)),
        findsNothing,
      );
      expect(
        find.descendant(of: surface, matching: find.byType(Opacity)),
        findsNothing,
      );
    },
  );

  testWidgets('scroll behavior preserves the platform physics chain', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        themeAnimationDuration: Duration.zero,
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final iOSPhysics = const AppScrollBehavior().getScrollPhysics(context);
    expect(iOSPhysics, isA<BouncingScrollPhysics>());
    expect(iOSPhysics.parent, isA<RangeMaintainingScrollPhysics>());

    await tester.pumpWidget(
      MaterialApp(
        themeAnimationDuration: Duration.zero,
        theme: ThemeData(platform: TargetPlatform.android),
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final androidPhysics = const AppScrollBehavior().getScrollPhysics(context);
    expect(androidPhysics, isA<ClampingScrollPhysics>());
    expect(androidPhysics.parent, isA<RangeMaintainingScrollPhysics>());
  });

  testWidgets('modal sheets use shared forward and reverse timing', (
    tester,
  ) async {
    final observer = _RouteObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) => GestureDetector(
            key: const ValueKey('open-sheet'),
            behavior: HitTestBehavior.opaque,
            onTap: () => showAppModalSheet<void>(
              context: context,
              builder: (_) => const SizedBox(height: 120),
            ),
            child: const SizedBox(width: 80, height: 80),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open-sheet')));
    await tester.pump();

    final route = observer.lastRoute;
    expect(route, isA<ModalBottomSheetRoute<void>>());
    final sheetRoute = route! as ModalBottomSheetRoute<void>;
    expect(sheetRoute.transitionDuration, AppMotion.deliberate);
    expect(sheetRoute.reverseTransitionDuration, AppMotion.responsive);
  });

  testWidgets('reduced motion removes route and sheet animation durations', (
    tester,
  ) async {
    final observer = _RouteObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Builder(
          builder: (context) => GestureDetector(
            key: const ValueKey('open-reduced-sheet'),
            behavior: HitTestBehavior.opaque,
            onTap: () => showAppModalSheet<void>(
              context: context,
              builder: (_) => const SizedBox(height: 120),
            ),
            child: const SizedBox(width: 80, height: 80),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open-reduced-sheet')));
    await tester.pump();

    final route = observer.lastRoute;
    expect(route, isA<ModalBottomSheetRoute<void>>());
    final sheetRoute = route! as ModalBottomSheetRoute<void>;
    expect(sheetRoute.transitionDuration, Duration.zero);
    expect(sheetRoute.reverseTransitionDuration, Duration.zero);
  });
}

class _RouteObserver extends NavigatorObserver {
  Route<dynamic>? lastRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastRoute = route;
  }
}
