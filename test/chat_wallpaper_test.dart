import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_wallpaper.dart';
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
    'theme cards omit pattern documents and resolved SVGs stay settled',
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
}
