import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_wallpaper.dart';
import 'package:mithka/profile/profile_theme_backdrop.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  test('selects explicit wallpaper, then cloud theme, then global theme', () {
    const explicit = ChatWallpaper.preset('aurora');
    const cloud = ChatWallpaper.preset('blossom');
    const global = ChatWallpaper.preset('classic');

    expect(
      selectProfileThemeWallpaper(
        themingEnabled: true,
        defaultWallpaper: explicit,
        cloudThemeWallpaper: cloud,
        globalThemeWallpaper: global,
      ),
      same(explicit),
    );
    expect(
      selectProfileThemeWallpaper(
        themingEnabled: true,
        defaultWallpaper: null,
        cloudThemeWallpaper: cloud,
        globalThemeWallpaper: global,
      ),
      same(cloud),
    );
    expect(
      selectProfileThemeWallpaper(
        themingEnabled: true,
        defaultWallpaper: null,
        cloudThemeWallpaper: null,
        globalThemeWallpaper: global,
      ),
      same(global),
    );
  });

  test('does not use a wallpaper when theming is disabled', () {
    expect(
      selectProfileThemeWallpaper(
        themingEnabled: false,
        defaultWallpaper: const ChatWallpaper.preset('aurora'),
        cloudThemeWallpaper: const ChatWallpaper.preset('blossom'),
        globalThemeWallpaper: const ChatWallpaper.preset('classic'),
      ),
      isNull,
    );
  });

  testWidgets('backdrop blurs wallpaper with themed surfaces and brightness', (
    tester,
  ) async {
    final colors = AppColors.dark.copyWith(
      background: const Color(0xFF102030),
      card: const Color(0xFF203040),
    );
    const wallpaper = ChatWallpaper.preset('aurora');
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, extensions: [colors]),
        home: const SizedBox(
          width: 320,
          height: 180,
          child: ProfileThemeBackdrop(wallpaper: wallpaper),
        ),
      ),
    );

    expect(find.byType(ImageFiltered), findsOneWidget);
    final rendered = tester.widget<ChatWallpaperBackground>(
      find.byType(ChatWallpaperBackground),
    );
    expect(rendered.wallpaper, same(wallpaper));
    expect(rendered.fallbackColor, colors.background);
    expect(rendered.brightness, Brightness.dark);
    expect(rendered.imageScrim, colors.background.withValues(alpha: 0));

    final overlay = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('profileThemeBackdropOverlay')),
    );
    final gradient = (overlay.decoration as BoxDecoration).gradient!;
    expect(gradient.colors, [
      colors.background.withValues(alpha: 0.60),
      colors.card.withValues(alpha: 0.76),
    ]);
  });
}
