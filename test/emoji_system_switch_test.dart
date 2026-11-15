import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mithka/settings/app_icon_controller.dart';
import 'package:mithka/theme/emoji_font_catalog.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// exteraless "EmojiUseDefault" parity: the system-emoji switch overrides the
/// selected pack; Android defaults to system emoji; picking a pack turns the
/// switch off; picking the system row turns it on and clears the pack.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('android defaults to the system emoji font', () async {
    // Failing-first: the choice always resolved through the pack list, so a
    // fresh Android install shipped Noto-downloaded emoji instead of the
    // platform font exteraless ships by default.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);

    expect(theme.useSystemEmoji, isTrue);
    expect(
      theme.effectiveEmojiFontFamilies,
      EmojiFontChoice.platformEmojiFontFallback(),
    );
  });

  test('non-android platforms default to the selected pack', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);

    expect(theme.useSystemEmoji, isFalse);
  });

  test('switch overrides the pack selection and persists', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);

    theme.setUseSystemEmoji(false);
    expect(theme.useSystemEmoji, isFalse);
    expect(prefs.getBool('emojiUseSystemFont'), isFalse);

    // A second controller reads the persisted choice back.
    final theme2 = ThemeController(prefs);
    addTearDown(theme2.dispose);
    expect(theme2.useSystemEmoji, isFalse);
  });

  test('system row turns the switch on and clears the pack override', () async {
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

    theme.useSystemEmojiFont();
    expect(theme.useSystemEmoji, isTrue);
    expect(theme.emojiFontChoice.isSystem, isTrue);
    expect(prefs.getString('emojiFontChoice'), 'system');
    expect(prefs.getString('emojiFontLabel'), isNull);
  });

  test('effective families follow the switch, not the pack', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({
      'emojiFontChoice': 'twemoji',
      'emojiFontLabel': 'Twemoji (jdecked)',
      // switch on: pack selected but system renders
      'emojiUseSystemFont': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);

    expect(theme.emojiFontChoice.key, 'twemoji');
    expect(
      theme.effectiveEmojiFontFamilies,
      EmojiFontChoice.platformEmojiFontFallback(),
    );

    theme.setUseSystemEmoji(false);
    // Until the pack's bytes are registered the family is absent and the
    // chain falls back to the platform font — the switch only picks WHICH
    // source wins; the loader still has to run for a pack family to appear.
    expect(
      theme.effectiveEmojiFontFamilies,
      EmojiFontChoice.platformEmojiFontFallback(),
    );
  });

  test('icon switch clears the stale task on android', () async {
    // The controller-side half of the post-icon-switch crash fix: after a
    // successful setIcon, the old alias-rooted task record must be dropped.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    const channel = const MethodChannel('mithka/app_icon');
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return switch (call.method) {
            'isSupported' => true,
            'currentIcon' => 'blue',
            'setIcon' => null,
            'clearTaskAfterIconSwitch' => true,
            _ => throw MissingPluginException(),
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final controller = AppIconController(
      prefs,
      proService: null,
      platform: TargetPlatform.android,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(await controller.setVariant(AppIconVariant.signal), isTrue);
    expect(calls, contains('clearTaskAfterIconSwitch'));
  });
}
