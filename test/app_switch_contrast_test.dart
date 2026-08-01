import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  testWidgets('active switch uses the theme foreground over a light accent', (
    tester,
  ) async {
    const accent = Color(0xFFF9F7F4);
    const onAccent = Color(0xFF171717);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            AppColors.dark.copyWith(linkBlue: accent, onAccent: onAccent),
          ],
        ),
        home: Center(child: AppSwitch(value: true, onChanged: (_) {})),
      ),
    );

    expect(_trackColor(tester), accent);
    expect(_handleColor(tester), onAccent);
    expect(_contrastRatio(accent, onAccent), greaterThanOrEqualTo(3));
  });

  testWidgets('inactive switch keeps its existing white handle', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            AppColors.dark.copyWith(
              linkBlue: const Color(0xFFF9F7F4),
              onAccent: const Color(0xFF171717),
            ),
          ],
        ),
        home: Center(child: AppSwitch(value: false, onChanged: (_) {})),
      ),
    );

    expect(_trackColor(tester), AppColors.dark.textTertiary);
    expect(_handleColor(tester), const Color(0xFFFFFFFF));
  });
}

Color _trackColor(WidgetTester tester) {
  final track = tester.widget<AnimatedContainer>(
    find.descendant(
      of: find.byType(AppSwitch),
      matching: find.byType(AnimatedContainer),
    ),
  );
  return (track.decoration! as BoxDecoration).color!;
}

Color _handleColor(WidgetTester tester) {
  final handle = tester.widget<Container>(
    find.descendant(
      of: find.byType(AppSwitch),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).shape == BoxShape.circle,
      ),
    ),
  );
  return (handle.decoration! as BoxDecoration).color!;
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
