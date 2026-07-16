import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_wallpaper.dart';
import 'package:mithka/theme/telegram_cloud_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads all saved Telegram cloud themes in server order', () async {
    final requests = <Map<String, dynamic>>[];
    final service = TelegramCloudThemeService(
      query: (request) async {
        requests.add(request);
        if (request['@type'] == 'getInstalledCloudThemes') {
          expect(request['theme_format'], 'ios');
          return {
            '@type': 'installedCloudThemes',
            'themes': const [
              {
                '@type': 'installedCloudTheme',
                'slug': 'MountainSolitude',
                'title': 'Mountain Solitude',
              },
              {
                '@type': 'installedCloudTheme',
                'slug': 'SepiaBlues',
                'title': 'Sepia Blues',
              },
              {
                '@type': 'installedCloudTheme',
                'slug': 'WeChatifyDark',
                'title': 'WeChatify Dark',
              },
            ],
          };
        }
        return _previewFor(_slugFromPreviewRequest(request));
      },
    );

    final themes = await service.loadInstalled();

    expect(themes.map((theme) => theme.slug), [
      'MountainSolitude',
      'SepiaBlues',
      'WeChatifyDark',
    ]);
    expect(themes.map((theme) => theme.rawTitle), [
      'Mountain Solitude',
      'Sepia Blues',
      'WeChatify Dark',
    ]);
    expect(requests.length, 4);
  });

  test(
    'keeps local imports when the native extension is unavailable',
    () async {
      final local = [_theme('LocalOne'), _theme('LocalTwo')];
      final service = TelegramCloudThemeService(
        query: (_) => Future.error(StateError('Unknown class')),
      );

      final themes = await service.loadInstalled(fallback: local);

      expect(themes, local);
    },
  );

  test('old native binary still rehydrates local theme wallpaper', () async {
    const stale = TelegramCloudTheme(
      slug: 'MountainSolitude',
      rawTitle: 'Stale Mountain Solitude',
      baseTheme: 'builtInThemeNight',
      accentColorValue: 0x5F9EA0,
      outgoingColors: [0xF3B4BD],
      palette: {},
      wallpaper: ChatWallpaper.telegram(
        backgroundId: 81,
        remoteType: 'wallpaper',
        imagePath: '/old/app/container/mountain.jpg',
      ),
    );
    final requests = <String>[];
    final service = TelegramCloudThemeService(
      query: (request) async {
        requests.add(request['@type'] as String);
        if (request['@type'] == 'getInstalledCloudThemes') {
          throw StateError('Unknown class');
        }
        return _previewFor(_slugFromPreviewRequest(request));
      },
    );

    final themes = await service.loadInstalled(fallback: const [stale]);

    expect(requests, ['getInstalledCloudThemes', 'getLinkPreview']);
    expect(themes.single.slug, 'MountainSolitude');
    expect(themes.single.wallpaper?.imagePath, isNull);
    expect(themes.single.wallpaper?.colors, [0x101820]);
  });

  test('one unavailable server theme does not hide the rest', () async {
    final retained = _theme('Unavailable', title: 'Retained local copy');
    final service = TelegramCloudThemeService(
      query: (request) async {
        if (request['@type'] == 'getInstalledCloudThemes') {
          return {
            '@type': 'installedCloudThemes',
            'themes': const [
              {'slug': 'Available', 'title': 'Available cloud theme'},
              {'slug': 'Unavailable', 'title': 'Unavailable cloud theme'},
              {'slug': 'Available', 'title': 'Duplicate'},
            ],
          };
        }
        final slug = _slugFromPreviewRequest(request);
        if (slug == 'Unavailable') throw StateError('deleted document');
        return _previewFor(slug);
      },
    );

    final themes = await service.loadInstalled(
      fallback: [retained, _theme('LocalOnly')],
    );

    expect(themes.map((theme) => theme.slug), [
      'Available',
      'Unavailable',
      'LocalOnly',
    ]);
    expect(themes[1].rawTitle, 'Retained local copy');
  });

  test('three hydrated themes persist and refresh a stale selection', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const stale = TelegramCloudTheme(
      slug: 'MountainSolitude',
      rawTitle: 'Stale Mountain Solitude',
      baseTheme: 'builtInThemeNight',
      accentColorValue: 0x5F9EA0,
      outgoingColors: [0xF3B4BD],
      palette: {},
      wallpaper: ChatWallpaper.telegram(
        backgroundId: 81,
        remoteType: 'wallpaper',
        imagePath: '/old/app/container/mountain.jpg',
      ),
    );
    final controller = ThemeController(prefs)..installCloudTheme(stale);
    final service = TelegramCloudThemeService(
      query: (request) async {
        if (request['@type'] == 'getInstalledCloudThemes') {
          return {
            '@type': 'installedCloudThemes',
            'themes': const [
              {'slug': 'MountainSolitude', 'title': 'Mountain Solitude'},
              {'slug': 'SepiaBlues', 'title': 'Sepia Blues'},
              {'slug': 'wechatify_dark', 'title': 'WeChatify Dark'},
            ],
          };
        }
        return _previewFor(_slugFromPreviewRequest(request));
      },
    );

    final hydrated = await service.loadInstalled(
      fallback: controller.installedCloudThemes,
    );
    controller.synchronizeInstalledCloudThemes(hydrated);

    expect(controller.installedCloudThemes.map((theme) => theme.slug), [
      'MountainSolitude',
      'SepiaBlues',
      'wechatify_dark',
    ]);
    expect(controller.darkCloudTheme?.rawTitle, 'Mountain Solitude');
    expect(controller.darkCloudTheme?.wallpaper?.imagePath, isNull);
    expect(controller.darkCloudTheme?.wallpaper?.colors, [0x101820]);

    final restored = ThemeController(prefs);
    expect(
      restored.installedCloudThemes.map((theme) => theme.slug),
      unorderedEquals(['MountainSolitude', 'SepiaBlues', 'wechatify_dark']),
    );
    expect(restored.darkCloudTheme?.wallpaper?.imagePath, isNull);
    expect(restored.darkCloudTheme?.wallpaper?.colors, [0x101820]);
  });
}

String _slugFromPreviewRequest(Map<String, dynamic> request) {
  final formatted = request['text'] as Map<String, dynamic>;
  final uri = Uri.parse(formatted['text'] as String);
  return uri.pathSegments.last;
}

Map<String, dynamic> _previewFor(String slug) => {
  '@type': 'linkPreview',
  'title': 'Preview $slug',
  'type': {
    '@type': 'linkPreviewTypeTheme',
    'documents': const <Object>[],
    'settings': {
      '@type': 'themeSettings',
      'base_theme': {'@type': 'builtInThemeDay'},
      'accent_color': 0x2481CC,
      'outgoing_message_fill': {
        '@type': 'backgroundFillSolid',
        'color': 0xD8F3FF,
      },
      'background': {
        '@type': 'background',
        'id': '81',
        'type': {
          '@type': 'backgroundTypeFill',
          'fill': {'@type': 'backgroundFillSolid', 'color': 0x101820},
        },
      },
    },
  },
};

TelegramCloudTheme _theme(String slug, {String? title}) => TelegramCloudTheme(
  slug: slug,
  rawTitle: title ?? slug,
  baseTheme: 'builtInThemeDay',
  accentColorValue: 0x2481CC,
  outgoingColors: [0xD8F3FF],
  palette: {},
);
