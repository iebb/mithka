part of 'moments_view.dart';

class _MomentsComposerHeader extends StatelessWidget {
  const _MomentsComposerHeader({
    required this.name,
    this.photo,
    required this.backgroundColor,
    this.profileColors,
    this.profileIconId = 0,
    this.emojiStatusId = 0,
    this.isPremium = false,
    required this.canCompose,
    required this.onCompose,
  });

  final String name;
  final TdFileRef? photo;
  final Color backgroundColor;
  final List<Color>? profileColors;
  final int profileIconId;
  final int emojiStatusId;
  final bool isPremium;
  final bool canCompose;
  final VoidCallback onCompose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final foreground = profileColors != null || photo != null
        ? Colors.white
        : c.textPrimary;
    return Container(
      color: c.background,
      child: Column(
        children: [
          SizedBox(
            height: 166,
            child: Stack(
              children: [
                Positioned.fill(
                  child: profileColors != null
                      ? ProfileHeaderBackground(
                          colors: profileColors!,
                          photoCenter: const Offset(55, 109),
                          photoRadius: 37,
                          patternEmojiId: profileIconId,
                        )
                      : photo == null
                      ? ColoredBox(color: backgroundColor)
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            RepaintBoundary(
                              child: ImageFiltered(
                                imageFilter: ui.ImageFilter.blur(
                                  sigmaX: 28,
                                  sigmaY: 28,
                                ),
                                child: TDImage(photo: photo, cornerRadius: 0),
                              ),
                            ),
                            ColoredBox(
                              color: Colors.black.withValues(alpha: 0.18),
                            ),
                          ],
                        ),
                ),
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 20,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      PhotoAvatar(title: name, photo: photo, size: 74),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 25,
                                        height: 1.08,
                                        fontWeight: FontWeight.w600,
                                        color: foreground,
                                      ),
                                    ),
                                  ),
                                  if (emojiStatusId != 0) ...[
                                    const SizedBox(width: 6),
                                    StatusEmojiView(
                                      id: emojiStatusId,
                                      size: 22,
                                      color: foreground,
                                    ),
                                  ],
                                  if (isPremium) ...[
                                    const SizedBox(width: 6),
                                    const VipBadge(),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (canCompose)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: c.background,
                  border: Border.all(color: c.divider),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onCompose,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        AppStringKeys.momentsShareSomethingPlaceholder.l10n(
                          context,
                        ),
                        style: TextStyle(fontSize: 14, color: c.textTertiary),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ChannelMomentsSearchView extends StatefulWidget {
  const ChannelMomentsSearchView({
    super.key,
    required this.channels,
    required this.meName,
    this.mePhoto,
  });

  final List<ChatSummary> channels;
  final String meName;
  final TdFileRef? mePhoto;

  @override
  State<ChannelMomentsSearchView> createState() =>
      _ChannelMomentsSearchViewState();
}

class _ChannelMomentsSearchViewState extends State<ChannelMomentsSearchView> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  String _query = '';
  bool _loading = false;
  List<ChannelPost> _results = const [];

  List<ChatSummary> get _channels =>
      widget.channels.where((chat) => chat.kind == ChatKind.channel).toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _loading = false;
        _results = const [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(query));
  }

  Future<void> _run(String query) async {
    final channels = _channels;
    if (channels.isEmpty) {
      setState(() {
        _loading = false;
        _results = const [];
      });
      return;
    }
    setState(() => _loading = true);
    final currentQuery = query;
    try {
      final batches = await Future.wait(
        channels.map((channel) => _searchChannel(channel, currentQuery)),
      );
      final results = batches.expand((items) => items).toList()
        ..sort((a, b) => b.message.date.compareTo(a.message.date));
      if (!mounted || _query.trim() != currentQuery) return;
      setState(() {
        _results = results.take(120).toList();
        _loading = false;
      });
      _hydrateAuthors(_results);
    } catch (_) {
      if (mounted && _query.trim() == currentQuery) {
        setState(() => _loading = false);
      }
    }
  }

  Future<List<ChannelPost>> _searchChannel(
    ChatSummary channel,
    String query,
  ) async {
    final accountSlot = TdClient.shared.activeSlot;
    try {
      final response = await TdClient.shared.queryForSlot({
        '@type': 'searchChatMessages',
        'chat_id': channel.id,
        'query': query,
        'sender_id': null,
        'from_message_id': 0,
        'offset': 0,
        'limit': 30,
        'filter': {'@type': 'searchMessagesFilterEmpty'},
      }, accountSlot);
      final rawMessages =
          response.objects('messages') ?? const <Map<String, dynamic>>[];
      return [
        for (final raw in rawMessages)
          if ((raw.int64('chat_id') ?? channel.id) == channel.id)
            if (TDParse.message(raw) case final message?)
              if (!message.isService)
                ChannelPost(
                  channel: channel,
                  message: message,
                  accountSlot: accountSlot,
                ),
      ];
    } catch (_) {
      return const [];
    }
  }

  void _hydrateAuthors(List<ChannelPost> posts) {
    for (final post in posts) {
      if (_isChannelSelfPost(post)) {
        post.authorName = null;
        post.authorPhoto = null;
        continue;
      }
      if (post.authorName != null) continue;
      unawaited(_resolvePostAuthor(post));
    }
  }

  Future<void> _resolvePostAuthor(ChannelPost post) async {
    if (_isChannelSelfPost(post)) {
      post.authorName = null;
      post.authorPhoto = null;
      return;
    }
    final senderId = post.message.senderId;
    try {
      if (senderId != null && senderId > 0) {
        final user = await TdClient.shared.query({
          '@type': 'getUser',
          'user_id': senderId,
        });
        final name = TDParse.userName(user).trim();
        if (name.isNotEmpty) post.authorName = name;
        post.authorPhoto = TDParse.smallPhoto(user.obj('profile_photo'));
      } else if (senderId != null && senderId < 0) {
        final chat = await TdClient.shared.query({
          '@type': 'getChat',
          'chat_id': senderId,
        });
        final name = chat.str('title')?.trim();
        if (name != null && name.isNotEmpty) post.authorName = name;
        post.authorPhoto = TDParse.smallPhoto(chat.obj('photo'));
      } else {
        final title = post.message.senderTitle?.trim();
        if (title != null && title.isNotEmpty) {
          post.authorName = title;
        }
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  void _openPost(ChannelPost post) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChannelPostDetailView(post: post)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          _header(),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _header() {
    final c = context.colors;
    return Container(
      padding: headerChromePaddingOf(context),
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: SizedBox(
        height: 50,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: AppIcon(
                    HeroAppIcons.chevronLeft,
                    size: 22,
                    color: c.textPrimary,
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: c.searchFill,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      AppIcon(
                        HeroAppIcons.magnifyingGlass,
                        size: 15,
                        color: c.textTertiary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focus,
                          autocorrect: false,
                          textInputAction: TextInputAction.search,
                          style: TextStyle(fontSize: 15, color: c.textPrimary),
                          decoration: InputDecoration(
                            hintText: AppStrings.t(
                              AppStringKeys.momentsSearchChannelPosts,
                            ).l10n(context),
                            hintStyle: TextStyle(color: c.textTertiary),
                            border: InputBorder.none,
                            isCollapsed: true,
                          ),
                          onChanged: _onChanged,
                          onSubmitted: (value) => _run(value.trim()),
                        ),
                      ),
                      if (_query.isNotEmpty)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            _controller.clear();
                            _onChanged('');
                          },
                          child: AppIcon(
                            HeroAppIcons.xmark,
                            size: 16,
                            color: c.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    final c = context.colors;
    if (_channels.isEmpty) {
      return Center(
        child: Text(
          AppStringKeys.momentsNoSearchableChannels.l10n(context),
          style: TextStyle(fontSize: 14, color: c.textSecondary),
        ),
      );
    }
    if (_loading && _results.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator.adaptive(strokeWidth: 2),
        ),
      );
    }
    if (_query.trim().isEmpty) {
      return Center(
        child: Text(
          AppStringKeys.momentsSearchJoinedChannelPosts.l10n(context),
          style: TextStyle(fontSize: 14, color: c.textSecondary),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          (_loading
                  ? AppStringKeys.momentsSearching
                  : AppStringKeys.momentsNoPostsFound)
              .l10n(context),
          style: TextStyle(fontSize: 14, color: c.textSecondary),
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final post = _results[index];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChannelPostRow(
              post: post,
              meName: widget.meName,
              mePhoto: widget.mePhoto,
              onOpenPost: _openPost,
              showInlineReply: false,
              showInlineComments: false,
            ),
            if (index != _results.length - 1)
              const InsetDivider(leadingInset: 0),
          ],
        );
      },
    );
  }
}

void openChannelPostOriginal(BuildContext context, ChannelPost post) {
  pushAppChatRoute(
    context,
    AppChatPageRoute<void>(
      builder: (_) => ChatView(
        chatId: post.channel.id,
        title: post.channel.title,
        initialMessageId: post.message.id,
      ),
    ),
  );
}

Future<void> showChannelPostMenu(BuildContext context, ChannelPost post) {
  final anchor = context.findRenderObject() as RenderBox?;
  final overlay =
      Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
  if (anchor == null || overlay == null) {
    openChannelPostOriginal(context, post);
    return Future.value();
  }
  final anchorTopLeft = anchor.localToGlobal(Offset.zero, ancestor: overlay);
  final anchorBottomRight = anchor.localToGlobal(
    anchor.size.bottomRight(Offset.zero),
    ancestor: overlay,
  );
  final anchorRect = Rect.fromLTRB(
    anchorTopLeft.dx,
    anchorTopLeft.dy,
    anchorBottomRight.dx,
    anchorBottomRight.dy + 4,
  );
  return showMenu<_ChannelPostMenuAction>(
    context: context,
    position: RelativeRect.fromRect(anchorRect, Offset.zero & overlay.size),
    color: context.colors.card,
    elevation: 8,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.card),
    ),
    items: [
      PopupMenuItem<_ChannelPostMenuAction>(
        value: _ChannelPostMenuAction.openOriginal,
        height: AppMetric.menuRowHeight,
        child: Row(
          children: [
            SizedBox(
              width: AppMetric.menuIconSlot,
              child: AppIcon(
                HeroAppIcons.rightFromBracket,
                size: AppIconSize.lg + 1,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(width: AppSpacing.xl),
            Text(
              AppStringKeys.momentsOpenOriginalMessage.l10n(context),
              style: TextStyle(
                fontSize: AppTextSize.bodyLarge,
                color: context.colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    ],
  ).then((action) {
    if (!context.mounted) return;
    switch (action) {
      case _ChannelPostMenuAction.openOriginal:
        openChannelPostOriginal(context, post);
      case null:
        break;
    }
  });
}

enum _ChannelPostMenuAction { openOriginal }

class _ChannelPostOverflowButton extends StatelessWidget {
  const _ChannelPostOverflowButton({required this.post});

  final ChannelPost post;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showChannelPostMenu(context, post),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
        child: AppIcon(HeroAppIcons.ellipsis, size: 22, color: c.textTertiary),
      ),
    );
  }
}

class ChannelPostDetailView extends StatefulWidget {
  const ChannelPostDetailView({
    super.key,
    required this.post,
    this.showBackButton = true,
  });

  final ChannelPost post;
  final bool showBackButton;

  @override
  State<ChannelPostDetailView> createState() => _ChannelPostDetailViewState();
}

class _ChannelPostDetailViewState extends State<ChannelPostDetailView> {
  final _replyController = TextEditingController();
  final _replyFocus = FocusNode();
  StreamSubscription? _tdSub;
  Timer? _refreshTimer;
  ChannelPostThreadTarget? _target;
  List<ChannelPostComment> _comments = const [];
  ChannelPostComment? _replyTo;
  String _meName = AppStrings.t(AppStringKeys.chatMeLabel);
  TdFileRef? _mePhoto;
  bool _loading = true;
  bool _sending = false;

  ChannelPost get post => widget.post;

  @override
  void initState() {
    super.initState();
    _target = post.threadTarget;
    _tdSub = TdClient.shared
        .updatesOfAny(const [
          'updateNewMessage',
          'updateMessageContent',
          'updateMessageEdited',
          'updateMessageInteractionInfo',
          'updateDeleteMessages',
        ])
        .listen(_handleTdUpdate);
    _loadMe();
    _loadComments();
  }

  @override
  void dispose() {
    _tdSub?.cancel();
    _refreshTimer?.cancel();
    _replyController.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  Future<void> _loadMe() async {
    try {
      final me = await TdClient.shared.queryForSlot({
        '@type': 'getMe',
      }, post.accountSlot);
      if (!mounted) return;
      final name = TDParse.userName(me).trim();
      setState(() {
        if (name.isNotEmpty) _meName = name;
        _mePhoto = TDParse.smallPhoto(me.obj('profile_photo'));
      });
    } catch (_) {}
  }

  void _handleTdUpdate(Map<String, dynamic> update) {
    final rawMessage = update.obj('message');
    final chatId = update.int64('chat_id') ?? rawMessage?.int64('chat_id');
    final target = _target;
    final touchesPost = chatId == post.channel.id;
    final touchesThread = target != null && chatId == target.chatId;
    if (!touchesPost && !touchesThread) return;
    switch (update.type) {
      case 'updateNewMessage':
      case 'updateMessageContent':
      case 'updateMessageEdited':
      case 'updateMessageInteractionInfo':
      case 'updateDeleteMessages':
        _refreshTimer?.cancel();
        _refreshTimer = Timer(const Duration(milliseconds: 350), _loadComments);
    }
  }

  Future<ChannelPostThreadTarget?> _resolveThreadTarget() async {
    if (_target != null) return _target;
    try {
      final target = await _fetchChannelPostThreadTarget(post);
      if (target == null) return null;
      post.threadTarget = target;
      _target = target;
      return target;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadComments() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final target = await _resolveThreadTarget();
      if (target == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final response = await TdClient.shared.queryForSlot(
        _commentsRequest(fromMessageId: 0, offset: 0, limit: 120),
        post.accountSlot,
      );
      final rawMessages =
          response.objects('messages') ?? const <Map<String, dynamic>>[];
      final kept = <_LoadedPostComment>[];
      for (final raw in rawMessages) {
        final message = TDParse.message(raw);
        if (message == null ||
            message.isService ||
            message.id == post.message.id ||
            message.id == target.messageThreadId ||
            _commentText(message).isEmpty) {
          continue;
        }
        kept.add(
          _LoadedPostComment(
            chatId: raw.int64('chat_id') ?? target.chatId,
            message: message,
          ),
        );
      }
      final keptByChatAndId =
          <({int chatId, int messageId}), _LoadedPostComment>{
            for (final entry in kept)
              (chatId: entry.chatId, messageId: entry.message.id): entry,
          };
      final missingRepliesByChat = <int, Set<int>>{};
      for (final entry in kept) {
        final rid = entry.message.replyToMessageId;
        final rChatId = entry.message.replyToChatId ?? entry.chatId;
        final isPostRoot =
            (rChatId == post.channel.id && rid == post.message.id) ||
            (rChatId == target.chatId && rid == target.messageThreadId);
        if (rid == null ||
            isPostRoot ||
            keptByChatAndId.containsKey((chatId: rChatId, messageId: rid))) {
          continue;
        }
        missingRepliesByChat.putIfAbsent(rChatId, () => <int>{}).add(rid);
      }
      final externalReplyTargets =
          <({int chatId, int messageId}), ChatMessage>{};
      for (final batch in missingRepliesByChat.entries) {
        try {
          final res = await TdClient.shared.queryForSlot({
            '@type': 'getMessages',
            'chat_id': batch.key,
            'message_ids': batch.value.toList(),
          }, post.accountSlot);
          for (final raw
              in res.objects('messages') ?? const <Map<String, dynamic>>[]) {
            final quoted = TDParse.message(raw);
            if (quoted != null) {
              final qChatId = quoted.chatId ?? batch.key;
              externalReplyTargets[(chatId: qChatId, messageId: quoted.id)] =
                  quoted;
            }
          }
        } catch (_) {}
      }
      // One query per distinct sender, in parallel. Resolving inline below
      // serialized up to 120 getUser/getChat round-trips, mostly repeats.
      final firstBySender = <int, ChatMessage>{};
      for (final entry in kept) {
        final senderId = entry.message.senderId;
        if (senderId != null) {
          firstBySender.putIfAbsent(senderId, () => entry.message);
        }
      }
      for (final quoted in externalReplyTargets.values) {
        final senderId = quoted.senderId;
        if (senderId != null) {
          firstBySender.putIfAbsent(senderId, () => quoted);
        }
      }
      final senders = <int, _CommentSender>{};
      await Future.wait(
        firstBySender.entries.map((entry) async {
          senders[entry.key] = await _commentSender(entry.value);
        }),
      );
      final externalReplySenders = <({int chatId, int messageId}), String>{};
      for (final entry in externalReplyTargets.entries) {
        final quoted = entry.value;
        final senderId = quoted.senderId;
        final cached = senderId == null ? null : senders[senderId];
        final sender = cached ?? await _commentSender(quoted);
        externalReplySenders[entry.key] = sender.name;
      }
      final comments = <ChannelPostComment>[];
      for (final entry in kept) {
        final message = entry.message;
        final senderId = message.senderId;
        final cached = senderId == null ? null : senders[senderId];
        final sender = cached ?? await _commentSender(message);
        final rid = message.replyToMessageId;
        final rChatId = message.replyToChatId ?? entry.chatId;
        comments.add(
          ChannelPostComment(
            chatId: entry.chatId,
            messageId: message.id,
            senderName: sender.name,
            senderPhoto: sender.photo,
            text: _commentText(message),
            entities: _commentEntities(message),
            date: message.date,
            replyToChatId: rid == null ? null : rChatId,
            replyToMessageId: rid,
            replyToSenderName: rid == null
                ? null
                : externalReplySenders[(chatId: rChatId, messageId: rid)],
            reactionCount: _reactionCount(message),
          ),
        );
      }
      comments.sort((a, b) => a.date.compareTo(b.date));
      if (!mounted) return;
      setState(() {
        _comments = comments;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The `getMessageThreadHistory` request for this post's comments.
  ///
  /// Delegates to [channelPostCommentsRequest] so the feed and this view agree.
  Map<String, dynamic> _commentsRequest({
    required int fromMessageId,
    required int offset,
    required int limit,
  }) => channelPostCommentsRequest(
    post: post,
    target: _target,
    fromMessageId: fromMessageId,
    offset: offset,
    limit: limit,
  );

  String _commentText(ChatMessage message) {
    return message.text.trim();
  }

  List<MessageTextEntity> _commentEntities(ChatMessage message) {
    // The comment text is shown trimmed; keep the formatting by re-addressing
    // the entities to the trimmed string instead of dropping them all.
    return trimTextForDisplay(message.text, message.textEntities).entities;
  }

  int _reactionCount(ChatMessage message) =>
      message.reactions.fold<int>(0, (sum, reaction) => sum + reaction.count);

  Future<_CommentSender> _commentSender(ChatMessage message) async {
    final title = message.senderTitle?.trim();
    final senderId = message.senderId;
    try {
      if (senderId != null && senderId > 0) {
        final user = await TdClient.shared.queryForSlot({
          '@type': 'getUser',
          'user_id': senderId,
        }, post.accountSlot);
        final name = TDParse.userName(user).trim();
        return _CommentSender(
          name: name.isNotEmpty
              ? name
              : title ?? AppStrings.t(AppStringKeys.topicChatUsers),
          photo: TDParse.smallPhoto(user.obj('profile_photo')),
        );
      }
      if (senderId != null && senderId < 0) {
        final chat = await TdClient.shared.queryForSlot({
          '@type': 'getChat',
          'chat_id': senderId,
        }, post.accountSlot);
        final name = chat.str('title')?.trim();
        return _CommentSender(
          name: name == null || name.isEmpty
              ? title ?? AppStrings.t(AppStringKeys.topicChatUsers)
              : name,
          photo: TDParse.smallPhoto(chat.obj('photo')),
        );
      }
    } catch (_) {}
    return _CommentSender(
      name: title == null || title.isEmpty
          ? AppStrings.t(AppStringKeys.topicChatUsers)
          : title,
    );
  }

  void _beginReply([ChannelPostComment? comment]) {
    setState(() => _replyTo = comment);
    _replyFocus.requestFocus();
  }

  Future<void> _sendReply() async {
    final target = await _resolveThreadTarget();
    final text = _replyController.text.trim();
    if (target == null || text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final replyTo = _replyTo;
    final content = {
      '@type': 'inputMessageText',
      'text': {'@type': 'formattedText', 'text': text},
    };
    try {
      final replyMessageId = replyTo?.messageId;
      if (replyMessageId == null) {
        await TdClient.shared.queryForSlot({
          '@type': 'sendMessage',
          'chat_id': target.chatId,
          'topic_id': {
            '@type': 'messageTopicThread',
            'message_thread_id': target.messageThreadId,
          },
          'input_message_content': content,
        }, post.accountSlot);
      } else {
        try {
          await TdClient.shared.queryForSlot({
            '@type': 'sendMessage',
            'chat_id': target.chatId,
            'topic_id': {
              '@type': 'messageTopicThread',
              'message_thread_id': target.messageThreadId,
            },
            'reply_to': {
              '@type': 'inputMessageReplyToMessage',
              'message_id': replyMessageId,
            },
            'input_message_content': content,
          }, post.accountSlot);
        } catch (_) {
          await TdClient.shared.queryForSlot({
            '@type': 'sendMessage',
            'chat_id': target.chatId,
            'reply_to': {
              '@type': 'inputMessageReplyToMessage',
              'message_id': replyMessageId,
            },
            'input_message_content': content,
          }, post.accountSlot);
        }
      }
      _replyController.clear();
      if (!mounted) return;
      setState(() => _replyTo = null);
      await _loadComments();
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.momentsReplyFailed, {'value1': e}),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          NavHeader(
            title: AppStringKeys.momentsDetails,
            onBack: widget.showBackButton
                ? () => Navigator.of(context).pop()
                : null,
            trailing: Builder(
              builder: (menuContext) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => showChannelPostMenu(menuContext, post),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: AppIcon(
                      HeroAppIcons.ellipsis,
                      size: 24,
                      color: c.textPrimary,
                    ),
                  ),
                );
              },
            ),
          ),
          Expanded(
            // Slivers, not a Column of every comment: a thread of 120 rebuilt
            // and laid out all of its tiles on each incoming-comment refresh.
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: ChannelPostRow(
                    post: post,
                    meName: '',
                    showInlineReply: false,
                    showInlineComments: false,
                  ),
                ),
                const SliverToBoxAdapter(child: InsetDivider(leadingInset: 14)),
                if (_loading && _comments.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
                else
                  _CommentThreadList(
                    post: post,
                    comments: _comments,
                    onReply: _beginReply,
                    onReactionSent: () => unawaited(_loadComments()),
                  ),
              ],
            ),
          ),
          if (_target != null || post.message.hasCommentThread)
            _bottomReplyBar(),
        ],
      ),
    );
  }

  Widget _bottomReplyBar() {
    final c = context.colors;
    final replyTo = _replyTo;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        decoration: BoxDecoration(
          color: c.background,
          border: Border(top: BorderSide(color: c.divider)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (replyTo != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppStrings.t(AppStringKeys.momentsReplyToUser, {
                          'value1': replyTo.senderName,
                        }),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: c.linkBlue),
                      ),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _replyTo = null),
                      child: AppIcon(
                        HeroAppIcons.solidCircleXmark,
                        size: 18,
                        color: c.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              constraints: const BoxConstraints(minHeight: 42),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: _momentQuoteFill(c),
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Row(
                children: [
                  PhotoAvatar(title: _meName, photo: _mePhoto, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _replyController,
                      focusNode: _replyFocus,
                      minLines: 1,
                      maxLines: 3,
                      textInputAction: TextInputAction.send,
                      onTap: () => _beginReply(_replyTo),
                      onSubmitted: (_) => _sendReply(),
                      style: TextStyle(fontSize: 15, color: c.textPrimary),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isCollapsed: true,
                        hintText: replyTo == null
                            ? AppStrings.t(
                                AppStringKeys.momentsCommentPlaceholder,
                              )
                            : AppStrings.t(
                                AppStringKeys.momentsReplyToUserPlaceholder,
                                {'value1': replyTo.senderName},
                              ),
                        hintStyle: TextStyle(color: c.textTertiary),
                      ),
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _sendReply,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: AppIcon(
                        HeroAppIcons.solidPaperPlane,
                        size: 21,
                        color: AppTheme.brand.withValues(
                          alpha: _sending ? 0.45 : 1,
                        ),
                      ),
                    ),
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

class _CommentSender {
  const _CommentSender({required this.name, this.photo});

  final String name;
  final TdFileRef? photo;
}

/// One flattened row of the comment thread: a root or one of its replies.
class _ThreadEntry {
  const _ThreadEntry({
    required this.comment,
    required this.endsGroup,
    this.prefix,
    this.nested = false,
  });

  final ChannelPostComment comment;
  final String? prefix;
  final bool nested;

  /// Last tile of a root-plus-replies group — carries the gap that used to be
  /// a SizedBox between groups.
  final bool endsGroup;
}

class _CommentThreadList extends StatelessWidget {
  const _CommentThreadList({
    required this.post,
    required this.comments,
    required this.onReply,
    required this.onReactionSent,
  });

  final ChannelPost post;
  final List<ChannelPostComment> comments;
  final ValueChanged<ChannelPostComment> onReply;
  final VoidCallback onReactionSent;

  @override
  Widget build(BuildContext context) {
    if (comments.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Center(
            child: Text(
              AppStringKeys.momentsNoComments.l10n(context),
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textTertiary,
              ),
            ),
          ),
        ),
      );
    }
    final byChatAndId = <({int chatId, int messageId}), ChannelPostComment>{
      for (final comment in comments)
        (chatId: comment.chatId, messageId: comment.messageId): comment,
    };
    final roots = comments
        .where((comment) => _isRoot(comment, byChatAndId))
        .toList();
    final childrenByRoot = <int, List<ChannelPostComment>>{};
    for (final comment in comments) {
      if (_isRoot(comment, byChatAndId)) continue;
      final rootId = _rootId(comment, byChatAndId);
      childrenByRoot.putIfAbsent(rootId, () => []).add(comment);
    }
    // Flattened once per build so the tiles themselves can be built lazily.
    final entries = <_ThreadEntry>[];
    for (final root in roots) {
      final children =
          childrenByRoot[root.messageId] ?? const <ChannelPostComment>[];
      entries.add(
        _ThreadEntry(
          comment: root,
          prefix: _rootReplyPrefix(root),
          endsGroup: children.isEmpty,
        ),
      );
      for (var i = 0; i < children.length; i++) {
        entries.add(
          _ThreadEntry(
            comment: children[i],
            prefix: _replyPrefix(children[i], root, byChatAndId),
            nested: true,
            endsGroup: i == children.length - 1,
          ),
        );
      }
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
      sliver: SliverList.builder(
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          final tile = _DetailCommentTile(
            comment: entry.comment,
            accountSlot: post.accountSlot,
            prefix: entry.prefix,
            nested: entry.nested,
            onReply: onReply,
            onReactionSent: onReactionSent,
          );
          if (!entry.endsGroup) return tile;
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: tile,
          );
        },
      ),
    );
  }

  ({int chatId, int messageId})? _replyKey(ChannelPostComment comment) {
    final rid = comment.replyToMessageId;
    if (rid == null) return null;
    return (chatId: comment.replyToChatId ?? comment.chatId, messageId: rid);
  }

  bool _isPostRootReply(ChannelPostComment comment) {
    final rid = comment.replyToMessageId;
    if (rid == null) return true;
    final rChatId = comment.replyToChatId ?? comment.chatId;
    if (rChatId == post.channel.id && rid == post.message.id) return true;
    final target = post.threadTarget;
    if (target != null &&
        rChatId == target.chatId &&
        rid == target.messageThreadId) {
      return true;
    }
    return false;
  }

  bool _isRoot(
    ChannelPostComment comment,
    Map<({int chatId, int messageId}), ChannelPostComment> byChatAndId,
  ) {
    if (_isPostRootReply(comment)) return true;
    final key = _replyKey(comment);
    return key == null || !byChatAndId.containsKey(key);
  }

  int _rootId(
    ChannelPostComment comment,
    Map<({int chatId, int messageId}), ChannelPostComment> byChatAndId,
  ) {
    var current = comment;
    final seen = <({int chatId, int messageId})>{};
    while (seen.add((chatId: current.chatId, messageId: current.messageId))) {
      final key = _replyKey(current);
      if (key == null) break;
      final parent = byChatAndId[key];
      if (parent == null) break;
      if (_isRoot(parent, byChatAndId)) return parent.messageId;
      current = parent;
    }
    return current.messageId;
  }

  String? _rootReplyPrefix(ChannelPostComment comment) {
    if (_isPostRootReply(comment)) return null;
    final parentName = comment.replyToSenderName?.trim();
    if (parentName == null || parentName.isEmpty) return null;
    return AppStrings.t(AppStringKeys.momentsReplyPrefix, {
      'value1': parentName,
    });
  }

  String? _replyPrefix(
    ChannelPostComment comment,
    ChannelPostComment root,
    Map<({int chatId, int messageId}), ChannelPostComment> byChatAndId,
  ) {
    final key = _replyKey(comment);
    if (key == null ||
        (key.chatId == root.chatId && key.messageId == root.messageId)) {
      return null;
    }
    final parent = byChatAndId[key];
    final parentName = parent?.senderName ?? comment.replyToSenderName;
    if (parentName == null || parentName.trim().isEmpty) return null;
    return AppStrings.t(AppStringKeys.momentsReplyPrefix, {
      'value1': parentName,
    });
  }
}

class _DetailCommentTile extends StatelessWidget {
  const _DetailCommentTile({
    required this.comment,
    required this.accountSlot,
    required this.onReply,
    required this.onReactionSent,
    this.prefix,
    this.nested = false,
  });

  final ChannelPostComment comment;
  final int accountSlot;
  final String? prefix;
  final bool nested;
  final ValueChanged<ChannelPostComment> onReply;
  final VoidCallback onReactionSent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final avatarSize = nested ? 30.0 : 38.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onReply(comment),
      child: Padding(
        padding: EdgeInsets.only(left: nested ? 52 : 0, top: nested ? 10 : 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PhotoAvatar(
              title: comment.senderName,
              photo: comment.senderPhoto,
              size: avatarSize,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          comment.senderName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: c.linkBlue,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        DateText.listLabel(comment.date),
                        style: TextStyle(fontSize: 13, color: c.textTertiary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    children: [
                      if (prefix != null)
                        Text(
                          prefix!,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.28,
                            color: c.textSecondary,
                          ),
                        ),
                      TelegramRichText(
                        text: comment.text,
                        entities: comment.entities,
                        quoteBackgroundColor: _momentQuoteFill(c),
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.28,
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
                ],
              ),
            ),
            const SizedBox(width: 8),
            _MomentsReactionControl(
              accountSlot: accountSlot,
              chatId: comment.chatId,
              messageId: comment.messageId,
              keyNamespace: 'moments-comment-reaction-${comment.messageId}',
              onReactionSent: onReactionSent,
              hiddenBuilder: _reactionContent,
              contentBuilder: _reactionContent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _reactionContent(BuildContext context, [AppIconData? icon]) {
    final c = context.colors;
    return SizedBox(
      width: 34,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) AppIcon(icon, size: 21, color: c.textTertiary),
          if (comment.reactionCount > 0) ...[
            if (icon != null) const SizedBox(height: 3),
            Text(
              _compactCount(comment.reactionCount),
              key: ValueKey(
                'moments-comment-reaction-count-${comment.messageId}',
              ),
              style: TextStyle(fontSize: 12, color: c.textTertiary),
            ),
          ],
        ],
      ),
    );
  }

  String _compactCount(int count) {
    if (count > 99) return '99+';
    return '$count';
  }
}

class ChannelPostComposerView extends StatefulWidget {
  const ChannelPostComposerView({
    super.key,
    required this.channels,
    this.initialChannel,
  });

  final List<ChatSummary> channels;
  final ChatSummary? initialChannel;

  @override
  State<ChannelPostComposerView> createState() =>
      _ChannelPostComposerViewState();
}

class _ChannelPostComposerViewState extends State<ChannelPostComposerView> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final List<OutgoingAttachment> _attachments = [];
  FormattedTextPayload? _richTextPayload;
  ChatSummary? _channel;
  bool _notifySubscribers = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _channel =
        widget.initialChannel ??
        (widget.channels.isNotEmpty ? widget.channels.first : null);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          _header(),
          Expanded(
            child: ListView(
              padding: AppInsets.composerScreen,
              children: [
                _editorCard(),
                const SizedBox(height: AppSpacing.xl),
                _publishSettingsCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    final c = context.colors;
    return Container(
      padding:
          headerChromePaddingOf(context) +
          const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
      height: topChromeInsetOf(context) + AppMetric.composerHeaderHeight,
      color: c.groupedBackground,
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(false),
            child: Text(
              AppStringKeys.countryPickerCancel.l10n(context),
              style: AppTextStyle.bodyLarge(c.textPrimary),
            ),
          ),
          const Spacer(),
          Text(
            AppStringKeys.momentsCreatePostTitle.l10n(context),
            style: AppTextStyle.title(
              c.textPrimary,
              weight: AppTextWeight.semibold,
            ),
          ),
          const Spacer(),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _sending ? null : _send,
            child: Container(
              height: AppMetric.composerPublishButtonHeight,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xxl + AppSpacing.xxs,
              ),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.brand.withValues(alpha: _canSend ? 1 : 0.45),
                borderRadius: BorderRadius.circular(AppRadius.md + 1),
              ),
              child: Text(
                (_sending
                        ? AppStringKeys.momentsSending
                        : AppStringKeys.momentsPostAction)
                    .l10n(context),
                style: AppTextStyle.bodyLarge(
                  Colors.white,
                  weight: AppTextWeight.medium,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _editorCard() {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        AppSpacing.xl,
        AppSpacing.xxl,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            focusNode: _focus,
            autofocus: true,
            minLines: 9,
            maxLines: 16,
            textInputAction: TextInputAction.newline,
            contextMenuBuilder: (context, editableTextState) {
              return AppTextSelectionToolbar.fromButtonItems(
                context: context,
                anchors: editableTextState.contextMenuAnchors,
                items: editableTextState.contextMenuButtonItems,
              );
            },
            style: AppTextStyle.bodyLarge(c.textPrimary).copyWith(height: 1.4),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: AppStringKeys.momentsShareSomethingPlaceholder.l10n(
                context,
              ),
              hintStyle: AppTextStyle.bodyLarge(c.textTertiary),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),
          _mediaStrip(),
          const SizedBox(height: AppSpacing.lg),
          _markdownToolbar(),
        ],
      ),
    );
  }

  Widget _mediaStrip() {
    final children = <Widget>[
      for (var i = 0; i < _attachments.length; i++) _imageTile(i),
      if (_attachments.length < 10) _addImageTile(),
    ];
    return SizedBox(
      height: AppMetric.mediaTile,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
        itemBuilder: (_, index) => children[index],
      ),
    );
  }

  Widget _imageTile(int index) {
    final attachment = _attachments[index];
    final isVisual =
        attachment.kind == OutgoingAttachmentKind.photo ||
        attachment.kind == OutgoingAttachmentKind.video;
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: isVisual
              ? Image.file(
                  File(attachment.path),
                  width: AppMetric.mediaTile,
                  height: AppMetric.mediaTile,
                  // A picked camera photo is tens of megabytes decoded.
                  cacheWidth: 512,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _postAttachmentIcon(attachment),
                )
              : _postAttachmentIcon(attachment),
        ),
        Positioned(
          top: AppSpacing.xs,
          right: AppSpacing.xs,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _attachments.removeAt(index)),
            child: Container(
              width: AppMetric.overlayCloseButton,
              height: AppMetric.overlayCloseButton,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: const AppIcon(
                HeroAppIcons.xmark,
                size: AppIconSize.xs,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _postAttachmentIcon(OutgoingAttachment attachment) {
    final c = context.colors;
    return Container(
      width: AppMetric.mediaTile,
      height: AppMetric.mediaTile,
      color: c.searchFill,
      alignment: Alignment.center,
      child: AppIcon(switch (attachment.kind) {
        OutgoingAttachmentKind.photo => HeroAppIcons.image,
        OutgoingAttachmentKind.video ||
        OutgoingAttachmentKind.animation => HeroAppIcons.video,
        OutgoingAttachmentKind.document => HeroAppIcons.file,
        OutgoingAttachmentKind.audio => HeroAppIcons.music,
        OutgoingAttachmentKind.voiceNote => HeroAppIcons.microphone,
      }, color: c.textTertiary),
    );
  }

  Widget _addImageTile() {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _pickImages,
      child: Container(
        width: AppMetric.mediaTile,
        height: AppMetric.mediaTile,
        decoration: BoxDecoration(
          color: c.searchFill,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon(
              HeroAppIcons.image,
              size: AppIconSize.add,
              color: c.textTertiary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              AppStringKeys.richTextComposerPhotoVideo.l10n(context),
              style: AppTextStyle.footnote(c.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _markdownToolbar() {
    final c = context.colors;
    return Row(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(_openRichTextComposer()),
          child: Container(
            height: AppMetric.composerFormatButtonHeight,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.searchFill,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  HeroAppIcons.penToSquare,
                  size: AppIconSize.sm,
                  color: c.textSecondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  AppStringKeys.composerRichText.l10n(context),
                  style: AppTextStyle.body(
                    c.textPrimary,
                    weight: AppTextWeight.semibold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        Text(
          AppStringKeys.markdownLabel.l10n(context),
          style: AppTextStyle.caption(c.textTertiary),
        ),
      ],
    );
  }

  Future<void> _openRichTextComposer() async {
    final result = await showRichTextComposerSheet(
      context,
      initialText: _controller.text,
      title: AppStringKeys.momentsCreatePostTitle,
      submitText: AppStringKeys.addMembersDone,
      hintText: AppStringKeys.momentsShareSomethingPlaceholder,
      initialAttachments: _attachments,
    );
    if (result == null || !mounted) return;
    setState(() {
      _controller.text = result.text;
      _richTextPayload = result.formattedText;
      _attachments
        ..clear()
        ..addAll(result.attachments);
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    });
  }

  Widget _publishSettingsCard() {
    final c = context.colors;
    return SettingsCard(
      children: [
        SettingsRow(
          leading: AppIcon(
            HeroAppIcons.paperPlane,
            size: AppIconSize.nav,
            color: c.textPrimary,
          ),
          title: AppStringKeys.momentsPublishTo,
          value: _channel?.title ?? AppStringKeys.momentsSelectChannel,
          onTap: _selectChannel,
          leadingInset: AppSpacing.xxl + AppSpacing.xxs,
          height: AppMetric.settingsRowHeight - AppSpacing.xxs,
        ),
        const InsetDivider(leadingInset: AppMetric.settingsIconDividerInset),
        SettingsSwitchRow(
          leading: AppIcon(
            HeroAppIcons.bell,
            size: AppIconSize.nav,
            color: c.textPrimary,
          ),
          title: AppStringKeys.momentsNotifySubscribers,
          value: _notifySubscribers,
          onChanged: (value) => setState(() => _notifySubscribers = value),
          leadingInset: AppSpacing.xxl + AppSpacing.xxs,
          height: AppMetric.settingsRowHeight - AppSpacing.xxs,
        ),
      ],
    );
  }

  bool get _canSend =>
      _channel != null &&
      (_controller.text.trim().isNotEmpty || _attachments.isNotEmpty);

  Future<void> _pickImages() async {
    try {
      final remaining = 10 - _attachments.length;
      final images = await AppAssetPicker.pick(
        context,
        type: AppAssetPickerType.image,
        maxAssets: remaining,
      );
      if (images.isEmpty || !mounted) return;
      setState(() {
        _attachments.addAll(
          images.map(
            (image) => OutgoingAttachment(
              path: image.path,
              kind: OutgoingAttachmentKind.photo,
            ),
          ),
        );
      });
    } catch (_) {
      if (mounted) showToast(context, AppStringKeys.momentsPickPhotoFailed);
    }
  }

  Future<void> _selectChannel() async {
    if (widget.channels.isEmpty) {
      showToast(context, AppStringKeys.momentsNoPostableChannels);
      return;
    }
    final selected = await showAppModalSheet<ChatSummary>(
      context: context,
      backgroundColor: context.colors.background,
      builder: (context) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: widget.channels.length,
          separatorBuilder: (_, _) => const InsetDivider(leadingInset: 66),
          itemBuilder: (context, index) {
            final channel = widget.channels[index];
            final selected = channel.id == _channel?.id;
            final c = context.colors;
            return ListTile(
              leading: PhotoAvatar(
                title: channel.title,
                photo: channel.photo,
                size: 38,
                square: true,
              ),
              title: Text(
                channel.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, color: c.textPrimary),
              ),
              trailing: selected
                  ? AppIcon(HeroAppIcons.circleCheck, color: AppTheme.brand)
                  : null,
              onTap: () => Navigator.of(context).pop(channel),
            );
          },
        ),
      ),
    );
    if (selected != null && mounted) setState(() => _channel = selected);
  }

  Future<void> _send() async {
    final channel = _channel;
    final text = _controller.text.trim();
    if (channel == null || (text.isEmpty && _attachments.isEmpty) || _sending) {
      return;
    }
    setState(() => _sending = true);
    // Read the switch before any await: 盘古之白 applies to whatever this
    // composer posts, body and captions alike.
    final spaceOutgoing = context.read<ThemeController>().panguOnSend;
    try {
      final parsed = _richTextPayload?.text.trim() == text
          ? _richTextPayload!
          : await parseTelegramMarkdownWithTdLib(
              text,
              query: TdClient.shared.query,
            );
      // Spacing lands after Markdown parsing, so the entity offsets TDLib
      // produced stay valid for the text that goes out.
      final spaced = PanguSpacing.gated(
        enabled: spaceOutgoing,
        text: parsed.text,
        entities: parsed.entities,
      );
      final formatted = FormattedTextPayload(spaced.text, spaced.entities);
      if (_attachments.isEmpty) {
        await _sendTextPost(channel, formatted);
      } else {
        final requests = buildAttachmentSendRequests(
          chatId: channel.id,
          attachments: _attachments,
          caption: formatted.text,
          captionEntities: formatted.entities,
        );
        for (final request in requests) {
          request['options'] = {
            '@type': 'messageSendOptions',
            'disable_notification': !_notifySubscribers,
          };
          await TdClient.shared.query(request);
        }
      }
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.momentsPostedTo, {'value1': channel.title}),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.momentsPostFailed, {'value1': e}),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendTextPost(
    ChatSummary channel,
    FormattedTextPayload formatted,
  ) {
    return TdClient.shared.query({
      '@type': 'sendMessage',
      'chat_id': channel.id,
      'options': {
        '@type': 'messageSendOptions',
        'disable_notification': !_notifySubscribers,
      },
      'input_message_content': {
        '@type': 'inputMessageText',
        'text': formatted.toTdJson(),
      },
    });
  }
}
