import 'package:flutter/widgets.dart';

import '../chat/message_bubble.dart';
import '../chats/chat_row_view.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/content_size.dart';

/// Entirely fictional, local samples: never reads an account or loads a photo.
///
/// Both pages draw with the real conversation and chat-list metrics, so the
/// preview reflows exactly like the screens it stands for.
class ContentSizePreview extends StatelessWidget {
  const ContentSizePreview({
    super.key,
    required this.appScale,
    required this.chatList,
    required this.now,
  });
  final double appScale;
  final bool chatList;

  /// Sample chats are dated relative to this moment so their rows show the
  /// clock times of a real recent list rather than full dates.
  final DateTime now;

  static const _sampleAges = [
    Duration(minutes: 20),
    Duration(hours: 2),
    Duration(days: 1),
  ];
  static const _sampleNames = [
    AppStringKeys.contentSizePreviewName1,
    AppStringKeys.contentSizePreviewName2,
    AppStringKeys.contentSizePreviewName3,
  ];
  static const _sampleLines = [
    AppStringKeys.contentSizePreviewLine1,
    AppStringKeys.contentSizePreviewLine2,
    AppStringKeys.contentSizePreviewLine3,
  ];

  @override
  Widget build(BuildContext context) => ContentSizeScope(
    appScale: appScale,
    child: chatList ? _chatList(context) : _conversation(context),
  );

  Widget _chatList(BuildContext context) => Column(
    key: const ValueKey('font-size-chat-list-preview'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var index = 0; index < _sampleAges.length; index++)
        ChatRowView(
          // No photo: the row paints the real colored monogram for its title.
          chat: ChatSummary(
            id: -900000 - index,
            title: AppStrings.t(_sampleNames[index]),
            lastMessage: AppStrings.t(_sampleLines[index]),
            lastMessageId: 0,
            date:
                now.subtract(_sampleAges[index]).millisecondsSinceEpoch ~/ 1000,
            unreadCount: 0,
            order: 0,
            isMuted: false,
          ),
        ),
    ],
  );

  Widget _conversation(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = messageBubbleMaxWidth(constraints.maxWidth);
        return Column(
          key: const ValueKey('font-size-chat-preview'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _bubble(
              context,
              AppStrings.t(AppStringKeys.contentSizePreviewIncoming),
              outgoing: false,
              maxWidth: maxWidth,
            ),
            const SizedBox(height: 8),
            _bubble(
              context,
              AppStrings.t(AppStringKeys.contentSizePreviewOutgoing),
              outgoing: true,
              maxWidth: maxWidth,
            ),
          ],
        );
      },
    ),
  );

  Widget _bubble(
    BuildContext context,
    String text, {
    required bool outgoing,
    required double maxWidth,
  }) {
    final colors = context.colors;
    return Align(
      alignment: outgoing
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: Container(
        key: ValueKey(
          outgoing ? 'content-size-bubble-outgoing' : 'content-size-bubble-in',
        ),
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: messageTextBubblePadding,
        decoration: BoxDecoration(
          color: outgoing ? AppTheme.bubbleOutgoing : colors.bubbleIncoming,
          borderRadius: BorderRadius.circular(messageTextBubbleRadius),
          border: outgoing
              ? null
              : Border.all(color: colors.divider, width: 0.5),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: AppTextSize.messageBody(),
            color: outgoing
                ? AppTheme.bubbleOutgoingText
                : colors.bubbleIncomingText,
          ),
        ),
      ),
    );
  }
}
