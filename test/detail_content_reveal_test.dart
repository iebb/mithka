import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/detail_content_reveal.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  testWidgets(
    'chat switch keeps the full detail pane painted with the active theme',
    (tester) async {
      const firstBackground = Color(0xFF102A43);
      const nextBackground = Color(0xFF6B2148);
      const childKey = ValueKey('revealed-detail-child');

      Widget host({required Key motionKey, required Color background}) {
        return MediaQuery(
          data: const MediaQueryData(size: Size(760, 520)),
          child: Theme(
            data: ThemeData(
              extensions: [
                AppColors.light.copyWith(chatBackground: background),
              ],
            ),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: SizedBox(
                width: 760,
                height: 520,
                child: DetailContentReveal(
                  motionKey: motionKey,
                  child: const ColoredBox(
                    key: childKey,
                    color: Color(0xFF334E68),
                  ),
                ),
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(
        host(
          motionKey: const ValueKey('first-chat'),
          background: firstBackground,
        ),
      );
      await tester.pump();

      await tester.pumpWidget(
        host(
          motionKey: const ValueKey('next-chat'),
          background: nextBackground,
        ),
      );

      final surface = find.byKey(DetailContentReveal.surfaceKey);
      final child = find.byKey(childKey);
      expect(tester.getRect(child), tester.getRect(surface));
      expect(tester.widget<ColoredBox>(surface).color, nextBackground);
      expect(
        find.descendant(of: surface, matching: find.byType(Transform)),
        findsNothing,
      );
      expect(
        find.descendant(of: surface, matching: find.byType(Opacity)),
        findsNothing,
      );

      final tint = tester.widget<ColoredBox>(
        find.byKey(DetailContentReveal.transitionTintKey),
      );
      expect(tint.color, nextBackground.withValues(alpha: 0.08));

      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(DetailContentReveal.transitionTintKey), findsNothing);
      expect(tester.getRect(child), tester.getRect(surface));
    },
  );
}
