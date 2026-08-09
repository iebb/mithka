import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/theme/emoji_font_catalog.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a preloaded emoji family is retained by the first theme frame',
    () async {
      SharedPreferences.setMockInitialValues({
        'emojiFontChoice': 'noto',
        'emojiFontLabel': 'Noto Color Emoji',
        'emojiFontChoiceSchema': 1,
      });
      final prefs = await SharedPreferences.getInstance();
      final catalog = _ControlledEmojiFontCatalog()
        ..loadedFamilies['noto'] = 'MithkaEmoji_noto';
      final controller = ThemeController(prefs, emojiFontCatalog: catalog);
      addTearDown(controller.dispose);

      expect(controller.emojiFontChoice.fontFamily, 'MithkaEmoji_noto');
      expect(
        controller.effectiveFontFamilyChain(),
        contains('MithkaEmoji_noto'),
      );
    },
  );

  test(
    'a stale startup load cannot switch back from the system font',
    () async {
      SharedPreferences.setMockInitialValues({
        'emojiFontChoice': 'noto',
        'emojiFontLabel': 'Noto Color Emoji',
        'emojiFontChoiceSchema': 1,
      });
      final prefs = await SharedPreferences.getInstance();
      final catalog = _ControlledEmojiFontCatalog();
      final controller = ThemeController(prefs, emojiFontCatalog: catalog);
      addTearDown(controller.dispose);

      final loading = controller.loadSelectedEmojiFontIfAvailable();
      controller.useSystemEmojiFont();
      catalog.cachedLoads['noto']!.complete('MithkaEmoji_noto');
      await loading;

      expect(controller.emojiFontChoice, EmojiFontChoice.system);
    },
  );

  test(
    'only the latest asynchronous emoji selection can update the UI',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final catalog = _ControlledEmojiFontCatalog();
      final controller = ThemeController(prefs, emojiFontCatalog: catalog);
      addTearDown(controller.dispose);
      final first = _entry('first');
      final second = _entry('second');

      final selectingFirst = controller.setEmojiFont(first);
      final selectingSecond = controller.setEmojiFont(second);
      catalog.downloads['second']!.complete('MithkaEmoji_second');
      await selectingSecond;
      catalog.downloads['first']!.complete('MithkaEmoji_first');
      await selectingFirst;

      expect(controller.emojiFontChoice.key, 'second');
      expect(controller.emojiFontChoice.fontFamily, 'MithkaEmoji_second');
    },
  );
}

EmojiFontManifestEntry _entry(String key) => EmojiFontManifestEntry(
  key: key,
  label: key,
  license: 'test',
  kind: 'color',
  url: 'https://example.invalid/$key.ttf',
  format: 'glyf',
  coveragePct: 100,
  emojiVersion: 'test',
  updated: 'test',
);

class _ControlledEmojiFontCatalog extends EmojiFontCatalog {
  _ControlledEmojiFontCatalog() : super.forTesting();

  final loadedFamilies = <String, String>{};
  final cachedLoads = <String, Completer<String?>>{};
  final downloads = <String, Completer<String>>{};

  @override
  String? loadedFamilyForKey(String key) => loadedFamilies[key];

  @override
  Future<String?> loadCachedOrDownload(String key) =>
      cachedLoads.putIfAbsent(key, Completer<String?>.new).future;

  @override
  Future<String> downloadAndLoad(EmojiFontManifestEntry entry) =>
      downloads.putIfAbsent(entry.key, Completer<String>.new).future;
}
