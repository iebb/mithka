import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:provider/provider.dart';

import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../l10n/app_localizations.dart';
import '../platform/adaptive_platform.dart';
import '../settings/translation_controller.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import '../theme/message_name_colors.dart';
import '../theme/telegram_cloud_theme.dart';
import '../theme/theme_controller.dart';
import 'chat_appearance_preview.dart';
import 'media_album_layout.dart';
import 'media_preview_geometry.dart';
import 'message_action_menu.dart';
import 'message_reply_count_badge.dart';
import 'mobile_message_text_selection.dart';
import 'telegram_rich_text.dart';

typedef MediaAlbumImageBuilder =
    Widget Function(
      BuildContext context,
      ChatMessage message,
      double width,
      double height,
    );

/// The production visual-media album row shared by chats and appearance
/// previews. Keeping the preview on this renderer ensures album geometry,
/// sender titles, name treatments, timestamps, and bubble colors stay honest.
class ImageMediaAlbumBubble extends StatelessWidget {
  const ImageMediaAlbumBubble({
    super.key,
    required this.messages,
    required this.peerTitle,
    required this.isGroup,
    this.peerPhoto,
    this.meName = AppStringKeys.chatMeLabel,
    this.mePhoto,
    this.hasCustomChatTheme = false,
    this.showCommentAttachment = false,
    this.channelHasLinkedDiscussion = false,
    this.selecting = false,
    this.selectedMessageIds = const <int>{},
    this.outgoingBubbleColor,
    this.outgoingBubbleTextColor,
    this.incomingBubbleColor,
    this.incomingBubbleTextColor,
    this.messageColors,
    this.translationDisplayStyle = TranslationDisplayStyle.quote,
    this.showOriginalTranslationMessageIds = const <int>{},
    this.onAvatarTap,
    this.onAvatarLongPress,
    this.onOpenImage,
    this.onPlayVideo,
    this.onEditCaption,
    this.onOpenComments,
    this.onLongPress,
    this.mobileTextSelectionAreaKey,
    this.onMobileTextSelectionChanged,
    this.onMobileTextSelectionDisposed,
    this.onToggleSelection,
    this.onBotCommandTap,
    this.onHashtagTap,
    this.onMentionTap,
    this.imageBuilder,
    this.targetMessageId,
    this.targetKey,
  }) : assert(messages.length >= 2);

  final List<ChatMessage> messages;
  final String peerTitle;
  final TdFileRef? peerPhoto;
  final bool isGroup;
  final String meName;
  final TdFileRef? mePhoto;
  final bool hasCustomChatTheme;
  final bool showCommentAttachment;
  final bool channelHasLinkedDiscussion;
  final bool selecting;
  final Set<int> selectedMessageIds;
  final Color? outgoingBubbleColor;
  final Color? outgoingBubbleTextColor;
  final Color? incomingBubbleColor;
  final Color? incomingBubbleTextColor;
  final TelegramMessageColors? messageColors;
  final TranslationDisplayStyle translationDisplayStyle;
  final Set<int> showOriginalTranslationMessageIds;
  final ValueChanged<ChatMessage>? onAvatarTap;
  final ValueChanged<ChatMessage>? onAvatarLongPress;
  final ValueChanged<ChatMessage>? onOpenImage;
  final ValueChanged<ChatMessage>? onPlayVideo;
  final ValueChanged<ChatMessage>? onEditCaption;
  final ValueChanged<ChatMessage>? onOpenComments;
  final void Function(
    ChatMessage message,
    Rect? bounds,
    MessageActionSource source,
  )?
  onLongPress;
  final GlobalKey<SelectionAreaState>? mobileTextSelectionAreaKey;
  final ValueChanged<SelectedContent?>? onMobileTextSelectionChanged;
  final VoidCallback? onMobileTextSelectionDisposed;
  final ValueChanged<ChatMessage>? onToggleSelection;
  final ValueChanged<String>? onBotCommandTap;
  final ValueChanged<String>? onHashtagTap;
  final void Function(int userId, String name)? onMentionTap;
  final MediaAlbumImageBuilder? imageBuilder;
  final int? targetMessageId;
  final GlobalKey? targetKey;

