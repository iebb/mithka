import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../components/photo_avatar.dart';
import '../theme/app_theme.dart';
import '../theme/message_bubble_background.dart';
import 'stretchable_message_bubble_background.dart';

class MessageBubbleChatPreview extends StatelessWidget {
  const MessageBubbleChatPreview({
    super.key,
    required this.incomingBackground,
    required this.outgoingBackground,
  });

  final MessageBubbleBackgroundSpec incomingBackground;
  final MessageBubbleBackgroundSpec outgoingBackground;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rowGap = math.max(
      8.0,
      incomingBackground.visualOverflow.bottom +
          outgoingBackground.visualOverflow.top +
          2,
    );
    return Container(
      key: const ValueKey('message-bubble-chat-preview'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.chatBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.divider.withValues(alpha: 0.7)),
      ),
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
                  text: 'Repository bubble preview with a longer message.',
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
              text: 'The center stretches with longer messages.',
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
    required this.text,
  });

  final MessageBubbleBackgroundSpec background;
  final bool outgoing;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return StretchableMessageBubbleBackground(
      background: background,
      constraints: const BoxConstraints(maxWidth: 250),
      fallbackColor: outgoing ? AppTheme.bubbleOutgoing : c.bubbleIncoming,
      fallbackBorderRadius: BorderRadius.circular(12),
      fallbackBorder: outgoing
          ? null
          : Border.all(color: c.divider, width: 0.5),
      fallbackPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      child: Text(
        text,
        style: TextStyle(
          color:
              background.foregroundColor ??
              (outgoing ? AppTheme.bubbleOutgoingText : c.bubbleIncomingText),
          fontSize: 15,
          height: 1.25,
        ),
      ),
    );
  }
}
