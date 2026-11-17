import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/theme/emoji_font_catalog.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The bundled-apple default round: the switch-free contract.
/// - fresh installs select the bundled Apple font (label resolved without a
///   stored label because it is a fork-known entry);
/// - the system row is a plain selectable row (no override switch anywhere);
/// - picking a pack stores the choice, picking system clears it;
/// - legacy installs that only stored the "no pack" sentinel migrate to apple.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a fresh install selects the bundled Apple font', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);

    expect(theme.emojiFontChoice.key, 'apple');
    expect(theme.emojiFontChoice.label, 'Apple Color Emoji');
    // Until the idle loader registers the family, the chain falls back to the
    // platform emoji font — the default selection is still apple.
    expect(
      theme.effectiveEmojiFontFamilies,
      EmojiFontChoice.platformEmojiFontFallback(),
    );
    expect(prefs.getString('emojiFontChoice'), 'apple');
  });

  test(
    'a legacy install with only the sentinel key migrates to apple',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      // Pre-switch Android default: no explicit pack ever chosen, switch on.
      SharedPreferences.setMockInitialValues({'emojiUseSystemFont': true});
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      addTearDown(theme.dispose);

      expect(theme.emojiFontChoice.key, 'apple');
    },
  );

  test('a stored pack selection survives untouched', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({
      'emojiFontChoice': 'twemoji',
      'emojiFontLabel': 'Twemoji (jdecked)',
      'emojiUseSystemFont': false,
    });
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);

    expect(theme.emojiFontChoice.key, 'twemoji');
    expect(theme.emojiFontChoice.label, 'Twemoji (jdecked)');
  });

  test('a deliberate system selection survives the migration', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    // The system row writes the choice key and the schema stamp itself; that
    // is a real selection and must not be dragged back to apple.
    SharedPreferences.setMockInitialValues({
      'emojiFontChoice': 'system',
      'emojiFontChoiceSchema': 1,
    });
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);

    expect(theme.emojiFontChoice.isSystem, isTrue);
  });

  test('system row clears the pack override without a switch', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({
      'emojiFontChoice': 'twemoji',
      'emojiFontLabel': 'Twemoji (jdecked)',
    });
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);

    theme.useSystemEmojiFont();
    expect(theme.emojiFontChoice.isSystem, isTrue);
    expect(prefs.getString('emojiFontChoice'), 'system');
    expect(prefs.getString('emojiFontLabel'), isNull);
    expect(
      theme.effectiveEmojiFontFamilies,
      EmojiFontChoice.platformEmojiFontFallback(),
    );
  });

  test('emoji families render last in the effective chain', () async {
    // Failing-first: the pack family used to sit at chain position 2, right
    // after the primary text face, so the pack's own ASCII digits/spaces
    // claimed any character the primary font missed and number spacing
    // exploded app-wide. Emoji must be the tail: text first, emoji only for
    // glyphs no text face carries.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({
      'emojiFontChoice': 'twemoji',
      'emojiFontLabel': 'Twemoji (jdecked)',
    });
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);

    // Simulate the pack family being registered.
    theme.debugSetEmojiFontFamilyForTesting('MithkaEmoji_twemoji');
    final chain = theme.effectiveFontFamilyChain();
    expect(chain, isNotEmpty);
    expect(
      chain[chain.length - 2],
      'MithkaEmoji_twemoji',
      reason:
          'the pack family must be the last emoji family; only the platform '
          'emoji tail follows it',
    );
    expect(
      chain.where((f) => f.startsWith('MithkaEmoji_')).length,
      1,
      reason: 'the pack family appears exactly once',
    );
    expect(
      chain.indexOf('MithkaEmoji_twemoji'),
      greaterThan(chain.indexOf('Roboto')),
      reason: 'a text face precedes the emoji family',
    );
    expect(
      chain.indexOf('MithkaEmoji_twemoji'),
      greaterThan(chain.indexOf('Noto Sans CJK SC')),
      reason: 'CJK text faces also precede the emoji family',
    );
  });
}