  ChatMessage get _first => messages.first;

  @override
  Widget build(BuildContext context) {
    final first = _first;
    final outgoing = first.isOutgoing;
    final avatarTitle = outgoing
        ? (first.senderIsChat ? (first.senderName ?? meName) : meName)
        : (isGroup && (first.senderName?.isNotEmpty ?? false))
        ? first.senderName!
        : peerTitle;
    final avatarPhoto = outgoing
        ? (first.senderIsChat ? first.senderPhoto : mePhoto)
        : (isGroup ? first.senderPhoto : peerPhoto);
    final captionMessage = messages
        .where((message) => message.text.trim().isNotEmpty)
        .firstOrNull;

    Widget avatar() => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onAvatarTap?.call(first),
      onLongPress: outgoing ? null : () => onAvatarLongPress?.call(first),
      child: PhotoAvatar(title: avatarTitle, photo: avatarPhoto, size: 38),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final chatWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final gallery = _gallery(
          context,
          outgoing: outgoing,
          captionMessage: captionMessage,
          // An album is chat media like any other: a wide transcript must not
          // stretch it past the box a single photo would get.
          maxWidth: math.max(
            1.0,
            math.min(chatWidth * 0.75, telegramDesktopMediaPreviewMaxSide),
          ),
        );
        final body = outgoing
            ? gallery
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isGroup && first.senderName != null)
                    _senderHeader(context),
                  gallery,
                ],
              );

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: outgoing
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: outgoing
                ? [
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: body,
                      ),
                    ),
                    const SizedBox(width: 8),
                    avatar(),
                  ]
                : [avatar(), const SizedBox(width: 8), Flexible(child: body)],
          ),
        );
      },
    );
  }

  Widget _senderHeader(BuildContext context) {
    final first = _first;
    final colors = context.colors;
    final theme = context.watch<ThemeController>();
    final showMemberTags = theme.showMemberTags;
    final showSenderRole = switch (first.senderRole) {
      null => false,
      MemberRole.member =>
        theme.showPlainMemberRoleTags ||
            (showMemberTags && (first.senderTitle?.trim().isNotEmpty ?? false)),
      _ => true,
    };
    final cloudTheme = theme.cloudThemeFor(Theme.of(context).brightness);
    final nameColor = messageNameColorForSender(
      theme: cloudTheme,
      accentColorId: first.senderAccentColorId,
      showNameColors: theme.chatNameColorAudience.shows(
        isPremium: first.senderIsPremium,
      ),
      nameColorsDisabledFallback:
          cloudTheme?.senderNameColor ?? colors.linkBlue,
    );
    final bubbleBackground = theme.effectiveMessageBubbleBackgroundSpecFor(
      outgoing: false,
    );
    final incomingColor =
        bubbleBackground.backgroundColor ??
        incomingBubbleColor ??
        cloudTheme?.incomingColor ??
        colors.bubbleIncoming;
    final incomingTextColor =
        bubbleBackground.foregroundColor ??
        incomingBubbleTextColor ??
        colors.bubbleIncomingText;
    final senderTitle = first.senderTitle?.trim();

    return Padding(
      key: ValueKey('messageSenderHeader-${first.id}'),
      padding: const EdgeInsets.only(left: 2, bottom: 4),
      child: Row(
        children: [
          Flexible(
            child: SenderIdentityPills(
              readabilityMode: theme.senderNameReadabilityMode,
              bubbleColor: incomingColor,
              textColor: incomingTextColor,
              name: first.senderName!,
              nameStyle: TextStyle(
                fontSize: 12,
                color: nameColor,
                fontWeight: FontWeight.w500,
              ),
              role: showSenderRole ? first.senderRole : null,
              roleTitle: showSenderRole && showMemberTags ? senderTitle : null,
              roleAfterName: isDesktopTargetPlatform(),
            ),
          ),
          if (theme.alwaysShowMessageTime) ...[
            const SizedBox(width: 5),
            SizedBox(
              width: 96,
              height: 14,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  DateText.messageDetailLabel(first.date),
                  key: const ValueKey('messageTappedTimestamp'),
                  maxLines: 1,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.2,
                    color: colors.textTertiary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _gallery(
    BuildContext context, {
    required bool outgoing,
    required ChatMessage? captionMessage,
    required double maxWidth,
  }) {
    final colors = context.colors;
    final theme = context.watch<ThemeController>();
    final bubbleBackground = theme.effectiveMessageBubbleBackgroundSpecFor(
      outgoing: outgoing,
    );
    final showsSurface = theme.shouldRenderMessageBubbleSurface(
      outgoing: outgoing,
      brightness: Theme.of(context).brightness,
      hasCustomChatTheme: hasCustomChatTheme,
    );
    final outgoingColor =
        bubbleBackground.backgroundColor ??
        outgoingBubbleColor ??
        AppTheme.bubbleOutgoing;
    final incomingColor =
        bubbleBackground.backgroundColor ??
        incomingBubbleColor ??
        colors.bubbleIncoming;
    final outgoingText = !showsSurface
        ? colors.textPrimary
        : bubbleBackground.foregroundColor ??
              outgoingBubbleTextColor ??
              readableForeground(outgoingColor);
    final incomingText = !showsSurface
        ? colors.textPrimary
        : bubbleBackground.foregroundColor ??
              incomingBubbleTextColor ??
              colors.bubbleIncomingText;
    final themedMessageColors = showsSurface && !bubbleBackground.isDecorative
        ? messageColors
        : null;
    final visible = messages.take(9).toList(growable: false);
    const padding = 4.0;
    final layout = _albumLayout(visible, math.max(1, maxWidth - padding * 2));
    final width = layout.width + padding * 2;
    final interactionOwner = selectMediaAlbumInteractionOwner(messages);
    final showComments =
        showCommentAttachment &&
        !interactionOwner.isContentRestricted &&
        (interactionOwner.hasCommentThread ||
            interactionOwner.commentCount > 0 ||
            (channelHasLinkedDiscussion && !interactionOwner.isService));
    final showCompactReplies =
        isGroup &&
        !showCommentAttachment &&
        !interactionOwner.isContentRestricted &&
        interactionOwner.commentCount > 0;
    final baseTextColor = outgoing ? outgoingText : incomingText;
    final baseLinkColor = outgoing
        ? themedMessageColors?.outgoingLink ?? outgoingText
        : themedMessageColors?.incomingLink ?? colors.linkBlue;
    final replacesOriginal =
        captionMessage != null &&
        translationDisplayStyle == TranslationDisplayStyle.translatedOnly &&
        !showOriginalTranslationMessageIds.contains(captionMessage.id) &&
        !captionMessage.isTranslating &&
        (captionMessage.translationText?.trim().isNotEmpty ?? false);
    final captionText = replacesOriginal
        ? captionMessage.translationText ?? ''
        : captionMessage?.text ?? '';
    final captionEntities = replacesOriginal
        ? captionMessage.translationEntities
        : captionMessage?.textEntities ?? const <MessageTextEntity>[];
    final displayedTextColor = replacesOriginal
        ? Color.lerp(baseTextColor, AppTheme.brand, outgoing ? 0.36 : 0.52)!
        : baseTextColor;
    final displayedLinkColor = replacesOriginal
        ? Color.lerp(baseLinkColor, AppTheme.brand, 0.30)!
        : baseLinkColor;
    final showsTranslationBlock =
        captionMessage != null &&
        (captionMessage.isTranslating ||
            ((captionMessage.translationText?.trim().isNotEmpty ?? false) &&
                translationDisplayStyle !=
                    TranslationDisplayStyle.translatedOnly));

    final card = Container(
      key: ValueKey('messageImageAlbumCard-${messages.first.id}'),
      constraints: BoxConstraints(maxWidth: width),
      decoration: showsSurface
          ? BoxDecoration(
              color: outgoing ? outgoingColor : incomingColor,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: outgoing || themedMessageColors != null
                  ? null
                  : Border.all(color: colors.divider, width: 0.5),
            )
          : null,
      clipBehavior: showsSurface ? Clip.antiAlias : Clip.none,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: layout.width,
                  height: layout.height,
                  child: Stack(
                    children: [
                      for (var i = 0; i < visible.length; i++)
                        Positioned.fromRect(
                          rect: layout.tiles[i],
                          child: _tile(
                            context,
                            visible[i],
                            width: layout.tiles[i].width,
                            height: layout.tiles[i].height,
                            extraCount: i == visible.length - 1
                                ? math.max(0, messages.length - visible.length)
                                : 0,
                          ),
                        ),
                    ],
                  ),
                ),
                if (captionMessage != null)
                  Builder(
                    builder: (captionContext) => GestureDetector(
                      key: ValueKey(
                        'messageImageAlbumCaption-${captionMessage.id}',
                      ),
                      behavior: HitTestBehavior.opaque,
                      onTap: outgoing
                          ? () => onEditCaption?.call(captionMessage)
                          : null,
                      onLongPress:
                          selecting || mobileTextSelectionAreaKey != null
                          ? null
                          : () {
                              final box =
                                  captionContext.findRenderObject()
                                      as RenderBox?;
                              final bounds = box != null && box.hasSize
                                  ? box.localToGlobal(Offset.zero) & box.size
                                  : null;
                              onLongPress?.call(
                                captionMessage,
                                bounds,
                                MessageActionSource.normal,
                              );
                            },
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(6, 7, 6, 3),
                        child: Builder(
                          builder: (context) {
                            final selectionContent = Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _captionText(
                                  captionText,
                                  captionEntities,
                                  displayedTextColor,
                                  displayedLinkColor,
                                  replacesOriginal: replacesOriginal,
                                ),
                                if (showsTranslationBlock) ...[
                                  const SizedBox(height: 7),
                                  _translationBlock(
                                    context,
                                    captionMessage,
                                    outgoing: outgoing,
                                    baseTextColor: baseTextColor,
                                    linkColor: baseLinkColor,
                                  ),
                                ],
                              ],
                            );
                            final selectionKey = mobileTextSelectionAreaKey;
                            if (selectionKey == null) return selectionContent;
                            return MobileMessageTextSelectionArea(
                              selectionAreaKey: selectionKey,
                              onSelectionChanged: onMobileTextSelectionChanged,
                              onDisposed:
                                  onMobileTextSelectionDisposed ?? () {},
                              child: selectionContent,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (showComments)
            _commentsAttachment(
              context,
              interactionOwner,
              outgoing: outgoing,
              width: width,
              outgoingTextColor: outgoingText,
            ),
        ],
      ),
    );
    if (!showCompactReplies) return card;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(padding: const EdgeInsets.only(bottom: 19), child: card),
        Positioned(
          right: 2,
          bottom: 0,
          child: MessageReplyCountBadge(
            key: ValueKey('messageCompactReplies-${interactionOwner.id}'),
            count: interactionOwner.commentCount,
            foreground: outgoing
                ? outgoingText.withValues(alpha: 0.78)
                : colors.textSecondary,
            background: outgoing
                ? outgoingColor.withValues(alpha: 0.82)
                : colors.card.withValues(alpha: 0.82),
            onTap: onOpenComments == null
                ? null
                : () => onOpenComments?.call(interactionOwner),
          ),
        ),
      ],
    );
  }

  Widget _captionText(
    String text,
    List<MessageTextEntity> entities,
    Color textColor,
    Color linkColor, {
    required bool replacesOriginal,
  }) => TelegramRichText(
    key: replacesOriginal ? const ValueKey('messageTranslatedOnlyText') : null,
    text: text,
    entities: entities,
    style: TextStyle(fontSize: 15, height: 1.25, color: textColor),
    linkColor: linkColor,
    onBotCommandTap: onBotCommandTap,
    onHashtagTap: onHashtagTap,
    onMentionTap: onMentionTap,
  );

  Widget _translationBlock(
    BuildContext context,
    ChatMessage source, {
    required bool outgoing,
    required Color baseTextColor,
    required Color linkColor,
  }) {
    final colors = context.colors;
    final secondary = outgoing
        ? baseTextColor.withValues(alpha: 0.70)
        : colors.textSecondary;
    if (source.isTranslating) {
      return SelectionContainer.disabled(
        child: Container(
          key: const ValueKey('messageTranslationBlock'),
          width: double.infinity,
          decoration: BoxDecoration(
            color: outgoing
                ? baseTextColor.withValues(alpha: 0.10)
                : colors.searchFill.withValues(alpha: 0.80),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border(left: BorderSide(color: secondary, width: 2.5)),
          ),
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(secondary),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                AppStringKeys.messageBubbleTranslating.l10n(context),
                style: TextStyle(fontSize: 13, color: secondary),
              ),
            ],
          ),
        ),
      );
    }

    final translatedText = TelegramRichText(
      text: source.translationText ?? '',
      entities: source.translationEntities,
      style: TextStyle(fontSize: 15, height: 1.25, color: baseTextColor),
      linkColor: linkColor,
      onBotCommandTap: onBotCommandTap,
      onHashtagTap: onHashtagTap,
      onMentionTap: onMentionTap,
    );
    if (translationDisplayStyle == TranslationDisplayStyle.both) {
      final divider = outgoing
          ? baseTextColor.withValues(alpha: 0.22)
          : colors.divider;
      return Container(
        key: const ValueKey('messageTranslationBlock'),
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: divider, width: 0.5)),
        ),
        padding: const EdgeInsets.only(top: 7),
        child: translatedText,
      );
    }
    return Container(
      key: const ValueKey('messageTranslationBlock'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: outgoing
            ? baseTextColor.withValues(alpha: 0.10)
            : colors.searchFill.withValues(alpha: 0.80),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border(left: BorderSide(color: secondary, width: 2.5)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectionContainer.disabled(
            child: Text(
              AppStringKeys.messageActionTranslate.l10n(context),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: secondary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          translatedText,
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    ChatMessage message, {
    required double width,
    required double height,
    required int extraCount,
  }) {
    // A GlobalKey minted here would change identity every build, so Flutter
    // could not match the old element: the whole tile — TDImage state and its
    // in-flight file lookup included — was deactivated and re-inflated on every
    // album rebuild. The key only ever resolved a RenderBox, which the tile's
    // own context gives for free.
    return Builder(
      builder: (tileContext) {
        void showActions({Offset? pointerPosition}) {
          final box = tileContext.findRenderObject() as RenderBox?;
          final bounds = pointerPosition != null
              ? Rect.fromLTWH(pointerPosition.dx, pointerPosition.dy, 0, 0)
              : box != null && box.hasSize
              ? box.localToGlobal(Offset.zero) & box.size
              : null;
          onLongPress?.call(
            message,
            bounds,
            message.video != null
                ? MessageActionSource.video
                : MessageActionSource.normal,
          );
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (selecting) {
              onToggleSelection?.call(message);
            } else if (message.video != null) {
              onPlayVideo?.call(message);
            } else {
              onOpenImage?.call(message);
            }
          },
          onLongPress: selecting ? null : showActions,
          onSecondaryTapUp: selecting
              ? null
              : (details) =>
                    showActions(pointerPosition: details.globalPosition),
          child: SizedBox(
            key: message.id == targetMessageId && targetKey != null
                ? targetKey
                : ValueKey('messageImageAlbumTile-${message.id}'),
            width: width,
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                imageBuilder?.call(context, message, width, height) ??
                    TDImage(
                      photo: message.image,
                      cornerRadius: 5,
                      cacheWidth: _cachePx(context, width),
                      cacheHeight: _cachePx(context, height),
                      showProgress: true,
                    ),
                if (message.video != null)
                  Center(
                    child: Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                      ),
                      child: const AppIcon(
                        HeroAppIcons.play,
                        color: Colors.white,
                        size: 21,
                      ),
                    ),
                  ),
                if (extraCount > 0)
                  Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      '+$extraCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (selecting)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: IgnorePointer(
                      child: _selectionIndicator(context, message),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _selectionIndicator(BuildContext context, ChatMessage message) {
    final selected = selectedMessageIds.contains(message.id);
    return Container(
      key: ValueKey('media-selection-${message.id}'),
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? AppTheme.brand : Colors.black.withValues(alpha: 0.28),
        border: Border.all(
          color: selected ? AppTheme.brand : Colors.white,
          width: selected ? 0 : 1.4,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 4),
        ],
      ),
      child: selected
          ? const AppIcon(HeroAppIcons.check, size: 17, color: Colors.white)
          : null,
    );
  }

  Widget _commentsAttachment(
    BuildContext context,
    ChatMessage message, {
    required bool outgoing,
    required double width,
    required Color outgoingTextColor,
  }) {
    final colors = context.colors;
    final count = message.commentCount;
    final label = count == 0
        ? AppStrings.t(AppStringKeys.messageLeaveAComment)
        : AppStrings.plural(AppStringKeys.momentsCommentCount, count);
    final foreground = outgoing ? outgoingTextColor : colors.textPrimary;
    final accent = outgoing
        ? outgoingTextColor.withValues(alpha: 0.72)
        : colors.linkBlue;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onOpenComments?.call(message),
      child: Container(
        key: ValueKey('messageCommentsAttachment-${message.id}'),
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: outgoing
                  ? outgoingTextColor.withValues(alpha: 0.16)
                  : colors.divider.withValues(alpha: 0.7),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            AppIcon(HeroAppIcons.comments, size: 18, color: accent),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: foreground,
                ),
              ),
            ),
            AppIcon(HeroAppIcons.chevronRight, size: 17, color: accent),
          ],
        ),
      ),
    );
  }

  int _cachePx(BuildContext context, double logical) =>
      (logical * MediaQuery.devicePixelRatioOf(context)).ceil();
}

