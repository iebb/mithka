import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/theme/emoji_font_catalog.dart';

/// The picker's manifest list must lead with Apple — the set every reference
/// client offers first — even though iebb/emojifonts does not build an Apple
/// font. The fork carries the entry itself.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('apple leads the parsed manifest', () {
    final catalog = EmojiFontCatalog.shared;
    // A manifest body shaped like iebb/emojifonts' release asset.
    const body = '''
{
  "fonts": [
    {
      "key": "noto",
      "label": "Google Noto Color Emoji",
      "license": "Apache-2.0 / OFL-1.1",
      "kind": "color",
      "emoji_version": "18.0",
      "formats": {
        "sbix": "https://example.com/noto.ttf"
      }
    }
  ]
}
''';
    final entries = catalog.parseManifestForTesting(body);
    expect(entries.first.key, 'apple');
    expect(entries.first.label, 'Apple Color Emoji');
    expect(entries.first.url, contains('AppleColorEmoji.ttf'));
    expect(entries.first.format, 'cbdt');
    expect(entries[1].key, 'noto');
  });

  test('apple entry is not duplicated when the manifest carries one', () {
    // If iebb/emojifonts ever ships an apple key, the pinned entry must not
    // double the row.
    const body = '''
{
  "fonts": [
    {
      "key": "apple",
      "label": "Apple Color Emoji (manifest)",
      "license": "Apple",
      "kind": "color",
      "emoji_version": "18.0",
      "formats": {
        "sbix": "https://example.com/apple.ttf"
      }
    }
  ]
}
''';
    final entries = EmojiFontCatalog.shared.parseManifestForTesting(body);
    final appleRows = entries.where((e) => e.key == 'apple').toList();
    expect(appleRows, hasLength(1));
    // The pinned fork entry wins (label without the manifest suffix).
    expect(appleRows.single.label, 'Apple Color Emoji');
  });
}
