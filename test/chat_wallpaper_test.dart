import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:mithka/chat/chat_wallpaper.dart';
import 'package:mithka/chat/chat_wallpaper_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('wallpaper JSON preserves preset and image values', () {
    const preset = ChatWallpaper.preset('sky');
    const image = ChatWallpaper.image(
      '/tmp/wallpaper.png',
      isBlurred: true,
      isMoving: true,
    );
    const tiled = ChatWallpaper.telegram(
      backgroundId: 0,
      remoteType: 'wallpaper',
      imagePath: '/tmp/tiled.jpg',
      backgroundName: 'MountainSolitude',
      isTiled: true,
    );

    expect(ChatWallpaper.fromJson(preset.toJson()), preset);
    expect(ChatWallpaper.fromJson(image.toJson()), image);
    expect(ChatWallpaper.fromJson(tiled.toJson()), tiled);
    expect(
      ChatWallpaper.fromJson(const {'kind': 'preset', 'preset_id': 'missing'}),
      isNull,
    );
  });

  test('image-backed wallpapers do not expose color customization', () {
    expect(
      wallpaperSupportsColorCustomization(
        const ChatWallpaper.telegram(
          backgroundId: 1,
          remoteType: 'wallpaper',
          imagePath: '/tmp/background.jpg',
          colors: [0x123456, 0x654321],
        ),
      ),
      isFalse,
    );
    expect(
      wallpaperSupportsColorCustomization(
        const ChatWallpaper.image('/tmp/background.jpg'),
      ),
      isFalse,
    );
    expect(
      wallpaperSupportsColorCustomization(
        const ChatWallpaper.telegram(
          backgroundId: 2,
          remoteType: 'pattern',
          imagePath: '/tmp/pattern.png',
        ),
      ),
      isTrue,
    );
  });

  test(
    'Theme wallpaper uses the active cloud theme when no override exists',
    () {
      final controller = ChatWallpaperController(
        activeSlot: () => 0,
        hasActiveClient: () => false,
        listenForUpdates: false,
      );
      const mountain = ChatWallpaper.telegram(
        backgroundId: 42,
        remoteType: 'wallpaper',
        imagePath: '/tmp/mountain-solitude.jpg',
      );

      expect(
        effectiveThemeWallpaperForPicker(
          controller: controller,
          dark: true,
          cloudThemeWallpaper: mountain,
        ),
        mountain,
      );
    },
  );

  test(
    'cloud theme wallpaper outranks a legacy emoji theme preference',
    () async {
      SharedPreferences.setMockInitialValues({
        'mithka.globalChatTheme.v1.0:dark': 'emoji:👨‍🏫',
      });
      final controller = ChatWallpaperController(
        activeSlot: () => 0,
        hasActiveClient: () => false,
        listenForUpdates: false,
      );
      await controller.loadGlobalChatThemes();
      const mountain = ChatWallpaper.telegram(
        backgroundId: 5984290053638062081,
        backgroundName: 'zzfjlRl4DFMBAAAAxcSJApVpL6g',
        remoteType: 'wallpaper',
        imagePath: '/tmp/mountain-solitude.jpg',
      );

      expect(controller.hasExplicitGlobalThemeSelection(dark: true), isTrue);
      expect(
        effectiveThemeWallpaperForPicker(
          controller: controller,
          dark: true,
          cloudThemeWallpaper: mountain,
        ),
        mountain,
      );
    },
  );

  test('custom gradients preserve colors and rotation independently', () {
    const pattern = ChatWallpaper.telegram(
      backgroundId: 91,
      remoteType: 'pattern',
      colors: [0x112233],
      rotationAngle: 45,
      fileId: 7,
      imagePath: '/tmp/pattern.svg',
    );

    final customized = pattern
        .withColors(const [0x445566, 0x778899])
        .withRotationAngle(315);

    expect(customized.colors, [0x445566, 0x778899]);
    expect(customized.rotationAngle, 315);
    expect(customized.fileId, 7);
    expect(customized.imagePath, '/tmp/pattern.svg');
  });

  test('Telegram two-color gradients follow iOS rotation semantics', () {
    final zero = telegramLinearGradientAlignments(0);
    expect(zero.$1, Alignment.topCenter);
    expect(zero.$2, Alignment.bottomCenter);

    final clockwise = telegramLinearGradientAlignments(90);
    expect(clockwise.$1.x, closeTo(-1, 0.0001));
    expect(clockwise.$1.y, closeTo(0, 0.0001));
    expect(clockwise.$2.x, closeTo(1, 0.0001));
    expect(clockwise.$2.y, closeTo(0, 0.0001));
  });

  test('wallpapers are persisted per account and chat', () async {
    SharedPreferences.setMockInitialValues({});
    var activeSlot = 0;
    final controller = ChatWallpaperController(
      activeSlot: () => activeSlot,
      listenForUpdates: false,
    );

    await controller.setPreset(42, 'sky');
    expect(controller.wallpaperFor(42), const ChatWallpaper.preset('sky'));

    activeSlot = 1;
    await controller.load(42);
    expect(controller.wallpaperFor(42), isNull);
    await controller.setPreset(42, 'night');

    activeSlot = 0;
    expect(controller.wallpaperFor(42), const ChatWallpaper.preset('sky'));

    final restored = ChatWallpaperController(
      activeSlot: () => activeSlot,
      listenForUpdates: false,
    );
    await restored.load(42);
    expect(restored.wallpaperFor(42), const ChatWallpaper.preset('sky'));
  });

  test(
    'custom image is copied into support storage and removed on reset',
    () async {
      SharedPreferences.setMockInitialValues({});
      final root = await Directory.systemTemp.createTemp(
        'mithka_wallpaper_test',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final source = File('${root.path}/source.png');
      await source.writeAsBytes(const [137, 80, 78, 71]);
      final support = Directory('${root.path}/support');
      final controller = ChatWallpaperController(
        activeSlot: () => 3,
        supportDirectory: () async => support,
        listenForUpdates: false,
      );

      await controller.setImage(99, source.path);
      final stored = controller.wallpaperFor(99);
      expect(stored?.kind, ChatWallpaperKind.image);
      expect(stored?.imagePath, isNot(source.path));
      expect(await File(stored!.imagePath!).exists(), isTrue);

      await controller.clear(99);
      expect(controller.wallpaperFor(99), isNull);
      expect(await File(stored.imagePath!).exists(), isFalse);
    },
  );

  test('loads Telegram chat backgrounds from getChat', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = ChatWallpaperController(
      activeSlot: () => 0,
      hasActiveClient: () => true,
      listenForUpdates: false,
      query: (request) async {
        expect(request['@type'], 'getChat');
        return {
          '@type': 'chat',
          'id': 42,
          'type': {'@type': 'chatTypePrivate', 'user_id': 7},
          'background': {
            '@type': 'chatBackground',
            'dark_theme_dimming': 31,
            'background': {
              '@type': 'background',
              'id': '9001',
              'type': {
                '@type': 'backgroundTypeFill',
                'fill': {
                  '@type': 'backgroundFillGradient',
                  'top_color': 0x123456,
                  'bottom_color': 0xABCDEF,
                  'rotation_angle': 45,
                },
              },
            },
          },
          'theme': null,
        };
      },
    );

    await controller.load(42);
    final wallpaper = controller.wallpaperFor(42);
    expect(wallpaper?.kind, ChatWallpaperKind.telegram);
    expect(wallpaper?.backgroundId, 9001);
    expect(wallpaper?.remoteType, 'fill');
    expect(wallpaper?.colors, [0x123456, 0xABCDEF]);
    expect(wallpaper?.rotationAngle, 45);
    expect(wallpaper?.darkThemeDimming, 31);
    expect(controller.canApplyOnlyForSelf(42), isTrue);
  });

  test('server chat state replaces stale local-only wallpaper', () async {
    SharedPreferences.setMockInitialValues({});
    final local = ChatWallpaperController(
      activeSlot: () => 0,
      listenForUpdates: false,
    );
    await local.setPreset(42, 'night');

    final synced = ChatWallpaperController(
      activeSlot: () => 0,
      hasActiveClient: () => true,
      listenForUpdates: false,
      query: (_) async => {
        '@type': 'chat',
        'id': 42,
        'type': {'@type': 'chatTypePrivate', 'user_id': 7},
        'background': null,
        'theme': null,
      },
    );

    await synced.load(42);
    expect(synced.wallpaperFor(42), isNull);
  });

  test('applies a preset through setChatBackground for self', () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <Map<String, dynamic>>[];
    final controller = ChatWallpaperController(
      activeSlot: () => 0,
      hasActiveClient: () => true,
      listenForUpdates: false,
      query: (request) async {
        requests.add(request);
        if (request['@type'] == 'getChat') {
          return {
            '@type': 'chat',
            'id': 42,
            'type': {'@type': 'chatTypePrivate', 'user_id': 7},
            'background': null,
            'theme': null,
          };
        }
        return {'@type': 'ok'};
      },
    );

    await controller.load(42);
    await controller.applyWallpaper(
      42,
      const ChatWallpaper.preset('sky'),
      onlyForSelf: true,
    );

    final request = requests.singleWhere(
      (request) => request['@type'] == 'setChatBackground',
    );
    expect(request['chat_id'], 42);
    expect(request['only_for_self'], isTrue);
    expect(request['background'], isNull);
    final type = request['type'] as Map<String, dynamic>;
    expect(type['@type'], 'backgroundTypeFill');
    final fill = type['fill'] as Map<String, dynamic>;
    expect(fill['@type'], 'backgroundFillFreeformGradient');
    expect((fill['colors'] as List).length, 3);
  });

  test('reapplies a Telegram background for both users by remote id', () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <Map<String, dynamic>>[];
    final controller = ChatWallpaperController(
      activeSlot: () => 0,
      hasActiveClient: () => true,
      listenForUpdates: false,
      query: (request) async {
        requests.add(request);
        if (request['@type'] == 'getChat') {
          return {
            '@type': 'chat',
            'id': 42,
            'type': {'@type': 'chatTypePrivate', 'user_id': 7},
            'background': null,
            'theme': null,
          };
        }
        return {'@type': 'ok'};
      },
    );

    await controller.load(42);
    await controller.applyWallpaper(
      42,
      const ChatWallpaper.telegram(
        backgroundId: 9001,
        remoteType: 'wallpaper',
        isBlurred: true,
        darkThemeDimming: 27,
      ),
      onlyForSelf: false,
    );

    final request = requests.singleWhere(
      (request) => request['@type'] == 'setChatBackground',
    );
    expect(request['only_for_self'], isFalse);
    expect(request['dark_theme_dimming'], 27);
    expect(request['background'], {
      '@type': 'inputBackgroundRemote',
      'background_id': 9001,
    });
    expect(request['type'], {
      '@type': 'backgroundTypeWallpaper',
      'is_blurred': true,
      'is_moving': false,
    });
  });

  test('applies emoji chat themes as a shared Telegram theme', () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <Map<String, dynamic>>[];
    final controller = ChatWallpaperController(
      activeSlot: () => 0,
      hasActiveClient: () => true,
      listenForUpdates: false,
      query: (request) async {
        requests.add(request);
        if (request['@type'] == 'getChat') {
          return {
            '@type': 'chat',
            'id': 42,
            'type': {'@type': 'chatTypePrivate', 'user_id': 7},
            'background': null,
            'theme': null,
          };
        }
        return {'@type': 'ok'};
      },
    );

    await controller.load(42);
    await controller.applyTheme(42, '🐣');

    final request = requests.singleWhere(
      (request) => request['@type'] == 'setChatTheme',
    );
    expect(request, {
      '@type': 'setChatTheme',
      'chat_id': 42,
      'theme': {'@type': 'inputChatThemeEmoji', 'name': '🐣'},
    });
    expect(controller.selectionFor(42)?.themeName, '🐣');
    expect(
      requests.where((request) => request['@type'] == 'deleteChatBackground'),
      isEmpty,
    );
  });

  test('sets a global Telegram wallpaper with motion and intensity', () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <Map<String, dynamic>>[];
    final controller = ChatWallpaperController(
      activeSlot: () => 0,
      hasActiveClient: () => true,
      listenForUpdates: false,
      query: (request) async {
        requests.add(request);
        if (request['@type'] == 'setDefaultBackground') {
          return {'@type': 'background', 'id': '123', 'type': request['type']};
        }
        return {'@type': 'ok'};
      },
    );

    await controller.applyDefaultWallpaper(
      const ChatWallpaper.telegram(
        backgroundId: 123,
        remoteType: 'pattern',
        colors: [0x112233],
        intensity: 64,
        isMoving: true,
      ),
      dark: false,
    );

    final request = requests.singleWhere(
      (request) => request['@type'] == 'setDefaultBackground',
    );
    expect(request['for_dark_theme'], isFalse);
    expect(request['background'], {
      '@type': 'inputBackgroundRemote',
      'background_id': 123,
    });
    expect(request['type'], {
      '@type': 'backgroundTypePattern',
      'fill': {'@type': 'backgroundFillSolid', 'color': 0x112233},
      'intensity': 64,
      'is_inverted': false,
      'is_moving': true,
    });
    expect(controller.defaultWallpaper(dark: false)?.isMoving, isTrue);
  });

  test('uploads an extracted theme wallpaper without a remote id', () async {
    SharedPreferences.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp(
      'mithka_embedded_theme_wallpaper',
    );
    addTearDown(() => root.delete(recursive: true));
    final image = File('${root.path}/MountainSolitude.jpg');
    await image.writeAsBytes(const [0xff, 0xd8, 0xff, 0xd9]);
    final requests = <Map<String, dynamic>>[];
    final controller = ChatWallpaperController(
      activeSlot: () => 0,
      hasActiveClient: () => true,
      listenForUpdates: false,
      query: (request) async {
        requests.add(request);
        return {
          '@type': 'background',
          'id': 321,
          'name': 'MountainSolitude',
          'type': request['type'],
        };
      },
    );

    await controller.applyDefaultWallpaper(
      ChatWallpaper.telegram(
        backgroundId: 0,
        remoteType: 'wallpaper',
        imagePath: image.path,
        backgroundName: 'MountainSolitude',
      ),
      dark: true,
    );

    final request = requests.singleWhere(
      (request) => request['@type'] == 'setDefaultBackground',
    );
    expect(request['for_dark_theme'], isTrue);
    expect(request['background'], {
      '@type': 'inputBackgroundLocal',
      'background': {'@type': 'inputFileLocal', 'path': image.path},
    });
    expect(
      controller.defaultWallpaper(dark: true)?.backgroundName,
      'MountainSolitude',
    );
  });

  test(
    'confirmed chat wallpaper is visible without a stale getChat refresh',
    () async {
      SharedPreferences.setMockInitialValues({});
      var getChatCount = 0;
      final controller = ChatWallpaperController(
        activeSlot: () => 0,
        hasActiveClient: () => true,
        listenForUpdates: false,
        query: (request) async {
          if (request['@type'] == 'getChat') {
            getChatCount++;
            return {
              '@type': 'chat',
              'id': 42,
              'type': {'@type': 'chatTypePrivate', 'user_id': 7},
              'background': null,
              'theme': null,
            };
          }
          return {'@type': 'ok'};
        },
      );
      await controller.load(42);
      const mountain = ChatWallpaper.telegram(
        backgroundId: 321,
        remoteType: 'wallpaper',
        backgroundName: 'MountainSolitude',
      );

      await controller.applyWallpaper(42, mountain, onlyForSelf: true);

      expect(getChatCount, 1);
      expect(controller.wallpaperFor(42), mountain);
    },
  );

  test('searches wallpaper photos through the configured inline bot', () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <Map<String, dynamic>>[];
    final controller = ChatWallpaperController(
      activeSlot: () => 0,
      hasActiveClient: () => true,
      listenForUpdates: false,
      query: (request) async {
        requests.add(request);
        return switch (request['@type']) {
          'getOption' => {'@type': 'optionValueString', 'value': 'pic'},
          'searchPublicChat' => {
            '@type': 'chat',
            'id': 77,
            'type': {'@type': 'chatTypePrivate', 'user_id': 88},
          },
          'getInlineQueryResults' => {
            '@type': 'inlineQueryResults',
            'next_offset': 'next',
            'results': [
              {
                '@type': 'inlineQueryResultPhoto',
                'id': 'photo-1',
                'title': 'Blue mountain',
                'photo': {
                  '@type': 'photo',
                  'sizes': [
                    {
                      '@type': 'photoSize',
                      'type': 'x',
                      'width': 1200,
                      'height': 1800,
                      'photo': {
                        '@type': 'file',
                        'id': 901,
                        'size': 100,
                        'expected_size': 100,
                        'local': {
                          '@type': 'localFile',
                          'path': '',
                          'can_be_downloaded': true,
                        },
                        'remote': {'@type': 'remoteFile', 'id': 'remote-901'},
                      },
                    },
                  ],
                },
              },
            ],
          },
          _ => {'@type': 'ok'},
        };
      },
    );

    final page = await controller.searchBackgroundImages('blue mountain');

    expect(page.providerUsername, 'pic');
    expect(page.nextOffset, 'next');
    expect(page.results, hasLength(1));
    expect(page.results.single.fileId, 901);
    final request = requests.singleWhere(
      (request) => request['@type'] == 'getInlineQueryResults',
    );
    expect(request['bot_user_id'], 88);
    expect(request['chat_id'], 77);
    expect(request['query'], 'blue mountain');
  });

  test('wallpaper search retries without a chat context', () async {
    SharedPreferences.setMockInitialValues({});
    final inlineChatIds = <int>[];
    final controller = ChatWallpaperController(
      activeSlot: () => 0,
      hasActiveClient: () => true,
      listenForUpdates: false,
      query: (request) async {
        return switch (request['@type']) {
          'getOption' => {'@type': 'optionValueString', 'value': '@pic'},
          'searchPublicChat' => {
            '@type': 'chat',
            'id': 77,
            'type': {'@type': 'chatTypePrivate', 'user_id': 88},
          },
          'getInlineQueryResults' => () {
            final chatId = request['chat_id'] as int;
            inlineChatIds.add(chatId);
            if (chatId != 0) throw StateError('chat is not initialized');
            return {
              '@type': 'inlineQueryResults',
              'next_offset': '',
              'results': <Object>[],
            };
          }(),
          _ => {'@type': 'ok'},
        };
      },
    );

    final page = await controller.searchBackgroundImages('blue');

    expect(page.providerUsername, 'pic');
    expect(page.results, isEmpty);
    expect(inlineChatIds, [77, 0]);
  });

  test('installed PNG pattern documents are prepared and resolved', () async {
    SharedPreferences.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp(
      'mithka_png_pattern_test',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final source = File('${root.path}/pattern-document');
    await source.writeAsBytes(const [
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
    ]);
    final controller = ChatWallpaperController(
      activeSlot: () => 0,
      hasActiveClient: () => true,
      supportDirectory: () async => Directory('${root.path}/support'),
      listenForUpdates: false,
      query: (_) async => {
        '@type': 'backgrounds',
        'backgrounds': [
          {
            '@type': 'background',
            'id': '51',
            'name': 'Paris',
            'document': {
              '@type': 'document',
              'mime_type': 'image/png',
              'document': {
                '@type': 'file',
                'id': 71,
                'local': {'@type': 'localFile', 'path': source.path},
              },
            },
            'type': {
              '@type': 'backgroundTypePattern',
              'fill': {'@type': 'backgroundFillSolid', 'color': 0x224466},
              'intensity': 45,
              'is_inverted': false,
              'is_moving': false,
            },
          },
        ],
      },
    );

    final pattern = (await controller.installedBackgrounds(dark: false)).single;
    expect(pattern.backgroundName, 'Paris');
    final resolved = Completer<void>();
    controller.addListener(() {
      if (!resolved.isCompleted) resolved.complete();
    });
    controller.resolvedWallpaper(pattern);
    await resolved.future.timeout(const Duration(seconds: 2));

    final prepared = controller.resolvedWallpaper(pattern);
    expect(prepared.imagePath, endsWith('.png'));
    expect(
      await File(prepared.imagePath!).readAsBytes(),
      await source.readAsBytes(),
    );
  });

  test(
    'official TGV line art is preserved and keeps compound interiors clear',
    () async {
      SharedPreferences.setMockInitialValues({});
      const svg = '''<?xml version="1.0" encoding="utf-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <style>.line{fill:none;stroke:#000;stroke-width:4;stroke-linecap:round;stroke-linejoin:round}</style>
  <path class="line" d="M10 10H90V90H10Z M30 30H70V70H30Z"/>
</svg>''';
      final root = await Directory.systemTemp.createTemp(
        'mithka_tgv_pattern_test',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final source = File('${root.path}/pattern.tgv');
      await source.writeAsBytes(GZipEncoder().encode(utf8.encode(svg))!);
      final controller = ChatWallpaperController(
        activeSlot: () => 0,
        hasActiveClient: () => true,
        supportDirectory: () async => Directory('${root.path}/support'),
        listenForUpdates: false,
        query: (_) async => {
          '@type': 'backgrounds',
          'backgrounds': [
            {
              '@type': 'background',
              'id': '52',
              'document': {
                '@type': 'document',
                'mime_type': 'application/x-tgwallpattern',
                'document': {
                  '@type': 'file',
                  'id': 72,
                  'local': {'@type': 'localFile', 'path': source.path},
                },
              },
              'type': {
                '@type': 'backgroundTypePattern',
                'fill': {'@type': 'backgroundFillSolid', 'color': 0x224466},
                'intensity': 45,
                'is_inverted': false,
                'is_moving': false,
              },
            },
          ],
        },
      );

      final pattern = (await controller.installedBackgrounds(
        dark: false,
      )).single;
      final resolved = Completer<void>();
      controller.addListener(() {
        if (!resolved.isCompleted) resolved.complete();
      });
      controller.resolvedWallpaper(pattern);
      await resolved.future.timeout(const Duration(seconds: 5));
      final prepared = controller.resolvedWallpaper(pattern);
      expect(prepared.imagePath, contains('pattern_raster_v1_'));
      final rendered = image_lib.decodePng(
        await File(prepared.imagePath!).readAsBytes(),
      );
      expect(rendered, isNotNull);
      int alphaAt(int x, int y) {
        final scaledX = (x * rendered!.width / 100).round().clamp(
          0,
          rendered.width - 1,
        );
        final scaledY = (y * rendered.height / 100).round().clamp(
          0,
          rendered.height - 1,
        );
        return rendered.getPixel(scaledX, scaledY).a.toInt();
      }

      expect(alphaAt(50, 10), greaterThan(0));
      expect(alphaAt(20, 20), 0);
      expect(alphaAt(50, 50), 0);
    },
  );

  test('uses live group boost features to gate custom wallpaper', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = ChatWallpaperController(
      activeSlot: () => 0,
      hasActiveClient: () => true,
      listenForUpdates: false,
      query: (request) async {
        return switch (request['@type']) {
          'getChat' => {
            '@type': 'chat',
            'id': 55,
            'type': {
              '@type': 'chatTypeSupergroup',
              'supergroup_id': 9,
              'is_channel': false,
            },
            'background': null,
            'theme': null,
          },
          'getSupergroup' => {
            '@type': 'supergroup',
            'id': 9,
            'is_channel': false,
            'boost_level': 1,
          },
          'getChatBoostStatus' => {'@type': 'chatBoostStatus', 'level': 1},
          'getChatBoostFeatures' => {
            '@type': 'chatBoostFeatures',
            'min_custom_background_boost_level': 2,
            'features': [
              {
                '@type': 'chatBoostLevelFeatures',
                'level': 1,
                'can_set_custom_background': false,
                'chat_theme_background_count': 1,
              },
              {
                '@type': 'chatBoostLevelFeatures',
                'level': 2,
                'can_set_custom_background': true,
                'chat_theme_background_count': 2,
              },
            ],
          },
          _ => {'@type': 'ok'},
        };
      },
    );

    await controller.load(55);
    final access = controller.accessFor(
      55,
      const ChatWallpaper.telegram(backgroundId: 12, remoteType: 'wallpaper'),
    );
    expect(access.allowed, isFalse);
    expect(access.currentLevel, 1);
    expect(access.requiredLevel, 2);
  });

  test(
    'a confirmed theme save does not depend on a follow-up refresh',
    () async {
      SharedPreferences.setMockInitialValues({});
      var getChatCount = 0;
      final controller = ChatWallpaperController(
        activeSlot: () => 0,
        hasActiveClient: () => true,
        listenForUpdates: false,
        query: (request) async {
          if (request['@type'] == 'getChat') {
            getChatCount++;
            if (getChatCount > 1) throw StateError('temporarily unavailable');
            return {
              '@type': 'chat',
              'id': 42,
              'type': {'@type': 'chatTypePrivate', 'user_id': 7},
              'background': null,
              'theme': null,
            };
          }
          return {'@type': 'ok'};
        },
      );

      await controller.load(42);
      await controller.applyTheme(42, '❄️');

      expect(getChatCount, 1);
      expect(controller.selectionFor(42)?.themeName, '❄️');
    },
  );

  test('uses Telegram emoji theme background and outgoing palette', () async {
    SharedPreferences.setMockInitialValues({});
    Map<String, dynamic> settings(int backgroundColor, int outgoingColor) => {
      '@type': 'themeSettings',
      'background': {
        '@type': 'background',
        'id': '18',
        'type': {
          '@type': 'backgroundTypeFill',
          'fill': {'@type': 'backgroundFillSolid', 'color': backgroundColor},
        },
      },
      'outgoing_message_fill': {
        '@type': 'backgroundFillSolid',
        'color': outgoingColor,
      },
      'outgoing_message_accent_color': outgoingColor,
    };

    final themesUpdate = {
      '@type': 'updateEmojiChatThemes',
      'chat_themes': [
        {
          '@type': 'emojiChatTheme',
          'name': '🐣',
          'light_settings': settings(0xFFF7C4, 0x44AA66),
          'dark_settings': settings(0x102030, 0x337755),
        },
      ],
    };
    final controller = ChatWallpaperController(
      activeSlot: () => 0,
      hasActiveClient: () => true,
      listenForUpdates: false,
      latestEmojiChatThemes: () => themesUpdate,
      query: (_) async => {
        '@type': 'chat',
        'id': 99,
        'type': {'@type': 'chatTypePrivate', 'user_id': 8},
        'background': null,
        'theme': {'@type': 'chatThemeEmoji', 'name': '🐣'},
      },
    );

    await controller.load(99);
    expect(controller.selectionFor(99), const ChatWallpaper.theme('🐣'));
    expect(controller.wallpaperFor(99)?.colors, [0xFFF7C4]);
    expect(controller.themeStyleFor(99, dark: false)?.outgoingColors, [
      0x44AA66,
    ]);
    final lightStyle = controller.themeStyleFor(99, dark: false)!;
    final darkStyle = controller.themeStyleFor(99, dark: true)!;
    expect(lightStyle.incomingColor, isNot(const Color(0xFFFFFFFF)));
    expect(darkStyle.incomingColor, isNot(const Color(0xFF202427)));
    expect(lightStyle.outgoingColor?.toARGB32(), 0xFF44AA66);
    expect(controller.wallpaperFor(99, dark: true)?.colors, [0x102030]);
  });

  test(
    'theme lists can defer patterns while full picker options retain them',
    () async {
      SharedPreferences.setMockInitialValues({});
      final root = await Directory.systemTemp.createTemp(
        'mithka_theme_card_pattern',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final pattern = File('${root.path}/pattern.svg');
      await pattern.writeAsString('<svg/>');
      final themesUpdate = {
        '@type': 'updateEmojiChatThemes',
        'chat_themes': [
          {
            '@type': 'emojiChatTheme',
            'name': '❄️',
            'light_settings': {
              '@type': 'themeSettings',
              'background': {
                '@type': 'background',
                'id': '18',
                'document': {
                  '@type': 'document',
                  'mime_type': 'image/svg+xml',
                  'document': {
                    '@type': 'file',
                    'id': 44,
                    'local': {'@type': 'localFile', 'path': pattern.path},
                  },
                },
                'type': {
                  '@type': 'backgroundTypePattern',
                  'fill': {'@type': 'backgroundFillSolid', 'color': 0x224466},
                  'intensity': 50,
                  'is_inverted': false,
                },
              },
              'outgoing_message_fill': null,
            },
            'dark_settings': null,
          },
        ],
      };
      final controller = ChatWallpaperController(
        activeSlot: () => 0,
        hasActiveClient: () => false,
        latestEmojiChatThemes: () => themesUpdate,
        listenForUpdates: false,
      );
      await controller.load(42);

      final card = controller
          .availableThemes(dark: false, resolvePatterns: false)
          .single;
      expect(card.wallpaper?.remoteType, 'pattern');
      expect(card.wallpaper?.colors, [0x224466]);
      expect(card.wallpaper?.fileId, 0);
      expect(card.wallpaper?.imagePath, isNull);

      var notifications = 0;
      controller.addListener(() => notifications++);
      final full = controller.availableThemes(dark: false).single;
      expect(full.wallpaper?.imagePath, pattern.path);
      final fullGlobal = controller
          .globalThemeOptions(dark: false, resolvePatterns: true)
          .where((option) => option.emoji == '❄️')
          .single;
      expect(fullGlobal.wallpaper?.fileId, 44);
      expect(fullGlobal.wallpaper?.imagePath, pattern.path);
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 0);
    },
  );

  test('loads and applies collectible gift chat themes', () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <Map<String, dynamic>>[];
    Map<String, dynamic> settings(int color) => {
      '@type': 'themeSettings',
      'background': {
        '@type': 'background',
        'id': '8',
        'type': {
          '@type': 'backgroundTypeFill',
          'fill': {'@type': 'backgroundFillSolid', 'color': color},
        },
      },
      'outgoing_message_fill': {'@type': 'backgroundFillSolid', 'color': color},
      'outgoing_message_accent_color': color,
    };
    final controller = ChatWallpaperController(
      activeSlot: () => 0,
      hasActiveClient: () => true,
      listenForUpdates: false,
      query: (request) async {
        requests.add(request);
        if (request['@type'] == 'getChat') {
          return {
            '@type': 'chat',
            'id': 42,
            'type': {'@type': 'chatTypePrivate', 'user_id': 7},
            'background': null,
            'theme': null,
          };
        }
        if (request['@type'] == 'getGiftChatThemes') {
          return {
            '@type': 'giftChatThemes',
            'themes': [
              {
                '@type': 'giftChatTheme',
                'gift': {
                  '@type': 'upgradedGift',
                  'name': 'MountainGift-1',
                  'title': 'Mountain Gift',
                },
                'light_settings': settings(0x88AA99),
                'dark_settings': settings(0x33443F),
              },
            ],
            'next_offset': '',
          };
        }
        return {'@type': 'ok'};
      },
    );

    await controller.load(42);
    await controller.loadGiftThemes();
    final gift = controller
        .availableThemes(dark: false)
        .singleWhere((theme) => theme.kind == ChatThemeKind.gift);
    expect(gift.name, 'MountainGift-1');
    expect(gift.label, 'Mountain Gift');

    await controller.applyTheme(42, gift.name, kind: ChatThemeKind.gift);
    final request = requests.singleWhere(
      (request) => request['@type'] == 'setChatTheme',
    );
    expect(request['theme'], {
      '@type': 'inputChatThemeGift',
      'name': 'MountainGift-1',
    });
  });

  test('renders and reapplies channel chat-theme backgrounds', () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <Map<String, dynamic>>[];
    final themesUpdate = {
      '@type': 'updateEmojiChatThemes',
      'chat_themes': [
        {
          '@type': 'emojiChatTheme',
          'name': '🏔️',
          'light_settings': {
            '@type': 'themeSettings',
            'background': {
              '@type': 'background',
              'id': '91',
              'type': {
                '@type': 'backgroundTypeFill',
                'fill': {'@type': 'backgroundFillSolid', 'color': 0xDDEEDD},
              },
            },
            'outgoing_message_fill': null,
            'outgoing_message_accent_color': 0,
          },
          'dark_settings': {
            '@type': 'themeSettings',
            'background': null,
            'outgoing_message_fill': null,
            'outgoing_message_accent_color': 0,
          },
        },
      ],
    };
    final controller = ChatWallpaperController(
      activeSlot: () => 0,
      hasActiveClient: () => true,
      latestEmojiChatThemes: () => themesUpdate,
      listenForUpdates: false,
      query: (request) async {
        requests.add(request);
        if (request['@type'] == 'getChat') {
          return {
            '@type': 'chat',
            'id': 55,
            'type': {
              '@type': 'chatTypeSupergroup',
              'supergroup_id': 9,
              'is_channel': true,
            },
            'background': {
              '@type': 'chatBackground',
              'dark_theme_dimming': 0,
              'background': {
                '@type': 'background',
                'id': '92',
                'type': {
                  '@type': 'backgroundTypeChatTheme',
                  'theme_name': '🏔️',
                },
              },
            },
            'theme': null,
          };
        }
        return {'@type': 'ok'};
      },
    );

    await controller.load(55);
    expect(controller.canApplyTheme(55), isTrue);
    expect(
      controller
          .availableThemes(dark: false, chatId: 55)
          .map((theme) => theme.kind),
      everyElement(ChatThemeKind.emoji),
    );
    expect(controller.wallpaperFor(55)?.colors, [0xDDEEDD]);
    final selection = controller.selectionFor(55);
    expect(selection?.remoteType, 'chatTheme');
    expect(selection?.themeName, '🏔️');

    await controller.applyWallpaper(55, selection, onlyForSelf: false);
    final request = requests.singleWhere(
      (request) => request['@type'] == 'setChatBackground',
    );
    expect(request['background'], isNull);
    expect(request['type'], {
      '@type': 'backgroundTypeChatTheme',
      'theme_name': '🏔️',
    });
  });

  test('explicit chat wallpaper remains independent of global theme', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = ChatWallpaperController(
      activeSlot: () => 0,
      hasActiveClient: () => true,
      latestEmojiChatThemes: () => {
        '@type': 'updateEmojiChatThemes',
        'chat_themes': [
          {
            '@type': 'emojiChatTheme',
            'name': '🌷',
            'light_settings': {
              '@type': 'themeSettings',
              'base_theme': {'@type': 'builtInThemeClassic'},
              'background': {
                '@type': 'background',
                'id': 22,
                'type': {
                  '@type': 'backgroundTypeFill',
                  'fill': {'@type': 'backgroundFillSolid', 'color': 0xF2DDEE},
                },
              },
              'outgoing_message_fill': {
                '@type': 'backgroundFillSolid',
                'color': 0xDD77AA,
              },
            },
            'dark_settings': null,
          },
        ],
      },
      listenForUpdates: false,
      query: (request) async {
        if (request['@type'] == 'setDefaultBackground') {
          return {
            '@type': 'background',
            'id': 77,
            'type': {
              '@type': 'backgroundTypeFill',
              'fill': {'@type': 'backgroundFillSolid', 'color': 0x123456},
            },
          };
        }
        return {'@type': 'ok'};
      },
    );
    addTearDown(controller.dispose);

    await controller.loadGlobalChatThemes();
    await controller.applyDefaultWallpaper(
      const ChatWallpaper.telegram(
        backgroundId: 0,
        remoteType: 'fill',
        colors: [0x123456],
      ),
      dark: false,
    );
    await controller.setGlobalChatTheme('🌷', dark: false);

    expect(controller.defaultWallpaper(dark: false)?.colors, [0x123456]);
    expect(controller.globalThemeWallpaperFor(dark: false)?.colors, [0xF2DDEE]);
  });

  test('encountered chat wallpapers are saved per account for reuse', () async {
    SharedPreferences.setMockInitialValues({});
    final first = ChatWallpaperController(
      activeSlot: () => 4,
      hasActiveClient: () => true,
      listenForUpdates: false,
      query: (_) async => {
        '@type': 'chat',
        'id': 42,
        'type': {'@type': 'chatTypePrivate', 'user_id': 7},
        'background': {
          '@type': 'chatBackground',
          'dark_theme_dimming': 0,
          'background': {
            '@type': 'background',
            'id': 701,
            'type': {
              '@type': 'backgroundTypePattern',
              'fill': {'@type': 'backgroundFillSolid', 'color': 0x334455},
              'intensity': 37,
              'is_inverted': false,
              'is_moving': true,
            },
          },
        },
        'theme': null,
      },
    );
    await first.load(42);
    await pumpEventQueue();
    expect(first.savedBackgrounds.single.backgroundId, 701);
    first.dispose();

    final restored = ChatWallpaperController(
      activeSlot: () => 4,
      listenForUpdates: false,
    );
    addTearDown(restored.dispose);
    final saved = await restored.loadSavedBackgrounds();
    expect(saved.single.backgroundId, 701);
    expect(saved.single.intensity, 37);
    expect(saved.single.isMoving, isTrue);
  });
}