/// Album geometry is a search over every row plan, each allocating a list and a
/// Rect per tile. The inputs only move when TDLib replaces a message, so memoize
/// it rather than re-running the search on every transcript rebuild.
final Map<String, MediaAlbumLayout> _albumLayouts = {};
const _maxMemoizedAlbumLayouts = 32;

MediaAlbumLayout _albumLayout(List<ChatMessage> visible, double maxWidth) {
  final signature = StringBuffer()..write(maxWidth.toStringAsFixed(2));
  for (final message in visible) {
    signature
      ..write('|')
      ..write(message.id)
      ..write(':')
      ..write(message.imageWidth)
      ..write('x')
      ..write(message.imageHeight);
  }
  final key = signature.toString();
  final cached = _albumLayouts[key];
  if (cached != null) return cached;
  final layout = buildTelegramMediaAlbumLayout(
    items: [
      for (final message in visible)
        MediaAlbumItem(width: message.imageWidth, height: message.imageHeight),
    ],
    maxWidth: maxWidth,
    gap: 4,
    maxSingleHeight: 300,
    minRowHeight: 82,
    maxRowHeight: 230,
    maxHeight: telegramChatMediaPreviewMaxHeight,
  );
  if (_albumLayouts.length >= _maxMemoizedAlbumLayouts) {
    _albumLayouts.remove(_albumLayouts.keys.first);
  }
  _albumLayouts[key] = layout;
  return layout;
}

ChatMessage selectMediaAlbumInteractionOwner(List<ChatMessage> group) {
  for (final message in group) {
    if (message.hasCommentThread || message.hasActualReplies) return message;
  }
  for (final message in group) {
    if (message.reactions.isNotEmpty) return message;
  }
  return group.first;
}
