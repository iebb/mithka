import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_appearance_message_preview.dart';
import 'package:mithka/chat/chat_wallpaper.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('preview parser preserves the chat background wrapper', () {
    final controller = ChatWallpaperController(
      listenForUpdates: false,
      hasActiveClient: () => false,
    );
    addTearDown(controller.dispose);

    final wallpaper = controller.previewWallpaperFromChatBackground({
      '@type': 'chatBackground',
      'dark_theme_dimming': 37,
      'background': {
        '@type': 'background',
        'id': 71,
        'name': 'sample',
        'type': {
          '@type': 'backgroundTypeFill',
          'fill': {
            '@type': 'backgroundFillGradient',
            'top_color': 0x102030,
            'bottom_color': 0x405060,
            'rotation_angle': 45,
          },
        },
      },
    });

    expect(wallpaper?.backgroundId, 71);
    expect(wallpaper?.remoteType, 'fill');
    expect(wallpaper?.colors, [0x102030, 0x405060]);
    expect(wallpaper?.rotationAngle, 45);
    expect(wallpaper?.darkThemeDimming, 37);
  });

  testWidgets('wallpaper service message renders a bounded visual card', (
    tester,
  ) async {
    final controller = ChatWallpaperController(
      listenForUpdates: false,
      hasActiveClient: () => false,
    );
    addTearDown(controller.dispose);
    await _pump(
      tester,
      controller: controller,
      preview: MessageAppearancePreview.background({
        '@type': 'chatBackground',
        'dark_theme_dimming': 0,
        'background': {
          '@type': 'background',
          'id': 72,
          'type': {
            '@type': 'backgroundTypeFill',
            'fill': {'@type': 'backgroundFillSolid', 'color': 0x315A76},
          },
        },
      }),
    );

    final preview = find.byKey(
      const ValueKey('chat-appearance-message-messageChatSetBackground'),
    );
    expect(preview, findsOneWidget);
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('appearance-preview-card-surface')),
          )
          .width,
      lessThanOrEqualTo(300),
    );
    expect(find.text('Chat wallpaper changed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('emoji theme service message uses its Telegram theme colors', (
    tester,
  ) async {
    Map<String, dynamic> settings(int background, int outgoing) => {
      '@type': 'themeSettings',
      'background': {
        '@type': 'background',
        'id': 73,
        'type': {
          '@type': 'backgroundTypeFill',
          'fill': {'@type': 'backgroundFillSolid', 'color': background},
        },
      },
      'outgoing_message_fill': {
        '@type': 'backgroundFillSolid',
        'color': outgoing,
      },
      'accent_color': 0x2255AA,
      'outgoing_message_accent_color': 0x2255AA,
    };
    final controller = ChatWallpaperController(
      listenForUpdates: false,
      hasActiveClient: () => false,
      latestEmojiChatThemes: () => {
        '@type': 'updateEmojiChatThemes',
        'chat_themes': [
          {
            '@type': 'emojiChatTheme',
            'name': '🌊',
            'light_settings': settings(0xDDEEFF, 0x4488CC),
            'dark_settings': settings(0x102030, 0x225577),
          },
        ],
      },
    );
    addTearDown(controller.dispose);
    await controller.loadGlobalChatThemes();
    await _pump(
      tester,
      controller: controller,
      preview: MessageAppearancePreview.theme({
        '@type': 'chatThemeEmoji',
        'name': '🌊',
      }),
    );

    expect(
      find.byKey(const ValueKey('chat-appearance-message-messageChatSetTheme')),
      findsOneWidget,
    );
    final card = tester.widget<ChatAppearancePreviewCard>(
      find.byType(ChatAppearancePreviewCard),
    );
    expect(card.style?.outgoingColor?.toARGB32(), 0xFF4488CC);
    expect(card.wallpaper?.colors, [0xDDEEFF]);
  });

  testWidgets('reset theme keeps the ordinary service banner fallback', (
    tester,
  ) async {
    final controller = ChatWallpaperController(
      listenForUpdates: false,
      hasActiveClient: () => false,
    );
    addTearDown(controller.dispose);
    await _pump(
      tester,
      controller: controller,
      preview: MessageAppearancePreview.theme(null),
    );

    expect(
      find.byKey(const ValueKey('appearance-preview-fallback')),
      findsOneWidget,
    );
    expect(find.byType(ChatAppearancePreviewCard), findsNothing);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required ChatWallpaperController controller,
  required MessageAppearancePreview preview,
}) async {
  SharedPreferences.setMockInitialValues({'appearanceThemingEnabled': true});
  final preferences = await SharedPreferences.getInstance();
  final theme = ThemeController(preferences);
  addTearDown(theme.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        home: Scaffold(
          body: SizedBox(
            width: 390,
            child: ChatAppearanceMessagePreview(
              preview: preview,
              label: 'Chat wallpaper changed',
              controller: controller,
              fallback: const SizedBox(
                key: ValueKey('appearance-preview-fallback'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
