import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/profile/profile_username_pill.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  test('pill palette follows the active theme colors', () {
    final palette = profileUsernamePillPalette(AppColors.light);

    expect(palette.capFill, AppColors.light.linkBlue.withValues(alpha: 1));
    expect(
      palette.bodyFill,
      Color.alphaBlend(
        AppColors.light.linkBlue.withValues(alpha: 0.24),
        AppColors.light.card.withValues(alpha: 1),
      ),
    );
    expect(
      _contrast(palette.capInk, palette.capFill),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(palette.bodyInk, palette.bodyFill),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('pill halves remain distinct when theme accent matches its card', () {
    const shared = Color(0xFFF9F7F4);
    final palette = profileUsernamePillPalette(
      AppColors.light.copyWith(linkBlue: shared, card: shared),
    );

    expect(palette.capFill, isNot(palette.bodyFill));
    expect(
      _contrast(palette.capInk, palette.capFill),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(palette.bodyInk, palette.bodyFill),
      greaterThanOrEqualTo(4.5),
    );
  });

  testWidgets(
    'renders a joined @ cap and username body in physical LTR order',
    (tester) async {
      await tester.pumpWidget(
        _pillHarness(
          textDirection: TextDirection.rtl,
          child: const ProfileUsernamePill(username: '@nekoko14'),
        ),
      );

      final cap = find.byKey(const ValueKey('profileUsernamePillAt'));
      final body = find.byKey(const ValueKey('profileUsernamePillValue'));
      expect(find.text('@'), findsOneWidget);
      expect(find.text('nekoko14'), findsOneWidget);
      expect(tester.getTopRight(cap).dx, tester.getTopLeft(body).dx);
      expect(tester.getSize(cap).height, tester.getSize(body).height);
      expect(tester.getTopLeft(cap).dx, lessThan(tester.getTopLeft(body).dx));
    },
  );

  testWidgets('long usernames ellipsize inside a narrow scaled pill', (
    tester,
  ) async {
    await tester.pumpWidget(
      _pillHarness(
        textScaler: const TextScaler.linear(3),
        child: const SizedBox(
          width: 120,
          child: ProfileUsernamePill(
            username: 'maximum_length_collectible_username',
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const ValueKey('profileUsernamePill'))).width,
      lessThanOrEqualTo(120),
    );
    final value = tester.widget<Text>(
      find.text('maximum_length_collectible_username'),
    );
    expect(value.maxLines, 1);
    expect(value.overflow, TextOverflow.ellipsis);
  });
}

Widget _pillHarness({
  required Widget child,
  TextDirection textDirection = TextDirection.ltr,
  TextScaler textScaler = TextScaler.noScaling,
}) => MaterialApp(
  theme: ThemeData(brightness: Brightness.light, extensions: [AppColors.light]),
  home: Directionality(
    textDirection: textDirection,
    child: MediaQuery(
      data: MediaQueryData(textScaler: textScaler),
      child: Align(alignment: Alignment.topLeft, child: child),
    ),
  ),
);

double _contrast(Color a, Color b) {
  final lighter = a.computeLuminance() >= b.computeLuminance() ? a : b;
  final darker = identical(lighter, a) ? b : a;
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}
