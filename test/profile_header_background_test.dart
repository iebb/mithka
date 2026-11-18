import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/profile/profile_header_background.dart';

void main() {
  final profileUpdate = {
    '@type': 'updateProfileAccentColors',
    'colors': [
      {
        'id': 19,
        'light_theme_colors': {
          'palette_colors': [0xFF0000],
          'background_colors': [0xA34F74, 0x874060],
        },
        'dark_theme_colors': {
          'palette_colors': [0x00FF00],
          'background_colors': [0x60334C, 0x432035],
        },
      },
    ],
  };

  test('uses profile background colors rather than palette swatch colors', () {
    expect(
      profileHeaderColors(
        profileAccentColorId: 19,
        accentColorId: 0,
        dark: false,
        profileAccentColors: profileUpdate,
      ),
      [const Color(0xFFA34F74), const Color(0xFF874060)],
    );
    expect(
      profileHeaderColors(
        profileAccentColorId: 19,
        accentColorId: 0,
        dark: true,
        profileAccentColors: profileUpdate,
      ),
      [const Color(0xFF60334C), const Color(0xFF432035)],
    );
  });

  test('an unset or unavailable profile color falls back to name color', () {
    for (final id in [-1, 999]) {
      expect(
        profileHeaderColors(
          profileAccentColorId: id,
          accentColorId: 2,
          dark: false,
          profileAccentColors: profileUpdate,
        )?.last,
        const Color(0xFF955CDB),
      );
    }
  });

  test('extended name colors use the matching light or dark palette', () {
    final nameUpdate = {
      'colors': [
        {
          'id': 35,
          'built_in_accent_color_id': 2,
          'light_theme_colors': [0xA34F74, 0x874060],
          'dark_theme_colors': [0x60334C, 0x432035],
        },
      ],
    };
    expect(
      profileHeaderColors(
        profileAccentColorId: -1,
        accentColorId: 35,
        dark: false,
        accentColors: nameUpdate,
      )?.last,
      const Color(0xFFA34F74),
    );
    expect(
      profileHeaderColors(
        profileAccentColorId: -1,
        accentColorId: 35,
        dark: true,
        accentColors: nameUpdate,
      )?.last,
      Color.lerp(const Color(0xFF60334C), const Color(0xFF000000), 0.22),
    );
    expect(
      profileHeaderColors(
        profileAccentColorId: -1,
        accentColorId: -1,
        dark: false,
      ),
      isNull,
    );
  });

  test('pattern stays inside narrow and wide headers and off the photo', () {
    for (final width in [200.0, 375.0, 782.0]) {
      final bounds = Size(width, 166);
      const center = Offset(55, 109);
      const photoRadius = 37.0;
      final slots = profilePatternSlots(bounds, center, photoRadius);
      expect(slots, isNotEmpty);
      for (final slot in slots) {
        final rect = Rect.fromCenter(
          center: slot.center,
          width: slot.size,
          height: slot.size,
        );
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(bounds.width));
        expect(rect.bottom, lessThanOrEqualTo(bounds.height));
        expect(
          (slot.center - center).distance - slot.size / 2,
          greaterThan(photoRadius),
        );
        expect(slot.opacity, inInclusiveRange(0.0, 1.0));
      }
    }
  });
}
