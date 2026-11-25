part of 'moments_view.dart';

class ChannelPostRow extends StatelessWidget {
  const ChannelPostRow({
    super.key,
    required this.post,
    required this.meName,
    this.mePhoto,
    this.onOpenPost,
    this.onComment,
    this.showInlineReply = true,
    this.showInlineComments = true,
  });

  final ChannelPost post;
  final String meName;
  final TdFileRef? mePhoto;
  final ValueChanged<ChannelPost>? onOpenPost;
  final void Function(ChannelPost post, BuildContext anchorContext)? onComment;
  final bool showInlineReply;
  final bool showInlineComments;

  ChatSummary get channel => post.channel;
  ChatMessage get message => post.message;
  List<ChatMessage> get messages => post.messages;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = _displayText;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onOpenPost == null ? null : () => onOpenPost!(post),
      child: Container(
        color: c.background,
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PhotoAvatar(
                  title: channel.title,
                  photo: channel.photo,
                  size: 48,
                  square: true,
                  allowAnimation: false,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              channel.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: c.linkBlue,
                              ),
                            ),
                          ),
                          _ChannelPostOverflowButton(post: post),
                        ],
                      ),
                      Row(
                        children: [
                          if (_hasSignedAuthor) ...[
                            PhotoAvatar(
                              title: post.authorName!,
                              photo: post.authorPhoto,
                              size: 16,
                              allowAnimation: false,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                post.authorName!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: c.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            DateText.listLabel(message.date),
                            style: TextStyle(
                              fontSize: 12,
                              color: c.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (message.hasForwardAttribution) ...[
              const SizedBox(height: 10),
              Text(
                key: const ValueKey('momentsForwardAttribution'),
                AppStrings.t(AppStringKeys.messageBubbleForwardedFrom, {
                  'value1': message.forwardDisplayName,
                }),
                style: TextStyle(fontSize: 13, color: c.linkBlue),
              ),
            ],
            if (text.isNotEmpty) ...[
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  // Trim the raw selected caption and its entities together.
                  // Passing `_displayText` would discard its original offsets.
                  final display = trimTextForDisplay(
                    _displayTextMessage?.text ?? '',
                    _displayTextMessage?.textEntities ?? const [],
                  );
                  return TelegramRichText(
                    text: display.text,
                    entities: display.entities,
                    quoteBackgroundColor: _momentQuoteFill(c),
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.35,
                      color: c.textPrimary,
                    ),
                    onMentionTap: (userId, name) {
                      unawaited(
                        openAdaptiveUserProfile(
                          context,
                          userId: userId,
                          name: name,
                        ),
                      );
                    },
                  );
                },
              ),
            ],
            if (_hasReplyQuote) ...[
              SizedBox(height: text.isNotEmpty ? 8 : 12),
              _PostReplyQuote(message: message),
            ],
            if (_imageMessages.isNotEmpty) ...[
              const SizedBox(height: 10),
              _PostImageGroup(
                messages: _imageMessages,
                sourceChatId: channel.id,
                accountSlot: post.accountSlot,
              ),
            ],
            for (final item in messages)
              if (!item.isContentRestricted && item.music != null) ...[
                const SizedBox(height: 10),
                _PostMusicCard(message: item, post: post),
              ] else if (!item.isContentRestricted &&
                  _hasStickerMedia(item)) ...[
                const SizedBox(height: 10),
                _PostSticker(
                  key: ValueKey('moments-sticker-${item.id}'),
                  message: item,
                  accountSlot: post.accountSlot,
                ),
              ],
            const SizedBox(height: 12),
            _PostActions(
              post: post,
              canComment: _canReply && onComment != null,
              onComment: (post) => onComment?.call(post, context),
            ),
            if (showInlineComments && _hasInlineComments) ...[
              const SizedBox(height: 8),
              _InlineComments(post: post),
            ],
            if (showInlineReply && _canReply && onComment != null) ...[
              const SizedBox(height: 10),
              _InlineQuickReply(
                meName: meName,
                mePhoto: mePhoto,
                onTap: (context) => onComment?.call(post, context),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String get _displayText {
    return _displayTextMessage?.text.trim() ?? '';
  }

  ChatMessage? get _displayTextMessage {
    for (final message in messages) {
      if (_hasStickerMedia(message)) continue;
      final text = message.text.trim();
      if (text.isNotEmpty && !(text.startsWith('[') && text.endsWith(']'))) {
        return message;
      }
    }
    return null;
  }

  // Album eligibility excludes animations/video notes and requires a photo
  // thumbnail. A standalone playable post does not have those restrictions.
  List<ChatMessage> get _imageMessages => messages
      .where(
        (message) =>
            message.isAlbumVisualMedia ||
            (message.video != null &&
                const {
                  'messageVideo',
                  'messageAnimation',
                  'messageVideoNote',
                }.contains(message.contentType)),
      )
      .toList();

  bool get _hasInlineComments =>
      message.commentCount > 0 || (post.comments?.isNotEmpty ?? false);

  bool get _canReply => post.threadTarget != null || message.hasCommentThread;

  bool get _hasSignedAuthor =>
      !_isChannelSelfPost(post) && post.authorName?.trim().isNotEmpty == true;

  bool get _hasReplyQuote => message.replyToMessageId != null;
}

bool _hasStickerMedia(ChatMessage message) =>
    !message.isContentRestricted &&
    (message.contentType == 'messageSticker' ||
        message.contentType == 'messageAnimatedEmoji') &&
    (message.image != null ||
        message.animatedSticker != null ||
        message.videoSticker != null);

class _PostMusicCard extends StatelessWidget {
  const _PostMusicCard({required this.message, required this.post});

  final ChatMessage message;
  final ChannelPost post;

  @override
  Widget build(BuildContext context) {
    final music = message.music!;
    final player = MusicPlayerController.shared;
    final colors = context.colors;
    final duration = math.max(0, music.duration);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.divider, width: 0.5),
        ),
        child: Row(
          children: [
            AnimatedBuilder(
              animation: player,
              builder: (context, _) {
                final sameAccount =
                    post.accountSlot == TdClient.shared.activeSlot;
                final active = sameAccount && player.isActive(music.file);
                final playing = active && player.isPlaying;
                final loading = active && player.isLoading;
                final canPlay = sameAccount && music.file != null;
                return Semantics(
                  button: true,
                  enabled: canPlay,
                  label:
                      (playing
                              ? AppStringKeys.musicPlayerPause
                              : AppStringKeys.musicPlayerPlay)
                          .l10n(context),
                  child: GestureDetector(
                    key: ValueKey('moments-music-play-${message.id}'),
                    behavior: HitTestBehavior.opaque,
                    onTap: !canPlay
                        ? null
                        : () => unawaited(
                            player.playChat(
                              ChatMessage(
                                id: message.id,
                                isOutgoing: message.isOutgoing,
                                text: '',
                                date: message.date,
                                chatId: post.channel.id,
                                senderName: post.channel.title,
                                music: music,
                              ),
                              post.channel.id,
                              title: post.channel.title,
                            ),
                          ),
                    child: SizedBox.square(
                      dimension: 52,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (music.cover != null)
                            TDImage(
                              photo: music.cover,
                              accountSlot: post.accountSlot,
                            ),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: music.cover == null
                                  ? AppTheme.brand
                                  : Colors.black.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(
                                AppRadius.control,
                              ),
                            ),
                            child: Center(
                              child: loading
                                  ? const SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : AppIcon(
                                      playing
                                          ? HeroAppIcons.pause
                                          : HeroAppIcons.play,
                                      size: 24,
                                      color: Colors.white,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    music.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  if ((music.performer ?? '').trim().isNotEmpty)
                    Text(
                      music.performer!.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textSecondary,
                      ),
                    ),
                  Text(
                    '${duration ~/ 60}:${(duration % 60).toString().padLeft(2, '0')}',
                    style: TextStyle(fontSize: 12, color: colors.textTertiary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostSticker extends StatefulWidget {
  const _PostSticker({
    super.key,
    required this.message,
    required this.accountSlot,
  });

  final ChatMessage message;
  final int accountSlot;

  @override
  State<_PostSticker> createState() => _PostStickerState();
}

class _PostStickerState extends State<_PostSticker> {
  bool _ready = false;

  @override
  void didUpdateWidget(_PostSticker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountSlot != widget.accountSlot ||
        oldWidget.message.animatedSticker?.id !=
            widget.message.animatedSticker?.id) {
      _ready = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final width = math.max(1, message.imageWidth ?? 180).toDouble();
    final height = math.max(1, message.imageHeight ?? 180).toDouble();
    final scale = 180 / math.max(width, height);
    final activeAccount = widget.accountSlot == TdClient.shared.activeSlot;
    return SizedBox(
      width: width * scale,
      height: height * scale,
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (message.image != null &&
                !_ready &&
                (!activeAccount || message.videoSticker == null))
              TDImage(
                photo: message.image,
                accountSlot: widget.accountSlot,
                fit: BoxFit.contain,
                cornerRadius: 0,
              ),
            if (activeAccount && message.animatedSticker != null)
              AnimatedStickerView(
                file: message.animatedSticker!,
                onReady: () {
                  if (mounted) setState(() => _ready = true);
                },
              )
            else if (activeAccount && message.videoSticker != null)
              VideoStickerView(
                file: message.videoSticker!,
                fallback: message.image,
              ),
          ],
        ),
      ),
    );
  }
}

class _PostReplyQuote extends StatelessWidget {
  const _PostReplyQuote({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sender = message.replyToSender?.trim();
    final preview = message.replyPreviewText?.trim() ?? '';
    final image = message.replyToImage;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final hasText =
        (sender?.isNotEmpty ?? false) || preview.isNotEmpty || image == null;
    return Container(
      key: const ValueKey('momentsReplyQuote'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
      decoration: BoxDecoration(
        color: _momentQuoteFill(c),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (image != null) ...[
            SizedBox(
              key: const ValueKey('momentsReplyMediaPreview'),
              width: 52,
              height: 52,
              child: TDImage(
                photo: image,
                cornerRadius: 6,
                cacheWidth: (52 * pixelRatio).round(),
                cacheHeight: (52 * pixelRatio).round(),
              ),
            ),
            if (hasText) const SizedBox(width: 10),
          ],
          if (hasText)
            Expanded(
              child: RichText(
                textScaler: MediaQuery.textScalerOf(context),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.35,
                    color: c.textPrimary,
                  ),
                  children: [
                    if (sender != null && sender.isNotEmpty)
                      TextSpan(
                        text: '$sender: ',
                        style: TextStyle(
                          color: c.linkBlue,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    TextSpan(
                      text: preview.isEmpty && image == null
                          ? AppStringKeys.chatInputBarReply.l10n(context)
                          : preview.replaceAll('\n', ' '),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InlineQuickReply extends StatelessWidget {
  const _InlineQuickReply({
    required this.meName,
    this.mePhoto,
    required this.onTap,
  });

  final String meName;
  final TdFileRef? mePhoto;
  final ValueChanged<BuildContext> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(context),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _momentQuoteFill(c),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          children: [
            PhotoAvatar(
              title: meName,
              photo: mePhoto,
              size: 26,
              allowAnimation: false,
            ),
            const SizedBox(width: 9),
            Text(
              AppStringKeys.momentsCommentPlaceholder.l10n(context),
              style: TextStyle(fontSize: 14, color: c.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineComments extends StatelessWidget {
  const _InlineComments({required this.post});

  final ChannelPost post;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final comments = post.comments ?? const <ChannelPostComment>[];
    if (comments.isEmpty) {
      return Text(
        AppStrings.plural(
          AppStringKeys.momentsCommentCount,
          post.message.commentCount,
        ),
        style: TextStyle(fontSize: 13, color: c.linkBlue),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final comment in comments)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => pushAppChatRoute(
              context,
              AppChatPageRoute<void>(
                builder: (_) => ChatView(
                  chatId: comment.chatId,
                  title: post.channel.title,
                  initialMessageId: comment.messageId,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Wrap(
                children: [
                  Text(
                    '${comment.senderName}: ',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.25,
                      color: c.linkBlue,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  TelegramRichText(
                    text: comment.text,
                    entities: comment.entities,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    quoteBackgroundColor: _momentQuoteFill(c),
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.25,
                      color: c.textPrimary,
                    ),
                    onMentionTap: (userId, name) {
                      unawaited(
                        openAdaptiveUserProfile(
                          context,
                          userId: userId,
                          name: name,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        if (post.message.commentCount > comments.length)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              AppStringKeys.momentsMore.l10n(context),
              style: TextStyle(fontSize: 13, color: c.linkBlue),
            ),
          ),
      ],
    );
  }
}

class _PostImageGroup extends StatelessWidget {
  const _PostImageGroup({
    required this.messages,
    required this.sourceChatId,
    required this.accountSlot,
  });

  final List<ChatMessage> messages;
  final int sourceChatId;
  final int accountSlot;

  @override
  Widget build(BuildContext context) {
    // sizeOf, not of: depending on the whole MediaQueryData rebuilt every
    // album in the viewport on each frame of the keyboard animation.
    final width = MediaQuery.sizeOf(context).width - 28;
    final visible = messages.take(9).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    final layout = buildTelegramMediaAlbumLayout(
      items: [
        for (final message in visible)
          MediaAlbumItem(
            width: message.imageWidth,
            height: message.imageHeight,
          ),
      ],
      maxWidth: width,
      minSingleHeight: 140,
      maxSingleHeight: 420,
      minRowHeight: 92,
      maxRowHeight: 280,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        width: layout.width,
        height: layout.height,
        child: Stack(
          children: [
            for (var i = 0; i < visible.length; i++)
              Positioned.fromRect(
                rect: layout.tiles[i],
                child: _tappableTile(
                  context: context,
                  index: i,
                  child: _PostImageTile(
                    message: visible[i],
                    width: layout.tiles[i].width,
                    height: layout.tiles[i].height,
                    accountSlot: accountSlot,
                    extraCount: i == visible.length - 1
                        ? math.max(0, messages.length - visible.length)
                        : 0,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tappableTile({
    required BuildContext context,
    required int index,
    required Widget child,
  }) {
    return GestureDetector(
      key: ValueKey('moments-media-${messages[index].id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _openMedia(context, messages[index]),
      child: MessageMediaSpoiler(
        message: messages[index],
        accountSlot: accountSlot,
        child: child,
      ),
    );
  }

  void _openMedia(BuildContext context, ChatMessage message) {
    final video = message.video;
    if (video != null) {
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => VideoOnDemandPlayerView(queue: _videoQueue(message)),
        ),
      );
      return;
    }
    _openImage(context, message);
  }

  VideoPlaybackQueue _videoQueue(ChatMessage current) {
    final videos = messages
        .where(
          (message) =>
              message.video != null &&
              canPreviewMediaAlongside(message, current),
        )
        .toList();
    if (!videos.any((message) => message.id == current.id)) videos.add(current);
    final index = videos.indexWhere((message) => message.id == current.id);
    return VideoPlaybackQueue(
      items: [
        for (final message in videos)
          VideoPlaybackItem(
            video: message.video!,
            accountSlot: accountSlot,
            thumb: message.image,
            width: message.imageWidth,
            height: message.imageHeight,
            durationSeconds: message.videoDuration,
            sourceChatId: sourceChatId,
            messageId: message.id,
            title: message.text.trim().replaceAll('\n', ' '),
          ),
      ],
      index: index < 0 ? 0 : index,
    );
  }

  void _openImage(BuildContext context, ChatMessage startMessage) {
    final photoMessages = messages
        .where(
          (message) =>
              message.isPhoto &&
              message.image != null &&
              canPreviewMediaAlongside(message, startMessage),
        )
        .toList();
    final refs = photoMessages.map((message) => message.image!).toList();
    if (refs.isEmpty) return;
    final startIndex = photoMessages.indexWhere(
      (message) => message.id == startMessage.id,
    );
    unawaited(
      openImagePreview(
        context,
        items: refs,
        startIndex: (startIndex < 0 ? 0 : startIndex).clamp(0, refs.length - 1),
      ),
    );
  }
}

class _PostImageTile extends StatelessWidget {
  const _PostImageTile({
    required this.message,
    required this.width,
    required this.height,
    required this.accountSlot,
    this.extraCount = 0,
  });

  final ChatMessage message;
  final double width;
  final double height;
  final int accountSlot;
  final int extraCount;

  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            TDImage(
              photo: message.image,
              cornerRadius: 3,
              cacheWidth: (width * pixelRatio).round(),
              cacheHeight: (height * pixelRatio).round(),
              showProgress: true,
              accountSlot: accountSlot,
            ),
            if (message.video != null)
              Center(
                child: Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: const AppIcon(
                    HeroAppIcons.play,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            if (extraCount > 0)
              Container(
                color: Colors.black.withValues(alpha: 0.42),
                alignment: Alignment.center,
                child: Text(
                  '+$extraCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PostActions extends StatelessWidget {
  const _PostActions({
    required this.post,
    required this.canComment,
    required this.onComment,
  });

  final ChannelPost post;
  final bool canComment;
  final ValueChanged<ChannelPost> onComment;

  ChatSummary get channel => post.channel;
  ChatMessage get message => post.message;

  static const double _actionSize = 32;
  static const double _actionGap = 8;
  static const double _iconSize = 22;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reactionCount = _reactionCount;
    final likeText = _likeText(reactionCount);
    return Row(
      children: [
        Text(likeText, style: TextStyle(fontSize: 13, color: c.linkBlue)),
        const Spacer(),
        _MomentsReactionControl(
          accountSlot: post.accountSlot,
          chatId: channel.id,
          messageId: message.id,
          keyNamespace: 'moments-reaction',
          contentBuilder: (context, icon) => SizedBox.square(
            dimension: _actionSize,
            child: Center(
              child: AppIcon(
                icon,
                size: _iconSize,
                color: context.colors.textPrimary,
              ),
            ),
          ),
        ),
        if (canComment) ...[
          const SizedBox(width: _actionGap),
          _actionButton(
            context,
            HeroAppIcons.comment,
            onTap: () => onComment(post),
          ),
        ],
        const SizedBox(width: _actionGap),
        _actionButton(
          context,
          HeroAppIcons.forward,
          onTap: () => _forward(context),
        ),
      ],
    );
  }

  Widget _actionButton(
    BuildContext context,
    AppIconData icon, {
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox.square(
        dimension: _actionSize,
        child: Center(
          child: AppIcon(
            icon,
            size: _iconSize,
            color: context.colors.textPrimary,
          ),
        ),
      ),
    );
  }

  int get _reactionCount =>
      message.reactions.fold<int>(0, (sum, reaction) => sum + reaction.count);

  String _likeText(int reactionCount) {
    if (reactionCount <= 0) return '';
    final names = post.likeNames;
    if (names == null || names.isEmpty) {
      return AppStrings.t(AppStringKeys.momentsLikedByCount, {
        'value1': reactionCount,
      });
    }
    final shownNames = names.take(3).toList();
    final shown = shownNames.join(AppStrings.t(AppStringKeys.listSeparator));
    if (reactionCount > names.length || names.length > 3) {
      return AppStrings.t(AppStringKeys.momentsLikedByListWithOthers, {
        'value1': shown,
        // Every locale's template reads "and N others" — the remainder
        // beyond the listed names, not the total like count.
        'value2': math.max(1, reactionCount - shownNames.length),
      });
    }
    return AppStrings.t(AppStringKeys.momentsUserLiked, {'value1': shown});
  }

  Future<void> _forward(BuildContext context) async {
    final result = await Navigator.of(context).push<ChatPickerResult>(
      MaterialPageRoute(
        builder: (_) => ChatPickerView(
          title: AppStringKeys.chatForwardToTitle,
          showForwardOptions: true,
          accountSlot: post.accountSlot,
        ),
      ),
    );
    if (result == null || !context.mounted) return;
    final target = result.chat;
    ChatDeepLinkController.shared.openChat(
      chatId: target.id,
      title: target.title,
      accountSlot: post.accountSlot,
      forwardHandoff: ForwardMessagesHandoff(
        fromChatId: channel.id,
        messages: post.messages,
        accountSlot: post.accountSlot,
        clientId: TdClient.shared.clientId(post.accountSlot) ?? 0,
        hasCaption: forwardSelectionHasCaption(post.messages),
        markdownOffer: const ForwardMarkdownOffer.none(),
      ),
    );
  }
}

class _MomentsReactionControl extends StatefulWidget {
  const _MomentsReactionControl({
    required this.accountSlot,
    required this.chatId,
    required this.messageId,
    required this.keyNamespace,
    required this.contentBuilder,
    this.hiddenBuilder,
    this.onReactionSent,
  });

  final int accountSlot;
  final int chatId;
  final int messageId;
  final String keyNamespace;
  final Widget Function(BuildContext context, AppIconData icon) contentBuilder;
  final WidgetBuilder? hiddenBuilder;
  final VoidCallback? onReactionSent;

  @override
  State<_MomentsReactionControl> createState() =>
      _MomentsReactionControlState();
}

class _MomentsReactionControlState extends State<_MomentsReactionControl> {
  static const _thumbsUp = QuickReactionChoice.emoji('👍');

  MessageReactionAvailability? _availability;
  List<QuickReactionChoice> _arbitraryCustomChoices = const [];
  int _availabilityGeneration = 0;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadAvailability();
  }

  @override
  void didUpdateWidget(_MomentsReactionControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_matchesTarget(
      oldWidget.accountSlot,
      oldWidget.chatId,
      oldWidget.messageId,
    )) {
      _availability = null;
      _arbitraryCustomChoices = const [];
      _sending = false;
      _loadAvailability();
    }
  }

  bool _matchesTarget(int accountSlot, int chatId, int messageId) =>
      widget.accountSlot == accountSlot &&
      widget.chatId == chatId &&
      widget.messageId == messageId;

  Future<MessageReactionAvailability> _fetchAvailability({
    required int accountSlot,
    required int chatId,
    required int messageId,
  }) async {
    final client = TdClient.shared;
    final responses = await Future.wait([
      client.queryForSlot({
        '@type': 'getMessageAvailableReactions',
        'chat_id': chatId,
        'message_id': messageId,
        'row_size': 25,
      }, accountSlot),
      client.queryForSlot({
        '@type': 'getOption',
        'name': 'is_premium',
      }, accountSlot),
    ]);
    return MessageReactionAvailability.fromTd(
      responses.first,
      isPremium: responses.last.boolean('value') ?? false,
    );
  }

  Future<void> _loadAvailability() async {
    final accountSlot = widget.accountSlot;
    final chatId = widget.chatId;
    final messageId = widget.messageId;
    final generation = ++_availabilityGeneration;
    MessageReactionAvailability? availability;
    var arbitraryCustomChoices = const <QuickReactionChoice>[];
    try {
      availability = await _fetchAvailability(
        accountSlot: accountSlot,
        chatId: chatId,
        messageId: messageId,
      );
      if (availability.allowArbitraryCustom) {
        arbitraryCustomChoices = await _cachedInstalledCustomReactionChoices(
          accountSlot,
        );
      }
    } catch (_) {
      // Fail closed: global reaction defaults are not authoritative for this
      // particular message and can trigger MESSAGE_REACTION_INVALID.
    }
    if (!mounted ||
        !_matchesTarget(accountSlot, chatId, messageId) ||
        generation != _availabilityGeneration) {
      return;
    }
    setState(() {
      _availability = availability;
      _arbitraryCustomChoices = arbitraryCustomChoices;
    });
  }

  @override
  Widget build(BuildContext context) {
    var action = momentsReactionAction(_availability);
    if (action == MomentsReactionAction.openSelector &&
        _availability!.choices.isEmpty &&
        _arbitraryCustomChoices.isEmpty) {
      // TDLib permits arbitrary custom emoji, but this account has none to
      // present. Do not expose a selector that contains zero choices.
      action = MomentsReactionAction.hidden;
    }
    if (action == MomentsReactionAction.hidden) {
      return widget.hiddenBuilder?.call(context) ?? const SizedBox.shrink();
    }
    final icon = action == MomentsReactionAction.sendThumbsUp
        ? HeroAppIcons.thumbsUp
        : HeroAppIcons.solidFaceSmile;
    return GestureDetector(
      key: ValueKey('${widget.keyNamespace}-action'),
      behavior: HitTestBehavior.opaque,
      onTap: _sending
          ? null
          : action == MomentsReactionAction.sendThumbsUp
          ? () => unawaited(_sendReaction(_thumbsUp))
          : () => unawaited(_openSelector()),
      onLongPress: _sending ? null : () => unawaited(_openSelector()),
      child: widget.contentBuilder(context, icon),
    );
  }

  Future<void> _openSelector() async {
    final accountSlot = widget.accountSlot;
    final chatId = widget.chatId;
    final messageId = widget.messageId;
    final generation = _availabilityGeneration;
    final availability = _availability;
    if (availability == null) return;
    final choices = <QuickReactionChoice>[
      ...availability.choices,
      for (final choice in _arbitraryCustomChoices)
        if (!availability.choices.contains(choice)) choice,
    ];
    if (choices.isEmpty) return;
    final selected = await showAppModalSheet<QuickReactionChoice>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _MomentsReactionSelector(choices: choices),
    );
    if (selected == null ||
        !mounted ||
        !_matchesTarget(accountSlot, chatId, messageId) ||
        generation != _availabilityGeneration) {
      return;
    }
    await _sendReaction(selected);
  }

  Future<void> _sendReaction(QuickReactionChoice requested) async {
    if (_sending) return;
    final accountSlot = widget.accountSlot;
    final chatId = widget.chatId;
    final messageId = widget.messageId;
    final generation = _availabilityGeneration;
    setState(() => _sending = true);
    try {
      // Availability can change while a row or selector is onscreen. Re-read
      // it immediately before mutation and send TDLib's canonical value.
      final fresh = await _fetchAvailability(
        accountSlot: accountSlot,
        chatId: chatId,
        messageId: messageId,
      );
      final freshArbitraryCustomChoices = fresh.allowArbitraryCustom
          ? await _cachedInstalledCustomReactionChoices(accountSlot)
          : const <QuickReactionChoice>[];
      if (!mounted ||
          !_matchesTarget(accountSlot, chatId, messageId) ||
          generation != _availabilityGeneration) {
        return;
      }
      setState(() {
        _availability = fresh;
        // A message can become restricted while its selector is open. Never
        // retain account-wide custom choices after the authoritative response
        // stops allowing them for this message.
        _arbitraryCustomChoices = freshArbitraryCustomChoices;
      });
      final reaction = fresh.canonicalChoice(requested);
      if (reaction == null) return;
      await TdClient.shared.queryForSlot({
        '@type': 'addMessageReaction',
        'chat_id': chatId,
        'message_id': messageId,
        'reaction_type': reaction.isCustom
            ? {
                '@type': 'reactionTypeCustomEmoji',
                'custom_emoji_id': reaction.customEmojiId,
              }
            : {'@type': 'reactionTypeEmoji', 'emoji': reaction.emoji},
        'is_big': false,
        'update_recent_reactions': true,
      }, accountSlot);
      if (!mounted || !_matchesTarget(accountSlot, chatId, messageId)) return;
      widget.onReactionSent?.call();
      showToast(context, AppStringKeys.momentsLiked);
    } catch (_) {
      if (mounted && _matchesTarget(accountSlot, chatId, messageId)) {
        showToast(context, AppStringKeys.topicPostContentActionFailed);
      }
    } finally {
      if (mounted && _matchesTarget(accountSlot, chatId, messageId)) {
        setState(() => _sending = false);
      }
    }
  }
}

class _MomentsReactionSelector extends StatelessWidget {
  const _MomentsReactionSelector({required this.choices});

  final List<QuickReactionChoice> choices;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      child: Container(
        key: const ValueKey('moments-reaction-selector'),
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 320),
        margin: const EdgeInsets.all(AppSpacing.md),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: c.divider, width: AppMetric.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: GridView.builder(
          shrinkWrap: true,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: AppSpacing.xs,
            crossAxisSpacing: AppSpacing.xs,
          ),
          itemCount: choices.length,
          itemBuilder: (context, index) {
            final reaction = choices[index];
            return GestureDetector(
              key: ValueKey('moments-reaction-choice-${reaction.storageValue}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(reaction),
              child: SizedBox.square(
                dimension: 42,
                child: Center(
                  child: reaction.isCustom
                      ? CustomEmojiView(
                          id: reaction.customEmojiId,
                          size: 29,
                          color: c.textPrimary,
                        )
                      : Text(
                          reaction.emoji,
                          textScaler: TextScaler.noScaling,
                          style: const TextStyle(fontSize: 29),
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

const _installedCustomReactionClientCacheLimit = 8;
const _installedCustomReactionSetLimit = 24;
const _installedCustomReactionChoiceLimit = 280;
const _installedCustomReactionCacheLifetime = Duration(minutes: 10);

class _InstalledCustomReactionChoiceCacheEntry {
  const _InstalledCustomReactionChoiceCacheEntry({
    required this.createdAt,
    required this.value,
  });

  final DateTime createdAt;
  final Future<List<QuickReactionChoice>> value;
}

final Map<int, _InstalledCustomReactionChoiceCacheEntry>
_installedCustomReactionChoiceCache = {};

@visibleForTesting
void resetMomentsInstalledCustomReactionChoiceCache() {
  _installedCustomReactionChoiceCache.clear();
}

Future<List<QuickReactionChoice>> _cachedInstalledCustomReactionChoices(
  int accountSlot,
) {
  final clientId = TdClient.shared.clientId(accountSlot);
  if (clientId == null) return Future.value(const <QuickReactionChoice>[]);
  final now = DateTime.now();
  final cached = _installedCustomReactionChoiceCache.remove(clientId);
  if (cached != null &&
      now.difference(cached.createdAt) <
          _installedCustomReactionCacheLifetime) {
    _installedCustomReactionChoiceCache[clientId] = cached;
    return cached.value;
  }

  // Store the in-flight future before issuing pack requests. Every visible
  // post/comment for this client then joins the same bounded load.
  final value = _loadInstalledCustomReactionChoices(
    accountSlot,
  ).then((choices) => choices, onError: (_) => const <QuickReactionChoice>[]);
  _installedCustomReactionChoiceCache[clientId] =
      _InstalledCustomReactionChoiceCacheEntry(createdAt: now, value: value);
  while (_installedCustomReactionChoiceCache.length >
      _installedCustomReactionClientCacheLimit) {
    _installedCustomReactionChoiceCache.remove(
      _installedCustomReactionChoiceCache.keys.first,
    );
  }
  return value;
}

Future<List<QuickReactionChoice>> _loadInstalledCustomReactionChoices(
  int accountSlot,
) async {
  final client = TdClient.shared;
  final installed = await client.queryForSlot({
    '@type': 'getInstalledStickerSets',
    'sticker_type': {'@type': 'stickerTypeCustomEmoji'},
  }, accountSlot);
  final infos = installed.objects('sets') ?? const <Map<String, dynamic>>[];
  final sets = await Future.wait(
    infos.take(_installedCustomReactionSetLimit).map((info) async {
      final setId = info.int64('id');
      if (setId == null) return null;
      try {
        return await client.queryForSlot({
          '@type': 'getStickerSet',
          'set_id': setId,
        }, accountSlot);
      } catch (_) {
        return null;
      }
    }),
  );
  final choices = <QuickReactionChoice>[];
  final seen = <int>{};
  for (final set in sets.whereType<Map<String, dynamic>>()) {
    for (final sticker
        in set.objects('stickers') ?? const <Map<String, dynamic>>[]) {
      final id = sticker.obj('full_type')?.int64('custom_emoji_id') ?? 0;
      if (id != 0 && seen.add(id)) {
        choices.add(QuickReactionChoice.custom(id));
        if (choices.length >= _installedCustomReactionChoiceLimit) {
          return List.unmodifiable(choices);
        }
      }
    }
  }
  return List.unmodifiable(choices);
}
