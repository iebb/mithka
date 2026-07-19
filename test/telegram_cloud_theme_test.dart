import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_wallpaper.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/telegram_cloud_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses official nested iOS theme colors and wallpaper', () {
    final bytes = Uint8List.fromList(
      utf8.encode('''
name: Mountain Solitude
dark: true
list:
  plainBg: 101820
  primaryText: f2f5f7
  accent: 5f9ea0
chat:
  defaultWallpaper: mountain_solitude 18263b 65
  message:
    incoming:
      bubble:
        withWp:
          bg: 22313b
      primaryText: f2f5f7
    outgoing:
      bubble:
        withWp:
          bg: f3b4bd
      primaryText: 101820
'''),
    );

    final parsed = parseTelegramThemeFile(TelegramThemePlatform.ios, bytes)!;

    expect(parsed.palette['dark'], 1);
    expect(parsed.palette['list.plainBg'], 0x101820);
    expect(parsed.palette['chat.message.incoming.bubble.withWp.bg'], 0x22313B);
    expect(parsed.palette['chat.message.outgoing.bubble.withWp.bg'], 0xF3B4BD);
    expect(parsed.wallpaperDescriptor, 'mountain_solitude 18263b 65');
  });

  test('parses Android ARGB values and embedded wallpaper', () {
    final bytes = Uint8List.fromList([
      ...utf8.encode('''
windowBackgroundWhite=#ff101820
chat_inBubble=-14536389
chat_outBubble=#fff3b4bd
'''),
      ...ascii.encode('\nWPS\n'),
      0xFF,
      0xD8,
      0xFF,
      0xE0,
      1,
      2,
      3,
      0xFF,
      0xD9,
    ]);

    final parsed = parseTelegramThemeFile(
      TelegramThemePlatform.android,
      bytes,
    )!;

    expect(parsed.palette['windowBackgroundWhite'], 0xFF101820);
    expect(parsed.palette['chat_inBubble'], (-14536389) & 0xFFFFFFFF);
    expect(parsed.palette['chat_outBubble'], 0xFFF3B4BD);
    expect(parsed.wallpaperExtension, '.jpg');
    expect(parsed.wallpaperBytes, [
      0xFF,
      0xD8,
      0xFF,
      0xE0,
      1,
      2,
      3,
      0xFF,
      0xD9,
    ]);
  });

  test('parses macOS palette metadata, alpha, and outgoing gradient', () {
    final parsed = parseTelegramThemeFile(
      TelegramThemePlatform.macos,
      Uint8List.fromList(
        utf8.encode('''
isDark=1
background=101820
grayText=8e8e93:0.5
bubbleBackground_outgoing=d8f3ff,8ad4ef
'''),
      ),
    )!;

    expect(parsed.palette['dark'], 1);
    expect(parsed.palette['background'], 0x101820);
    expect(parsed.palette['grayText'], 0x808E8E93);
    expect(parsed.palette['bubbleBackground_outgoing'], 0xD8F3FF);
    expect(parsed.palette['bubbleBackgroundGradient_outgoing'], 0x8AD4EF);
  });

  test('parses Desktop archive colors, aliases, alpha, and tiled image', () {
    final archive = Archive()
      ..addFile(
        ArchiveFile.string('colors.tdesktop-theme', '''
windowBg: #101820;
windowFg: #f2f5f7;
msgInBg: #22313b;
msgOutBg: #f3b4bd;
historyTextInFg: windowFg;
historyTextOutFg: windowBg;
windowShadowFg: #01020380;
'''),
      )
      ..addFile(ArchiveFile('tiled.jpg', 7, [0xFF, 0xD8, 1, 2, 3, 0xFF, 0xD9]));
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive)!);

    final parsed = parseTelegramThemeFile(
      TelegramThemePlatform.desktop,
      bytes,
    )!;

    expect(parsed.palette['msgInBg'], 0x22313B);
    expect(parsed.palette['historyTextInFg'], 0xF2F5F7);
    expect(parsed.palette['windowShadowFg'], 0x80010203);
    expect(parsed.wallpaperIsTiled, isTrue);
    expect(parsed.wallpaperExtension, '.jpg');
  });

  test(
    'cloud theme loader merges Android then iOS, macOS, and Desktop',
    () async {
      final root = await Directory.systemTemp.createTemp('mithka_theme_order');
      addTearDown(() => root.delete(recursive: true));
      final ios = File('${root.path}/theme.tgios-theme');
      final android = File('${root.path}/theme.attheme');
      final macos = File('${root.path}/theme.palette');
      final desktop = File('${root.path}/theme.tdesktop-theme');
      await ios.writeAsString(_iosTheme);
      await android.writeAsString('''
windowBackgroundWhite=#ff334455
chat_inBubble=#ff445566
chat_outBubble=#ff556677
avatar_nameInMessageRed=#ff112233
''');
      await macos.writeAsString('groupPeerNameOrange=cc7722');
      final desktopArchive = Archive()
        ..addFile(
          ArchiveFile.string(
            'colors.tdesktop-theme',
            'windowBg: #667788; msgInBg: #778899; msgOutBg: #8899aa;',
          ),
        );
      await desktop.writeAsBytes(ZipEncoder().encode(desktopArchive)!);

      final service = TelegramCloudThemeService(
        query: (_) async => _themePreview([
          _themeDocument(3, 'theme.tdesktop-theme', 'tgtheme-tdesktop'),
          _themeDocument(4, 'theme.palette', 'tgtheme-macos'),
          _themeDocument(2, 'theme.attheme', 'tgtheme-android'),
          _themeDocument(1, 'theme.tgios-theme', 'tgtheme-ios'),
        ]),
        filePath: (id) async =>
            {1: ios.path, 2: android.path, 3: desktop.path, 4: macos.path}[id],
        supportDirectory: () async => root,
      );

      final theme = await service.load(
        'https://t.me/addtheme/MountainSolitude',
      );

      expect(theme.palette['list.plainBg'], 0x101820);
      expect(theme.incomingColor?.toARGB32(), 0xFF445566);
      expect(theme.outgoingColor?.toARGB32(), 0xFF556677);
      expect(theme.incomingTextColor?.toARGB32(), 0xFFF2F5F7);
      expect(theme.outgoingTextColor?.toARGB32(), 0xFF101820);
      expect(
        theme.uiColors.pinnedRow.toARGB32(),
        theme.uiColors.background.toARGB32(),
      );
      expect(theme.senderNameColors[0].toARGB32(), 0xFF112233);
      expect(theme.senderNameColors[1].toARGB32(), 0xFFCC7722);
      expect(theme.semanticUiPreviewColors, hasLength(8));
    },
  );

  test('telegram.me theme links resolve exactly like t.me links', () async {
    final root = await Directory.systemTemp.createTemp(
      'mithka_telegram_me_theme',
    );
    addTearDown(() => root.delete(recursive: true));
    final ios = File('${root.path}/theme.tgios-theme');
    await ios.writeAsString(_iosTheme);
    String? resolvedLink;
    final service = TelegramCloudThemeService(
      query: (request) async {
        resolvedLink =
            (request['text'] as Map<String, dynamic>)['text'] as String?;
        return _themePreview([
          _themeDocument(1, 'theme.tgios-theme', 'tgtheme-ios'),
        ]);
      },
      filePath: (_) async => ios.path,
      supportDirectory: () async => root,
    );

    final theme = await service.load(
      'https://telegram.me/addtheme/MountainSolitude',
    );

    expect(resolvedLink, 'https://t.me/addtheme/MountainSolitude');
    expect(theme.slug, 'MountainSolitude');
  });

  test(
    'falls back from unusable iOS to Android and persists its image',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'mithka_theme_fallback',
      );
      addTearDown(() => root.delete(recursive: true));
      final ios = File('${root.path}/empty.tgios-theme')
        ..writeAsStringSync('name: empty');
      final android = File('${root.path}/theme.attheme');
      await android.writeAsBytes([
        ...utf8.encode('''
windowBackgroundWhite=#ff334455
chat_inBubble=#ff445566
chat_outBubble=#ff556677
'''),
        ...ascii.encode('\nWPS\n'),
        0xFF,
        0xD8,
        0xFF,
        0xE0,
        9,
        0xFF,
        0xD9,
      ]);
      final service = TelegramCloudThemeService(
        query: (_) async => _themePreview([
          _themeDocument(1, 'empty.tgios-theme', 'tgtheme-ios'),
          _themeDocument(2, 'theme.attheme', 'tgtheme-android'),
        ]),
        filePath: (id) async => id == 1 ? ios.path : android.path,
        supportDirectory: () async => root,
      );

      final theme = await service.load('https://t.me/addtheme/Fallback');

      expect(theme.palette['windowBackgroundWhite'], 0xFF334455);
      expect(theme.incomingColor?.toARGB32(), 0xFF445566);
      expect(theme.outgoingColor?.toARGB32(), 0xFF556677);
      expect(theme.wallpaper?.mimeType, 'image/jpeg');
      expect(await File(theme.wallpaper!.imagePath!).exists(), isTrue);
    },
  );

  test('falls back through Android to a Desktop archive', () async {
    final root = await Directory.systemTemp.createTemp(
      'mithka_theme_desktop_fallback',
    );
    addTearDown(() => root.delete(recursive: true));
    final ios = File('${root.path}/empty.tgios-theme')
      ..writeAsStringSync('name: empty');
    final android = File('${root.path}/empty.attheme')
      ..writeAsStringSync('name=empty');
    final desktop = File('${root.path}/theme.tdesktop-theme');
    final desktopArchive = Archive()
      ..addFile(
        ArchiveFile.string('colors.tdesktop-theme', '''
windowBg: #101820;
windowFg: #f2f5f7;
msgInBg: #22313b;
msgOutBg: #f3b4bd;
'''),
      )
      ..addFile(ArchiveFile('background.jpg', 5, [0xFF, 0xD8, 1, 0xFF, 0xD9]));
    await desktop.writeAsBytes(ZipEncoder().encode(desktopArchive)!);
    final service = TelegramCloudThemeService(
      query: (_) async => _themePreview([
        _themeDocument(1, 'empty.tgios-theme', 'tgtheme-ios'),
        _themeDocument(2, 'empty.attheme', 'tgtheme-android'),
        _themeDocument(3, 'theme.tdesktop-theme', 'tgtheme-tdesktop'),
      ]),
      filePath: (id) async =>
          {1: ios.path, 2: android.path, 3: desktop.path}[id],
      supportDirectory: () async => root,
    );

    final theme = await service.load('https://t.me/addtheme/DesktopFallback');

    expect(theme.palette['windowBg'], 0x101820);
    expect(theme.incomingColor?.toARGB32(), 0xFF22313B);
    expect(theme.outgoingColor?.toARGB32(), 0xFFF3B4BD);
    expect(theme.wallpaper?.isTiled, isFalse);
    expect(await File(theme.wallpaper!.imagePath!).exists(), isTrue);
  });

  test('resolves an iOS wallpaper slug using Telegram backgrounds', () async {
    final root = await Directory.systemTemp.createTemp(
      'mithka_theme_wallpaper',
    );
    addTearDown(() => root.delete(recursive: true));
    final ios = File('${root.path}/theme.tgios-theme');
    await ios.writeAsString(
      _iosTheme.replaceFirst(
        'defaultWallpaper: builtin',
        'defaultWallpaper: mountain_pattern 18263b 65 37526f 45',
      ),
    );
    final pattern = File('${root.path}/pattern.svg')
      ..writeAsStringSync('<svg/>');
    final requests = <String>[];
    final service = TelegramCloudThemeService(
      query: (request) async {
        requests.add(request['@type'] as String);
        if (request['@type'] == 'searchBackground') {
          expect(request['name'], 'mountain_pattern');
          return {
            '@type': 'background',
            'id': '91',
            'document': {
              '@type': 'document',
              'mime_type': 'image/svg+xml',
              'document': {'@type': 'file', 'id': 44},
            },
            'type': {
              '@type': 'backgroundTypePattern',
              'fill': {'@type': 'backgroundFillSolid', 'color': 0x18263B},
              'intensity': 50,
              'is_inverted': false,
              'is_moving': false,
            },
          };
        }
        return _themePreview([
          _themeDocument(1, 'theme.tgios-theme', 'tgtheme-ios'),
        ]);
      },
      filePath: (id) async => id == 1 ? ios.path : pattern.path,
      supportDirectory: () async => root,
    );

    final theme = await service.load('https://t.me/addtheme/Mountains');

    expect(requests, ['getLinkPreview', 'searchBackground']);
    expect(theme.wallpaper?.remoteType, 'pattern');
    expect(theme.wallpaper?.colors, [0x18263B, 0x37526F]);
    expect(theme.wallpaper?.intensity, 65);
    expect(theme.wallpaper?.rotationAngle, 45);
    expect(theme.wallpaper?.imagePath, pattern.path);
  });

  test(
    'resolves Mountain Solitude background link instead of a fallback',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'mithka_mountain_solitude_wallpaper',
      );
      addTearDown(() => root.delete(recursive: true));
      final ios = File('${root.path}/ios.tgios-theme');
      await ios.writeAsString(
        _iosTheme.replaceFirst(
          'defaultWallpaper: builtin',
          'defaultWallpaper: '
              'https://t.me/bg/zzfjlRl4DFMBAAAAxcSJApVpL6g?mode=blur+motion',
        ),
      );
      final photo = File('${root.path}/mountain.jpg')
        ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
      final requests = <Map<String, dynamic>>[];
      final service = TelegramCloudThemeService(
        query: (request) async {
          requests.add(request);
          if (request['@type'] == 'searchBackground') {
            expect(request['name'], 'zzfjlRl4DFMBAAAAxcSJApVpL6g');
            return {
              '@type': 'background',
              'id': '5984290053638062081',
              'name': 'zzfjlRl4DFMBAAAAxcSJApVpL6g',
              'document': {
                '@type': 'document',
                'mime_type': 'image/jpeg',
                'document': {'@type': 'file', 'id': 12},
              },
              'type': {
                '@type': 'backgroundTypeWallpaper',
                'is_blurred': false,
                'is_moving': false,
              },
            };
          }
          return _themePreview([
            _themeDocument(1, 'ios.tgios-theme', 'tgtheme-ios'),
          ]);
        },
        filePath: (id) async => id == 1 ? ios.path : photo.path,
        supportDirectory: () async => root,
      );

      final theme = await service.load(
        'https://t.me/addtheme/MountainSolitude',
      );

      expect(requests.map((request) => request['@type']), [
        'getLinkPreview',
        'searchBackground',
      ]);
      expect(theme.wallpaper?.backgroundId, 5984290053638062081);
      expect(theme.wallpaper?.backgroundName, 'zzfjlRl4DFMBAAAAxcSJApVpL6g');
      expect(theme.wallpaper?.imagePath, photo.path);
      expect(theme.wallpaper?.isBlurred, isTrue);
      expect(theme.wallpaper?.isMoving, isTrue);
    },
  );

  test('Telegram UI palette is persisted but opt-in by default', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const theme = TelegramCloudTheme(
      slug: 'MountainSolitude',
      rawTitle: 'Mountain Solitude',
      baseTheme: 'builtInThemeNight',
      accentColorValue: 0xFF5F9EA0,
      outgoingColors: [0xFFF3B4BD],
      palette: {
        'list.plainBg': 0x101820,
        'list.primaryText': 0xF2F5F7,
        'chat.message.incoming.bubble.withWp.bg': 0x22313B,
        'chat.message.incoming.primaryText': 0xF2F5F7,
        'chat.message.outgoing.primaryText': 0x101820,
      },
      wallpaper: ChatWallpaper.telegram(
        backgroundId: 81,
        remoteType: 'fill',
        colors: [0x101820],
      ),
    );

    final controller = ThemeController(prefs)..installCloudTheme(theme);
    expect(controller.mode, AppearanceMode.system);
    expect(controller.darkCloudTheme?.slug, 'MountainSolitude');
    expect(controller.lightCloudTheme, isNull);
    expect(controller.installedCloudThemes.single.slug, 'MountainSolitude');
    expect(controller.useTelegramThemeForUi, isFalse);
    expect(
      controller.uiColorsFor(Brightness.dark).bubbleIncoming.toARGB32(),
      AppColors.dark.bubbleIncoming.toARGB32(),
    );
    expect(controller.darkCloudTheme?.incomingColor?.toARGB32(), 0xFF22313B);

    controller.useTelegramThemeForUi = true;
    expect(controller.mode, AppearanceMode.system);
    expect(controller.useTelegramThemeForUi, isTrue);
    expect(
      controller.uiColorsFor(Brightness.dark).bubbleIncoming.toARGB32(),
      0xFF22313B,
    );
    expect(
      controller.uiColorsFor(Brightness.light).background.toARGB32(),
      AppColors.light.background.toARGB32(),
    );

    controller.themingEnabled = false;
    expect(controller.useTelegramThemeForUi, isFalse);
    expect(
      controller.uiColorsFor(Brightness.dark).bubbleIncoming.toARGB32(),
      AppColors.dark.bubbleIncoming.toARGB32(),
    );
    controller.themingEnabled = true;
    expect(controller.useTelegramThemeForUi, isTrue);
    expect(
      controller.uiColorsFor(Brightness.dark).bubbleIncoming.toARGB32(),
      0xFF22313B,
    );

    final restored = ThemeController(prefs);
    expect(restored.darkCloudTheme?.slug, 'MountainSolitude');
    expect(restored.useTelegramThemeForUi, isTrue);
    expect(restored.darkCloudTheme?.outgoingColor?.toARGB32(), 0xFFF3B4BD);
    expect(restored.darkCloudTheme?.incomingColor?.toARGB32(), 0xFF22313B);
    expect(restored.darkCloudTheme?.wallpaper?.colors, [0x101820]);

    restored.useTelegramThemeForUi = false;
    expect(restored.darkCloudTheme?.slug, 'MountainSolitude');
    expect(restored.mode, AppearanceMode.system);
    expect(restored.brandColor.toARGB32(), 0xFF0099FF);
    expect(
      restored.uiColorsFor(Brightness.dark).background.toARGB32(),
      AppColors.dark.background.toARGB32(),
    );

    restored.clearCloudTheme();
    expect(restored.hasCloudTheme, isFalse);
    expect(restored.useTelegramThemeForUi, isFalse);
    expect(restored.mode, AppearanceMode.system);
    expect(restored.brandColor.toARGB32(), 0xFF0099FF);
  });

  test('light and dark cloud theme slots persist independently', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const dayTheme = TelegramCloudTheme(
      slug: 'DayTheme',
      rawTitle: 'Day Theme',
      baseTheme: 'builtInThemeDay',
      accentColorValue: 0xFF007AFF,
      outgoingColors: [0xFFDCF8C6],
      palette: {'list.plainBg': 0xFFF8F5ED, 'list.primaryText': 0xFF171717},
    );
    const nightTheme = TelegramCloudTheme(
      slug: 'NightTheme',
      rawTitle: 'Night Theme',
      baseTheme: 'builtInThemeNight',
      accentColorValue: 0xFFF3B4BD,
      outgoingColors: [0xFFF3B4BD],
      palette: {'list.plainBg': 0xFF101820, 'list.primaryText': 0xFFF2F5F7},
    );

    final controller = ThemeController(prefs)
      ..installCloudTheme(dayTheme, brightness: Brightness.light)
      ..installCloudTheme(nightTheme, brightness: Brightness.dark);
    controller.useTelegramThemeForUi = true;

    expect(controller.lightCloudTheme?.slug, 'DayTheme');
    expect(controller.darkCloudTheme?.slug, 'NightTheme');
    expect(controller.installedCloudThemes.map((theme) => theme.slug), [
      'DayTheme',
      'NightTheme',
    ]);
    expect(
      controller.uiColorsFor(Brightness.light).background.toARGB32(),
      0xFFF8F5ED,
    );
    expect(
      controller.uiColorsFor(Brightness.dark).background.toARGB32(),
      0xFF101820,
    );

    // Reinstalling updates the library entry instead of duplicating it.
    controller.installCloudTheme(
      const TelegramCloudTheme(
        slug: 'DayTheme',
        rawTitle: 'Updated Day Theme',
        baseTheme: 'builtInThemeDay',
        accentColorValue: 0xFF007AFF,
        outgoingColors: [0xFFDCF8C6],
        palette: {'list.plainBg': 0xFFFFFFFF},
      ),
      brightness: Brightness.light,
    );
    expect(controller.installedCloudThemes.length, 2);
    expect(controller.installedCloudThemes.last.rawTitle, 'Updated Day Theme');

    final restored = ThemeController(prefs);
    expect(restored.useTelegramThemeForUi, isTrue);
    expect(restored.lightCloudTheme?.rawTitle, 'Updated Day Theme');
    expect(restored.darkCloudTheme?.slug, 'NightTheme');
    expect(restored.installedCloudThemes.length, 2);

    restored.clearCloudTheme(Brightness.light);
    expect(restored.lightCloudTheme, isNull);
    expect(restored.darkCloudTheme?.slug, 'NightTheme');
    expect(restored.useTelegramThemeForUi, isTrue);
  });

  test(
    'theme selections can follow the active account or stay global',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      const firstTheme = TelegramCloudTheme(
        slug: 'FirstAccount',
        rawTitle: 'First Account',
        baseTheme: 'builtInThemeNight',
        accentColorValue: 0xFF112233,
        outgoingColors: [0xFF334455],
        palette: {'list.plainBg': 0xFF101820},
      );
      const secondTheme = TelegramCloudTheme(
        slug: 'SecondAccount',
        rawTitle: 'Second Account',
        baseTheme: 'builtInThemeNight',
        accentColorValue: 0xFF556677,
        outgoingColors: [0xFF778899],
        palette: {'list.plainBg': 0xFF182028},
      );

      final controller = ThemeController(prefs, initialAccountSlot: 1)
        ..installCloudTheme(firstTheme, brightness: Brightness.dark);
      controller.mode = AppearanceMode.dark;
      controller.brandColor = const Color(0xFF112233);
      controller.usePerAccountTheming = true;
      controller.setActiveAccountSlot(2);
      expect(controller.darkCloudTheme, isNull);
      expect(controller.mode, AppearanceMode.system);
      expect(controller.brandColor.toARGB32(), 0xFF0099FF);
      controller.installCloudTheme(secondTheme, brightness: Brightness.dark);
      controller.mode = AppearanceMode.light;
      controller.brandColor = const Color(0xFF556677);

      final restoredSecond = ThemeController(prefs, initialAccountSlot: 2);
      expect(restoredSecond.usePerAccountTheming, isTrue);
      expect(restoredSecond.darkCloudTheme?.slug, 'SecondAccount');
      expect(restoredSecond.mode, AppearanceMode.light);
      expect(restoredSecond.brandColor.toARGB32(), 0xFF556677);

      controller.setActiveAccountSlot(1);
      expect(controller.darkCloudTheme?.slug, 'FirstAccount');
      expect(controller.mode, AppearanceMode.dark);
      expect(controller.brandColor.toARGB32(), 0xFF112233);
      controller.setActiveAccountSlot(2);
      expect(controller.darkCloudTheme?.slug, 'SecondAccount');
      expect(controller.mode, AppearanceMode.light);
      expect(controller.brandColor.toARGB32(), 0xFF556677);

      controller.usePerAccountTheming = false;
      expect(controller.darkCloudTheme?.slug, 'FirstAccount');
      expect(controller.mode, AppearanceMode.dark);
      expect(controller.brandColor.toARGB32(), 0xFF112233);
      controller.setActiveAccountSlot(1);
      expect(controller.darkCloudTheme?.slug, 'FirstAccount');
    },
  );

  test('theme accent and pinned row always resolve semantic colors', () {
    const theme = TelegramCloudTheme(
      slug: 'ReadableTheme',
      rawTitle: 'Readable Theme',
      baseTheme: 'builtInThemeNight',
      accentColorValue: 0xFFF3B4BD,
      outgoingColors: [0xFFF3B4BD],
      palette: {'list.plainBg': 0xFF101820, 'chats_pinnedOverlay': 0xFF18263B},
    );

    expect(theme.uiColors.pinnedRow.toARGB32(), 0xFF18263B);
    expect(theme.uiColors.onAccent.toARGB32(), 0xFF171717);
    expect(readableForeground(const Color(0xFFF3B4BD)).toARGB32(), 0xFF171717);
    expect(readableForeground(const Color(0xFF101820)).toARGB32(), 0xFFFFFFFF);
  });

  test(
    'built-in tint updates reusable UI accent and survives persistence',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = ThemeController(prefs);
      final tinted = builtInTelegramCloudThemes.first.withBuiltInAccent(
        const Color(0xFFFF9500),
      );

      controller.installCloudTheme(tinted, brightness: Brightness.light);
      controller.useTelegramThemeForUi = true;
      final restored = ThemeController(prefs);

      expect(restored.lightCloudTheme?.accentColor.toARGB32(), 0xFFFF9500);
      expect(
        restored.uiColorsFor(Brightness.light).linkBlue.toARGB32(),
        0xFFFF9500,
      );
      expect(restored.useTelegramThemeForUi, isTrue);
    },
  );

  test('community attheme tint remains immutable', () {
    const community = TelegramCloudTheme(
      slug: 'MountainSolitude',
      rawTitle: 'Mountain Solitude',
      baseTheme: 'builtInThemeDay',
      accentColorValue: 0x2481CC,
      outgoingColors: [0xD8F3FF],
      palette: {'list.accent': 0x2481CC},
    );

    expect(
      identical(
        community,
        community.withBuiltInAccent(const Color(0xFFFF9500)),
      ),
      isTrue,
    );
  });
}

