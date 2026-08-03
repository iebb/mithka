import 'package:flutter/material.dart' show Theme;
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'chat_appearance_preview.dart';
import 'chat_wallpaper.dart';

/// A visual service-message card for Telegram wallpaper and chat-theme
/// changes. Reset or unavailable themes keep the existing text banner.
class ChatAppearanceMessagePreview extends StatelessWidget {
  const ChatAppearanceMessagePreview({
    super.key,
    required this.preview,
    required this.label,
    required this.controller,
    required this.fallback,
  });

  final MessageAppearancePreview preview;
  final String label;
  final ChatWallpaperController controller;
  final Widget fallback;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      ChatWallpaper? wallpaper;
      ChatThemeStyle? style;
      if (preview.contentType == 'messageChatSetBackground') {
        wallpaper = controller.previewWallpaperFromChatBackground(
          preview.chatBackground,
        );
        if (wallpaper == null) return fallback;
        wallpaper = controller.resolvedWallpaper(wallpaper);
      } else if (preview.contentType == 'messageChatSetTheme') {
        final option = controller.previewThemeFromChatTheme(
          preview.chatTheme,
          dark: dark,
        );
        if (option == null) return fallback;
        wallpaper = option.wallpaper == null
            ? null
            : controller.resolvedWallpaper(option.wallpaper!);
        style = option.style;
      } else {
        return fallback;
      }
      return ChatAppearancePreviewCard(
        key: ValueKey('chat-appearance-message-${preview.contentType}'),
        wallpaper: wallpaper,
        style: style,
        label: label,
        brightness: dark ? Brightness.dark : Brightness.light,
      );
    },
  );
}

/// Shared compact preview used by service messages and background-link
/// confirmation dialogs.
class ChatAppearancePreviewCard extends StatelessWidget {
  const ChatAppearancePreviewCard({
    super.key,
    required this.wallpaper,
    required this.label,
    this.style,
    this.brightness,
  });

  final ChatWallpaper? wallpaper;
  final ChatThemeStyle? style;
  final String label;
  final Brightness? brightness;

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<ThemeController>();
    final targetBrightness =
        brightness ?? MediaQuery.platformBrightnessOf(context);
    final cloudTheme = appearance.cloudThemeFor(targetBrightness);
    final colors = cloudTheme?.uiColors ?? context.colors;
    final incomingBubble =
        style?.incomingColor ??
        cloudTheme?.incomingColor ??
        colors.bubbleIncoming;
    final outgoingBubble =
        style?.outgoingColor ?? cloudTheme?.outgoingColor ?? colors.linkBlue;
    final incomingText =
        style?.incomingTextColor ??
        cloudTheme?.incomingTextColor ??
        colors.bubbleIncomingText;
    final outgoingText =
        style?.outgoingTextColor ??
        cloudTheme?.outgoingTextColor ??
        readableForeground(outgoingBubble);
    final nameColor =
        style?.nameColor ?? cloudTheme?.accentColor ?? colors.linkBlue;
    final plate = servicePlateBackground(colors);

    return Semantics(
      label: label,
      image: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                key: const ValueKey('appearance-preview-card-surface'),
                height: 220,
                child: ChatWallpaperBackground(
                  wallpaper: wallpaper,
                  fallbackColor: colors.chatBackground,
                  brightness: targetBrightness,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 34),
                        child: ChatAppearancePreview(
                          incomingBubbleColor: incomingBubble,
                          incomingTextColor: incomingText,
                          outgoingBubbleColor: outgoingBubble,
                          outgoingTextColor: outgoingText,
                          incomingNameColor: nameColor,
                          outgoingNameColor: nameColor,
                          incomingMessage: AppStringKeys
                              .chatWallpaperPreviewIncoming
                              .l10n(context),
                          outgoingMessage: AppStringKeys
                              .chatWallpaperPreviewOutgoing
                              .l10n(context),
                          senderNameReadabilityMode:
                              appearance.senderNameReadabilityMode,
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: plate,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x26000000),
                                  blurRadius: 6,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyle.caption(
                                  servicePlateForeground(plate),
                                ).copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
