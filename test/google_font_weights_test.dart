import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/theme/google_font_weights.dart';

void main() {
  test('the app asks for the weights its labels actually use', () {
    // w600 carries most of this app's labels; w400 and w500 arrive from the
    // Material text theme. Dropping one of these puts that weight back on a
    // synthetic embolden.
    expect(kGoogleFontWeights, [
      FontWeight.w400,
      FontWeight.w500,
      FontWeight.w600,
    ]);
  });

  test('variant segments match the names google_fonts caches under', () {
    expect(googleFontVariantSegment(FontWeight.w400), 'regular');
    expect(googleFontVariantSegment(FontWeight.w500), '500');
    expect(googleFontVariantSegment(FontWeight.w600), '600');
  });

  group('reading google_fonts cache file names', () {
    FontWeight? weightOf(String fileName, {String family = 'Noto Sans TC'}) =>
        googleFontWeightOfCacheFile(googleFamily: family, fileName: fileName);

    test('recognises the real names on disk', () {
      // Verbatim from a device cache.
      expect(
        weightOf(
          'NotoSansTC_regular_17d9b1bfc0eb614c5947422e575e4bf664afc809def6'
          'cdcd7760d76c71928e50.ttf',
        ),
        FontWeight.w400,
      );
      expect(
        weightOf(
          'NotoSansTC_500_95f8eb752ac1451f647591e4e3662d1e22a51a301898ecfd'
          '9415c8d2fbf95ea0.ttf',
        ),
        FontWeight.w500,
      );
      expect(weightOf('NotoSansTC_600_abc123.ttf'), FontWeight.w600);
    });

    test('ignores files belonging to another family or weight', () {
      expect(weightOf('NotoSansSC_600_abc123.ttf'), isNull);
      expect(weightOf('NotoSansTC_700_abc123.ttf'), isNull);
      expect(weightOf('NotoSansTC_600italic_abc123.ttf'), isNull);
    });

    test('ignores anything that is not a cached face', () {
      expect(weightOf('NotoSansTC_600_abc123.woff2'), isNull);
      expect(weightOf('NotoSansTC_600.ttf'), isNull);
      expect(weightOf('unrelated.ttf'), isNull);
      expect(weightOf('NotoSansTC_.ttf'), isNull);
    });

    test('handles families whose names carry no spaces', () {
      expect(
        weightOf('Roboto_regular_abc123.ttf', family: 'Roboto'),
        FontWeight.w400,
      );
    });
  });

  test('a family is only named once its faces are registered', () {
    final loader = GoogleFontWeightLoader.forTesting();
    addTearDown(loader.dispose);
    // Nothing is registered in a plain test binding, so the pipeline keeps
    // google_fonts' per-variant family instead of naming one that has no faces.
    expect(loader.loadedFamily('Noto Sans TC'), isNull);
  });
}
