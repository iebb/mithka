import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/theme/app_motion.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  late AnimationController controller;

  // Accepts builders with optional extra parameters so [transitionFor] can
  // be passed as a tear-off.
  Widget host(Widget Function(BuildContext) builder) => MaterialApp(
    themeAnimationDuration: Duration.zero,
    theme: ThemeData(
      platform: TargetPlatform.android,
      extensions: [AppColors.light],
    ),
    home: Builder(builder: builder),
  );

  Widget transitionFor(BuildContext context, {bool fullscreenDialog = false}) {
    const builder = AppPageTransitionsBuilder();
    final route = MaterialPageRoute<void>(
      fullscreenDialog: fullscreenDialog,
      builder: (_) => const SizedBox.shrink(),
    );
    return builder.buildTransitions<void>(
      route,
      context,
      controller.view,
      const AlwaysStoppedAnimation<double>(0),
      const SizedBox(key: ValueKey('transition-child')),
    );
  }

  Widget pageTransition(BuildContext context) => transitionFor(context);

  /// The on-screen opacity of the transition child: the product of every
  /// ancestor [FadeTransition] (nested fades multiply).
  double effectiveOpacity(WidgetTester tester) {
    var product = 1.0;
    for (final fade in tester.widgetList<FadeTransition>(
      find.ancestor(
        of: find.byKey(const ValueKey('transition-child')),
        matching: find.byType(FadeTransition),
      ),
    )) {
      product *= fade.opacity.value;
    }
    return product;
  }

  // A pop runs the controller from 1.0 back to 0.0 over 240 ms. The dual
  // builder only takes the exit path once the animation status flips to
  // reverse, which the zero-duration pump lets settle before sampling.
  Future<List<double>> sampleExit(WidgetTester tester) async {
    controller.value = 1;
    await tester.pump();
    unawaited(controller.reverse());
    await tester.pump();
    final samples = <double>[];
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      samples.add(effectiveOpacity(tester));
    }
    // Land the controller so no ticker outlives the tree disposal.
    controller.stop();
    controller.value = 0;
    return samples;
  }

  setUp(() {
    controller = AnimationController(
      vsync: const TestVSync(),
      duration: AppMotion.route,
      reverseDuration: AppMotion.routeReverse,
    );
  });

  tearDown(() => controller.dispose());

  testWidgets(
    'shared route exit fades the page fully out by its last frame',
    (tester) async {
      await tester.pumpWidget(host(pageTransition));
      final samples = await sampleExit(tester);

      // The exit is a real fade: strictly decreasing, ending at fully
      // transparent instead of being torn down mid-fade near 0.92.
      for (var i = 1; i < samples.length; i++) {
        expect(samples[i], lessThan(samples[i - 1]));
      }
      expect(samples.first, lessThan(1));
      expect(samples.last, 0, reason: 'samples=$samples');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'fullscreen dialog exits fade fully out by the last frame',
    (tester) async {
      await tester.pumpWidget(
        host((context) => transitionFor(context, fullscreenDialog: true)),
      );
      final samples = await sampleExit(tester);

      for (var i = 1; i < samples.length; i++) {
        expect(samples[i], lessThan(samples[i - 1]));
      }
      expect(samples.first, lessThan(1));
      expect(samples.last, 0, reason: 'samples=$samples');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'shared route entrance keeps the original converging fade',
    (tester) async {
      await tester.pumpWidget(host(pageTransition));
      controller.value = 0;
      await tester.pump();
      // Entrance starts below full opacity (0.92 with the standard curve at 0)
      // and converges to fully opaque.
      expect(effectiveOpacity(tester), closeTo(0.92, 0.001));

      controller.value = 1;
      await tester.pump();
      expect(effectiveOpacity(tester), 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'a live navigator pops a themed route without exceptions',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          themeAnimationDuration: Duration.zero,
          theme: ThemeData(
            platform: TargetPlatform.android,
            extensions: [AppColors.light],
          ),
          home: Builder(
            builder: (context) => GestureDetector(
              key: const ValueKey('open'),
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SizedBox(key: ValueKey('pushed')),
                ),
              ),
              child: const SizedBox(width: 40, height: 40),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pushed')), findsOneWidget);

      // Pop midway through a fresh entrance as well, to exercise the
      // interrupted-transition path of the dual builder inside a live route.
      Navigator.of(tester.element(find.byKey(const ValueKey('pushed')))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('pushed')), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
