import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/telegram_rich_text.dart';
import 'package:mithka/theme/system_font_catalog.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ThemeController> controller([List<String>? chain]) async {
    SharedPreferences.setMockInitialValues({'fontFallbackChain': ?chain});
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);
    return theme;
  }

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('iOS text face resolves before emoji and CJK fallbacks', () async {
    final theme = await controller();
    expect(theme.fontFallbackChain, isEmpty);
    expect(
      AppFontChoice.resolvePlatformFontFamily('CupertinoSystemText'),
      '.AppleSystemUIFont',
    );
    expect(
      theme.effectiveFontFamilyChain(),
      containsAllInOrder(['.AppleSystemUIFont', 'Apple Color Emoji']),
    );
    expect(theme.effectiveFontFamilyChain().first, '.AppleSystemUIFont');
    expect(
      theme.effectiveFontFamilyChain(),
      containsAllInOrder(['PingFang SC', 'PingFang TC', 'Hiragino Sans']),
    );
    expect(
      theme.effectiveFontFamilyChain(),
      isNot(contains('CupertinoSystemText')),
    );
    for (final size in [14.0, 19.0, 20.0, 34.0]) {
      final style = theme.applyAppTextStyle(TextStyle(fontSize: size));
      expect(
        style.fontFamily,
        size < 20 ? '.AppleSystemUIFont' : 'CupertinoSystemDisplay',
      );
      expect(style.fontSize, size);
      expect(style.letterSpacing, 0);
      expect(style.fontFamilyFallback, contains('PingFang SC'));
    }
  });

  test(
    'explicit system-only selections match default without storage changes',
    () async {
      for (final alias in [
        '.AppleSystemUIFont',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
      ]) {
        final theme = await controller([alias]);
        expect(theme.usesIosSystemTypography, isTrue);
        final themed = theme.applyAppTextTheme(
          ThemeData(useMaterial3: true).textTheme,
        );
        expect(themed.bodyMedium!.fontFamily, '.AppleSystemUIFont');
        expect(themed.bodyMedium!.letterSpacing, 0);
        expect(themed.displayLarge!.fontFamily, 'CupertinoSystemDisplay');
        expect(themed.displayLarge!.letterSpacing, 0);
        expect(
          theme
              .applyAppTextStyle(const TextStyle(letterSpacing: 1.2))
              .letterSpacing,
          1.2,
        );
        expect(theme.fontFallbackChain, [alias]);
        expect(
          (await SharedPreferences.getInstance()).getStringList(
            'fontFallbackChain',
          ),
          [alias],
        );
      }
    },
  );

  test('system-first mixed chains retain custom typography', () async {
    final theme = await controller(['.AppleSystemUIFont', 'PingFang TC']);
    expect(theme.usesIosSystemTypography, isFalse);
    final themed = theme.applyAppTextTheme(
      const TextTheme(
        displayLarge: TextStyle(fontSize: 34, letterSpacing: 0.5),
      ),
    );
    expect(themed.displayLarge!.fontFamily, '.AppleSystemUIFont');
    expect(themed.displayLarge!.letterSpacing, 0.5);
    expect(theme.fontFallbackChain, ['.AppleSystemUIFont', 'PingFang TC']);
  });

  test(
    'chain setter invalidates default, custom and system style caches',
    () async {
      final theme = await controller();
      const base = TextStyle(fontSize: 24);
      expect(
        theme.applyAppTextStyle(base).fontFamily,
        'CupertinoSystemDisplay',
      );
      theme.setFontFallbackChain(['Futura']);
      expect(theme.applyAppTextStyle(base).fontFamily, 'Futura');
      expect(theme.applyAppTextStyle(base).letterSpacing, isNull);
      theme.setFontFallbackChain(['.AppleSystemUIFont']);
      expect(
        theme.applyAppTextStyle(base).fontFamily,
        'CupertinoSystemDisplay',
      );
      expect(theme.applyAppTextStyle(base).letterSpacing, 0);
      theme.setFontFallbackChain([]);
      expect(
        theme.applyAppTextStyle(base).fontFamily,
        'CupertinoSystemDisplay',
      );
    },
  );

  testWidgets(
    'TelegramRichText uses system typography but preserves explicit mono',
    (tester) async {
      try {
        final theme = await controller();
        Future<void> pump(TextStyle style) => tester.pumpWidget(
          ChangeNotifierProvider<ThemeController>.value(
            value: theme,
            child: MaterialApp(
              home: MediaQuery(
                data: const MediaQueryData(
                  textScaler: TextScaler.linear(1.3),
                  boldText: true,
                ),
                child: TelegramRichText(text: 'Messages 消息', style: style),
              ),
            ),
          ),
        );
        RichText paragraph() => tester.widget<RichText>(
          find
              .descendant(
                of: find.byType(TelegramRichText),
                matching: find.byType(RichText),
              )
              .first,
        );
        await pump(const TextStyle(fontSize: 17));
        expect(paragraph().text.style!.fontFamily, '.AppleSystemUIFont');
        expect(
          paragraph().text.style!.fontFamilyFallback,
          contains('PingFang SC'),
        );
        expect(paragraph().text.style!.letterSpacing, 0);
        expect(paragraph().text.style!.fontWeight, FontWeight.w600);
        expect(paragraph().textScaler.scale(17), closeTo(22.1, 0.001));
        await pump(
          const TextStyle(
            fontFamily: 'Menlo',
            fontSize: 17,
            letterSpacing: 1.2,
          ),
        );
        expect(paragraph().text.style!.fontFamily, 'Menlo');
        expect(paragraph().text.style!.letterSpacing, 1.2);
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  test(
    'unresolved theme geometry selects optical faces without fixing sizes',
    () async {
      final theme = await controller();
      final styled = theme.applyAppTextTheme(
        const TextTheme(
          displayLarge: TextStyle(),
          titleLarge: TextStyle(),
          bodyMedium: TextStyle(),
          headlineSmall: TextStyle(fontSize: 18),
          labelLarge: TextStyle(fontSize: 24),
        ),
      );
      expect(styled.displayLarge!.fontFamily, 'CupertinoSystemDisplay');
      expect(styled.titleLarge!.fontFamily, 'CupertinoSystemDisplay');
      expect(styled.bodyMedium!.fontFamily, '.AppleSystemUIFont');
      expect(styled.displayLarge!.fontSize, isNull);
      expect(styled.titleLarge!.fontSize, isNull);
      expect(styled.bodyMedium!.fontSize, isNull);
      expect(styled.headlineSmall!.fontFamily, '.AppleSystemUIFont');
      expect(styled.labelLarge!.fontFamily, 'CupertinoSystemDisplay');
    },
  );

  test('only stock iOS theme removes Material tracking', () async {
    final theme = await controller();
    final base = ThemeData(useMaterial3: true).textTheme;
    final styled = theme.applyAppTextTheme(base);
    expect(styled.bodyMedium!.letterSpacing, 0);
    expect(styled.labelSmall!.letterSpacing, 0);
    expect(styled.displayLarge!.letterSpacing, 0);
    expect(styled.displayLarge!.fontFamily, 'CupertinoSystemDisplay');
    expect(styled.bodyMedium!.fontSize, base.bodyMedium!.fontSize);
    expect(styled.bodyMedium!.height, base.bodyMedium!.height);
    const explicit = TextStyle(
      letterSpacing: 1.2,
      height: 1.4,
      fontStyle: FontStyle.italic,
      decoration: TextDecoration.underline,
    );
    final result = theme.applyAppTextStyle(explicit);
    expect(result.letterSpacing, 1.2);
    expect(result.height, 1.4);
    expect(result.fontStyle, FontStyle.italic);
    expect(result.decoration, TextDecoration.underline);
  });

  test(
    'custom order and tracking survive; text sentinel resolves only at runtime',
    () async {
      const chain = ['Futura', 'CupertinoSystemText', 'PingFang TC'];
      final theme = await controller(chain);
      final style = theme.applyAppTextStyle(
        const TextStyle(fontSize: 34, letterSpacing: 0.5),
      );
      expect(style.fontFamily, 'Futura');
      expect(style.letterSpacing, 0.5);
      expect(
        style.fontFamilyFallback,
        containsAllInOrder(['.AppleSystemUIFont', 'PingFang TC']),
      );
      expect(theme.fontFallbackChain, chain);
      expect(
        (await SharedPreferences.getInstance()).getStringList(
          'fontFallbackChain',
        ),
        chain,
      );
      final themed = theme.applyAppTextTheme(
        const TextTheme(bodyMedium: TextStyle(letterSpacing: 0.25)),
      );
      expect(themed.bodyMedium!.letterSpacing, 0.25);
      expect(AppFontChoice.apple.fontFamily, '.AppleSystemUIFont');
    },
  );

  test('code face and explicit spacing are retained', () async {
    final theme = await controller();
    const base = TextStyle(fontSize: 22, letterSpacing: 1.5);
    final code = theme.codeTextStyle(base);
    expect(code.fontFamily, isNot('CupertinoSystemDisplay'));
    expect(code.fontFamily, isNot('.AppleSystemUIFont'));
    expect(code.fontSize, 22);
    expect(code.letterSpacing, 1.5);
  });

  test(
    'macOS and Android retain their default face and Material tracking',
    () async {
      for (final platform in [TargetPlatform.macOS, TargetPlatform.android]) {
        debugDefaultTargetPlatformOverride = platform;
        final theme = await controller();
        const base = TextStyle(fontSize: 34, letterSpacing: 0.5);
        final style = theme.applyAppTextStyle(base);
        expect(
          style.fontFamily,
          platform == TargetPlatform.macOS ? '.AppleSystemUIFont' : 'Roboto',
        );
        expect(style.letterSpacing, 0.5);
        expect(
          theme
              .applyAppTextTheme(const TextTheme(bodyMedium: base))
              .bodyMedium!
              .letterSpacing,
          0.5,
        );
      }
    },
  );

  test('system aliases cannot be rewritten by native normalization', () async {
    const channel = MethodChannel('mithka/fonts');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => [
        '.SFUI-Regular',
        '.SFUI-Regular',
        '.SFUI-Regular',
        'Helvetica Neue',
      ],
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    expect(
      await SystemFontCatalog.normalizeFamilies([
        '.AppleSystemUIFont',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
        'HelveticaNeue',
      ]),
      [
        '.AppleSystemUIFont',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
        'Helvetica Neue',
      ],
    );
  });

  testWidgets('English and Chinese retain scaling and system bold text', (
    tester,
  ) async {
    try {
      final theme = await controller();
      final style = theme.applyAppTextStyle(
        const TextStyle(fontSize: 17),
        boldText: true,
      );
      expect(style.fontWeight, FontWeight.w600);
      final scale = theme.effectiveTextScale(const TextScaler.linear(1.3));
      expect(scale, greaterThan(1));
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(scale),
            boldText: true,
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: DefaultTextStyle(
              style: style,
              child: const Text('Messages 消息'),
            ),
          ),
        ),
      );
      final rich = tester.widget<RichText>(find.byType(RichText));
      expect(rich.text.style!.fontFamily, '.AppleSystemUIFont');
      expect(rich.text.style!.fontFamilyFallback, contains('PingFang SC'));
      expect(rich.text.style!.letterSpacing, 0);
      expect(rich.textScaler.scale(17), greaterThan(17));
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
