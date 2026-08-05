import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../components/photo_avatar.dart';
import '../theme/app_theme.dart';
import '../theme/message_bubble_background.dart';
import 'stretchable_message_bubble_background.dart';
import 'chat_wallpaper.dart';

class MessageBubbleChatPreview extends StatelessWidget {
  const MessageBubbleChatPreview({
    super.key,
    required this.incomingBackground,
    required this.outgoingBackground,
    this.wallpaper,
    this.showIncomingSurface = true,
    this.showOutgoingSurface = true,
    this.incomingSurfaceColor,
    this.outgoingSurfaceColor,
    this.incomingTextColor,
    this.outgoingTextColor,
  });

  final MessageBubbleBackgroundSpec incomingBackground;
  final MessageBubbleBackgroundSpec outgoingBackground;

  /// Painted behind the sample messages so a theme and its background are
  /// judged together, the way they are actually seen.
  final ChatWallpaper? wallpaper;

  final bool showIncomingSurface;
  final bool showOutgoingSurface;
  final Color? incomingSurfaceColor;
  final Color? outgoingSurfaceColor;
  final Color? incomingTextColor;
  final Color? outgoingTextColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final double rowGap = showIncomingSurface || showOutgoingSurface
        ? math
              .max(
                8.0,
                (showIncomingSurface
                        ? incomingBackground.visualOverflow.bottom
                        : 0.0) +
                    (showOutgoingSurface
                        ? outgoingBackground.visualOverflow.top
                        : 0.0) +
                    2,
              )
              .toDouble()
        : 8.0;
    return Container(
      key: const ValueKey('message-bubble-chat-preview'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: c.divider.withValues(alpha: 0.7)),
      ),
      // The wallpaper fills behind the sample messages rather than wrapping
      // them: it expands to its constraints, so the content has to be what
      // decides the height.
      child: Stack(
        children: [
          Positioned.fill(
            child: ChatWallpaperBackground(
              wallpaper: wallpaper,
              fallbackColor: c.chatBackground,
              brightness: Theme.of(context).brightness,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const PhotoAvatar(title: 'M', size: 34),
                    const SizedBox(width: 8),
                    Flexible(
                      child: _PreviewBubble(
                        key: const ValueKey('message-bubble-preview-incoming'),
                        background: incomingBackground,
                        outgoing: false,
                        showSurface: showIncomingSurface,
                        surfaceColor: incomingSurfaceColor,
                        textColor: incomingTextColor,
                        text:
                            'Repository bubble preview with a longer message.',
                      ),
                    ),
                  ],
                ),
                SizedBox(height: rowGap),
                Align(
                  alignment: Alignment.centerRight,
                  child: _PreviewBubble(
                    key: const ValueKey('message-bubble-preview-outgoing'),
                    background: outgoingBackground,
                    outgoing: true,
                    showSurface: showOutgoingSurface,
                    surfaceColor: outgoingSurfaceColor,
                    textColor: outgoingTextColor,
                    text: 'The center stretches with longer messages.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewBubble extends StatelessWidget {
  const _PreviewBubble({
    super.key,
    required this.background,
    required this.outgoing,
    required this.showSurface,
    this.surfaceColor,
    this.textColor,
    required this.text,
  });

  final MessageBubbleBackgroundSpec background;
  final bool outgoing;
  final bool showSurface;
  final Color? surfaceColor;
  final Color? textColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (!showSurface) {
      return Container(
        constraints: const BoxConstraints(maxWidth: 250),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        child: Text(
          text,
          style: TextStyle(color: c.textPrimary, fontSize: 15, height: 1.25),
        ),
      );
    }
    return StretchableMessageBubbleBackground(
      background: background,
      constraints: const BoxConstraints(maxWidth: 250),
      fallbackColor:
          surfaceColor ??
          (outgoing ? AppTheme.bubbleOutgoing : c.bubbleIncoming),
      fallbackBorderRadius: BorderRadius.circular(AppRadius.card),
      fallbackBorder: outgoing
          ? null
          : Border.all(color: c.divider, width: 0.5),
      fallbackPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      child: Text(
        text,
        style: TextStyle(
          color:
              background.foregroundColor ??
              textColor ??
              (outgoing ? AppTheme.bubbleOutgoingText : c.bubbleIncomingText),
          fontSize: 15,
          height: 1.25,
        ),
      ),
    );
  }
}