const _iosTheme = '''
name: Mountain Solitude
dark: true
list:
  plainBg: 101820
  primaryText: f2f5f7
  accent: 5f9ea0
chat:
  defaultWallpaper: builtin
  message:
    incoming:
      bubble:
        withWp:
          bg: 22313b
      primaryText: f2f5f7
    outgoing:
      bubble:
        withWp:
          bg: f3b4bd
      primaryText: 101820
''';

Map<String, dynamic> _themeDocument(int id, String name, String mime) => {
  '@type': 'document',
  'file_name': name,
  'mime_type': 'application/x-$mime',
  'document': {'@type': 'file', 'id': id},
};

Map<String, dynamic> _themePreview(List<Map<String, dynamic>> documents) => {
  '@type': 'linkPreview',
  'title': 'Mountain Solitude',
  'type': {
    '@type': 'linkPreviewTypeTheme',
    'documents': documents,
    'settings': {
      '@type': 'themeSettings',
      'base_theme': {'@type': 'builtInThemeNight'},
      'accent_color': 0xFF5F9EA0,
      'background': {
        '@type': 'background',
        'id': '81',
        'type': {
          '@type': 'backgroundTypeFill',
          'fill': {'@type': 'backgroundFillSolid', 'color': 0x101820},
        },
      },
      'outgoing_message_fill': {
        '@type': 'backgroundFillSolid',
        'color': 0x477A7B,
      },
    },
  },
};
