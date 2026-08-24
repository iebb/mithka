import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/theme/chat_font_scale_scope.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('chat scope scales its subtree and leaves the rest alone', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'fontScale': 1.5});
    final prefs = await SharedPreferences.getInstance();
    final controller = ThemeController(prefs);

    TextScaler? inside;
    TextScaler? outside;
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: controller,
        child: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.2)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Column(
              children: [
                ChatFontScaleScope(
                  child: Builder(
                    builder: (context) {
                      inside = MediaQuery.textScalerOf(context);
                      return const SizedBox.shrink();
                    },
                  ),
                ),
                Builder(
                  builder: (context) {
                    outside = MediaQuery.textScalerOf(context);
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // 1.2 system × 1.5 user preference inside the scope, 1.2 outside.
    expect(inside!.scale(10), closeTo(18, 0.001));
    expect(outside!.scale(10), closeTo(12, 0.001));
  });

  testWidgets('chat scope tracks fontScale changes', (tester) async {
    SharedPreferences.setMockInitialValues({'fontScale': 1.0});
    final prefs = await SharedPreferences.getInstance();
    final controller = ThemeController(prefs);

    TextScaler? inside;
    Future<void> pump() => tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: controller,
        child: MediaQuery(
          data: const MediaQueryData(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: ChatFontScaleScope(
              child: Builder(
                builder: (context) {
                  inside = MediaQuery.textScalerOf(context);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      ),
    );

    await pump();
    expect(inside!.scale(10), 10);

    controller.fontScale = 1.4;
    await pump();
    expect(inside!.scale(10), 14);

    // The setter debounces a SharedPreferences write on a 200 ms timer; let it
    // run before the test tears the tree down.
    await tester.pump(const Duration(milliseconds: 300));
  });
}
