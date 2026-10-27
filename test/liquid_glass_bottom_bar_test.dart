import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/liquid_glass_bottom_bar.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/app_icon_controller.dart';
import 'package:mithka/settings/appearance_view.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/glass_review_capture.dart';

void main() {
  testWidgets('icon-only capsule slots fit at larger text scales', (
    tester,
  ) async {
    const labels = ['Chats', 'Channels', 'Contacts', 'Moments'];
    for (final scale in [1.0, 1.4, 2.0]) {
      for (var selected = 0; selected < labels.length; selected++) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(extensions: [AppColors.light]),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    width: 318,
                    child: LiquidGlassBottomBar(
                      selection: selected,
                      itemCount: labels.length,
                      child: SizedBox(
                        height: 62,
                        child: Row(
                          children: [
                            for (final label in labels)
                              Expanded(
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 2,
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          key: ValueKey('scaled-icon-$label'),
                                          width: 36,
                                          height: 28,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final indicator = find.byKey(const ValueKey('liquid-glass-selection'));
        final decoration =
            tester.widget<DecoratedBox>(indicator).decoration as BoxDecoration;
        final radius = decoration.borderRadius! as BorderRadius;
        final shape = radius.toRRect(tester.getRect(indicator));
        expect(
          radius,
          BorderRadius.circular(tester.getSize(indicator).height / 2),
        );
        for (final prefix in ['scaled-icon']) {
          final bounds = tester.getRect(
            find.byKey(ValueKey('$prefix-${labels[selected]}')),
          );
          for (final point in [
            bounds.topLeft,
            bounds.topRight,
            bounds.bottomLeft,
            bounds.bottomRight,
          ]) {
            expect(
              shape.contains(point),
              isTrue,
              reason: '$prefix, scale $scale, selected $selected',
            );
          }
        }
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('glass setting defaults off and persists both choices', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    final appIcons = AppIconController(prefs);
    addTearDown(theme.dispose);
    addTearDown(appIcons.dispose);
    expect(theme.liquidGlassBottomBar, isFalse);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: appIcons),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [AppLocalizations.delegate],
          home: AppearanceView(),
        ),
      ),
    );
    final row = find.byKey(const ValueKey('settings-liquid-glass-bottom-bar'));
    expect(tester.widget<SettingsSwitchRow>(row).value, isFalse);
    for (final value in [true, false]) {
      await tester.tap(row);
      await tester.pump();
      expect(theme.liquidGlassBottomBar, value);
      expect(prefs.getBool('liquidGlassBottomBar'), value);
      final restored = ThemeController(prefs);
      expect(restored.liquidGlassBottomBar, value);
      restored.dispose();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('glass respects safe area, RTL, contrast, and reduced motion', (
    tester,
  ) async {
    var selection = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.dark]),
        home: MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.only(bottom: 34),
            disableAnimations: true,
            highContrast: true,
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 320,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    update = setState;
                    return LiquidGlassBottomBar(
                      selection: selection,
                      itemCount: 4,
                      child: const SizedBox(height: 90, width: double.infinity),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final bar = find.byType(LiquidGlassBottomBar);
    final pill = find.byKey(const ValueKey('liquid-glass-selection'));
    final initial = tester.getRect(pill);
    expect(tester.getRect(bar).bottom - initial.bottom, 39);
    expect(
      tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled,
      isFalse,
    );
    update(() => selection = 3);
    await tester.pump();
    expect(tester.getRect(pill).left, lessThan(initial.left));
    expect(
      tester
          .widget<AnimatedPositionedDirectional>(
            find.byType(AnimatedPositionedDirectional),
          )
          .duration,
      Duration.zero,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('selection capsule derives its radius from its own height', (
    tester,
  ) async {
    // The glass row is icon-only. Its full capsule follows the outer surface
    // across the 5pt inset; the classic icon + label bar is a separate path.
    for (final rowHeight in [62.0, 71.0]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [AppColors.light]),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 318,
                child: LiquidGlassBottomBar(
                  selection: 0,
                  itemCount: 4,
                  child: SizedBox(
                    height: rowHeight,
                    child: Row(
                      children: [
                        for (var index = 0; index < 4; index++)
                          Expanded(
                            child: Center(
                              child: SizedBox(
                                key: ValueKey('capsule-icon-$index'),
                                width: 36,
                                height: 28,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final pill = find.byKey(const ValueKey('liquid-glass-selection'));
      final rect = tester.getRect(pill);
      final decoration =
          tester.widget<DecoratedBox>(pill).decoration as BoxDecoration;
      final radius = decoration.borderRadius! as BorderRadius;
      expect(rect.height, rowHeight);
      expect(radius, BorderRadius.circular(rowHeight / 2));
      final shape = radius.toRRect(rect);
      final icon = tester.getRect(find.byKey(const ValueKey('capsule-icon-0')));
      for (final corner in [
        icon.topLeft,
        icon.topRight,
        icon.bottomLeft,
        icon.bottomRight,
      ]) {
        expect(shape.contains(corner), isTrue);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'capture patterned glass surfaces for visual review',
    (tester) async {
      for (final scene in [
        (name: 'capsule-light', dark: false, highContrast: false),
        (name: 'capsule-dark', dark: true, highContrast: false),
        (name: 'capsule-high-contrast', dark: false, highContrast: true),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: scene.dark ? Brightness.dark : Brightness.light,
              extensions: [scene.dark ? AppColors.dark : AppColors.light],
            ),
            home: Scaffold(
              body: Center(
                child: glassReviewBoundary(
                  SizedBox(
                    width: 390,
                    height: 180,
                    child: MediaQuery(
                      data: MediaQueryData(highContrast: scene.highContrast),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(painter: _ReviewBackdrop()),
                          ),
                          const Align(
                            alignment: Alignment.bottomCenter,
                            child: LiquidGlassBottomBar(
                              selection: 1,
                              itemCount: 4,
                              child: SizedBox(
                                height: 62,
                                width: double.infinity,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await captureGlassReviewImage(tester, scene.name);
      }
    },
    skip: !captureGlassReview,
  );
}

class _ReviewBackdrop extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const colors = [Color(0xFF186AAB), Color(0xFFF6CC5D), Color(0xFFEA6262)];
    for (var index = 0; index * 18 < size.width; index++) {
      canvas.drawRect(
        Rect.fromLTWH(index * 18.0, 0, 18, size.height),
        Paint()..color = colors[index % colors.length],
      );
    }
  }

  @override
  bool shouldRepaint(_ReviewBackdrop oldDelegate) => false;
}
