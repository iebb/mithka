part of 'chat_view.dart';

extension _ChatViewActions on _ChatViewState {
  void _enterSelection(ChatMessage message) {
    _updateState(() {
      _actionTarget = null;
      _actionRect = null;
      // Multi-select replaces the HUD outright; there is no exit to replay.
      _actionOverlaySnapshot = null;
      _clearMobileTextSelectionState();
      _actionSource = MessageActionSource.normal;
      _reactionExpanded = false;
      _selectionAnchorId = message.id;
      _selectedMessageIds
        ..clear()
        ..add(message.id);
      _selectionScrollingUp = false;
    });
  }

  void _exitSelection() {
    _updateState(() {
      _selectionAnchorId = null;
      _selectedMessageIds.clear();
    });
  }

  void _toggleSelection(Iterable<ChatMessage> messages) {
    final ids = messages.where((m) => !m.isService).map((m) => m.id).toList();
    if (ids.isEmpty) return;
    _updateState(() {
      final allSelected = ids.every(_selectedMessageIds.contains);
      if (allSelected) {
        _selectedMessageIds.removeAll(ids);
      } else {
        _selectedMessageIds.addAll(ids);
      }
      if (_selectedMessageIds.isEmpty) _selectionAnchorId = null;
    });
  }

  List<int> _orderedSelectedIds() => _vm.messages
      .where((m) => _selectedMessageIds.contains(m.id))
      .map((m) => m.id)
      .toList();

  int _approxVisibleMessageIndex({required bool topEdge}) {
    if (!_scroll.hasClients || _vm.messages.isEmpty) return 0;
    final pos = _scroll.position;
    final viewportContext = _transcriptViewportKey.currentContext;
    final viewportRenderObject = viewportContext?.findRenderObject();
    if (viewportRenderObject is RenderBox && viewportRenderObject.attached) {
      // Viewport-local coordinates keep the transform walk off the ancestor
      // chain above the scrollable.
      final viewportBottom = viewportRenderObject.size.height;
      var bestDistance = double.infinity;
      int? bestIndex;
      for (final trackedEntry in _mountedTranscriptEntries.entries) {
        final itemRenderObject = trackedEntry.value;
        if (!itemRenderObject.attached) {
          continue;
        }
        final itemTop = itemRenderObject
            .localToGlobal(Offset.zero, ancestor: viewportRenderObject)
            .dy;
        final itemBottom = itemTop + itemRenderObject.size.height;
        if (itemBottom <= 0 || itemTop >= viewportBottom) continue;
        final distance = topEdge
            ? (itemTop <= 0 ? 0.0 : itemTop)
            : (itemBottom >= viewportBottom
                  ? 0.0
                  : viewportBottom - itemBottom);
        if (distance >= bestDistance) continue;
        bestDistance = distance;
        final entry = _trackedTranscriptEntries[trackedEntry.key];
        if (entry == null) continue;
        bestIndex = topEdge
            ? entry.startIndex
            : entry.startIndex + entry.messages.length - 1;
      }
      if (bestIndex != null) {
        return bestIndex.clamp(0, _vm.messages.length - 1);
      }
    }

    final viewport = math.max(pos.viewportDimension, 1.0);
    final edgeOffset = topEdge ? pos.pixels : pos.pixels + viewport;
    final frac = scrollFraction(pos, offset: edgeOffset);
    return (frac * (_vm.messages.length - 1)).round().clamp(
      0,
      _vm.messages.length - 1,
    );
  }

  void _selectToVisibleEdge() {
    final anchorId = _selectionAnchorId;
    if (anchorId == null || _vm.messages.isEmpty) return;
    final anchorIndex = _vm.messages.indexWhere((m) => m.id == anchorId);
    if (anchorIndex < 0) return;
    final edgeIndex = _approxVisibleMessageIndex(
      topEdge: _selectionScrollingUp,
    );
    final start = math.min(anchorIndex, edgeIndex);
    final end = math.max(anchorIndex, edgeIndex);
    _updateState(() {
      for (final message in _vm.messages.getRange(start, end + 1)) {
        if (!message.isService) _selectedMessageIds.add(message.id);
      }
    });
  }

  ForwardMarkdownOffer _forwardMarkdownOffer(List<int> messageIds) {
    // Both gates are client-side: the re-send is a normal sendMessage, the
    // server never sees a "rich text forward" mode. The settings toggle keeps
    // detection opt-in; Premium is required by product decision, and the
    // cached AccountStore flag is authoritative enough for hiding a chip.
    final theme = context.read<ThemeController>();
    if (!theme.forwardRichMarkdown) return const ForwardMarkdownOffer.none();
    if (!(context.read<AccountStore?>()?.activeIsPremium ?? false)) {
      return const ForwardMarkdownOffer.none();
    }
    var available = false;
    final byId = {for (final message in _vm.messages) message.id: message};
    for (final id in messageIds) {
      final message = byId[id];
      if (message == null) continue;
      // Detection is heuristic and must never break forwarding: any parse or
      // match failure degrades to "no offer", leaving a regular forward.
      final offer = forwardMarkdownOfferForMessage(message);
      if (offer.suggested) return offer;
      if (offer.available) available = true;
    }
    return ForwardMarkdownOffer(available: available, suggested: false);
  }

  Future<void> _forwardSelected() async {
    final ids = _orderedSelectedIds();
    if (ids.isEmpty) return;
    if (!_vm.canForwardContent && !_protectedCopyEnabled) {
      _showForwardFailure(const ForwardBlockedException());
      return;
    }
    final byId = {for (final message in _vm.messages) message.id: message};
    final messages = [
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
    await _openForwardPicker(
      messages: messages,
      protectedCopy: _protectedCopyEnabled,
    );
  }

  Future<void> _saveSelected() async {
    final ids = _orderedSelectedIds();
    if (ids.isEmpty) return;
    if (!_vm.canForwardContent) {
      _showForwardFailure(const ForwardBlockedException());
      return;
    }
    try {
      await _vm.saveToFavoritesMany(ids);
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.chatMessagesSavedCount, {
          'value1': ids.length,
        }),
      );
      _exitSelection();
    } catch (e) {
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.chatSaveFailed, {'value1': e}),
      );
    }
  }

  Future<void> _deleteSelected() async {
    final ids = _orderedSelectedIds();
    if (ids.isEmpty) return;
    final confirmed = await confirmDialog(
      context,
      title: AppStringKeys.chatDeleteMessagesQuestion,
      message: AppStrings.t(
        AppStringKeys.chatDeleteSelectedMessagesConfirmation,
        {'value1': ids.length},
      ),
      confirmText: AppStringKeys.chatDelete,
      destructive: true,
    );
    if (!mounted || !confirmed) return;
    try {
      await _vm.deleteMessages(ids);
      if (mounted) _exitSelection();
    } catch (e) {
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.chatDeleteActionsFailed, {'value1': e}),
      );
    }
  }

  void _onWallpaperChanged() {
    if (mounted) _updateState(() {});
  }

  Future<void> _votePoll(ChatMessage message, int optionIndex) async {
    try {
      await _vm.votePoll(message, optionIndex);
    } catch (_) {
      if (mounted) {
        showToast(context, AppStringKeys.topicPostContentActionFailed);
      }
    }
  }

  Future<void> _transcribeVoice(ChatMessage message) async {
    try {
      await _vm.recognizeSpeech(message);
    } catch (_) {
      if (mounted) {
        showToast(context, AppStringKeys.topicPostContentActionFailed);
      }
    }
  }

  Future<void> _summarizeMessage(ChatMessage message) async {
    try {
      await _vm.summarizeMessage(message);
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    }
  }

  Future<void> _stopPoll(ChatMessage message) async {
    final confirmed = await confirmDialog(
      context,
      title: AppStringKeys.messagePollStop,
      message: AppStringKeys.messagePollStopConfirm,
      confirmText: AppStringKeys.messagePollStop,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await _vm.stopPoll(message);
    } catch (_) {
      if (mounted) {
        showToast(context, AppStringKeys.topicPostContentActionFailed);
      }
    }
  }

  Future<void> _addPollOption(ChatMessage message) async {
    final value = await _promptChecklistTask(
      title: AppStrings.t(AppStringKeys.chatAddPollOption),
      hint: AppStrings.t(AppStringKeys.chatAddPollOptionHint),
    );
    if (value == null || value.trim().isEmpty || !mounted) return;
    try {
      await _vm.addPollOption(message, value);
    } catch (_) {
      if (mounted) {
        showToast(context, AppStringKeys.topicPostContentActionFailed);
      }
    }
  }

  void _showPollResults(ChatMessage message) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PollResultsView(chatId: _vm.chatId, message: message),
      ),
    );
  }

  Future<void> _toggleChecklistTask(
    ChatMessage message,
    MessageChecklistTask task,
  ) async {
    try {
      await _vm.toggleChecklistTask(message, task);
    } catch (_) {
      if (mounted) {
        showToast(context, AppStringKeys.topicPostContentActionFailed);
      }
    }
  }

  Future<void> _addChecklistTask(ChatMessage message) async {
    final value = await _promptChecklistTask();
    if (value == null || value.trim().isEmpty || !mounted) return;
    try {
      await _vm.addChecklistTask(message, value);
    } catch (_) {
      if (mounted) {
        showToast(context, AppStringKeys.topicPostContentActionFailed);
      }
    }
  }

  Future<String?> _promptChecklistTask({String? title, String? hint}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final c = context.colors;
          final canSubmit = controller.text.trim().isNotEmpty;
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 28),
            child: Container(
              width: 360,
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title ??
                        AppStringKeys.messageChecklistNewTask.l10n(context),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 13),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    maxLength: 128,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      hintText:
                          hint ??
                          AppStringKeys.messageChecklistTaskHint.l10n(context),
                      filled: true,
                      fillColor: c.searchFill,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _ChecklistDialogButton(
                        label: AppStringKeys.countryPickerCancel,
                        foreground: c.textSecondary,
                        onTap: () => Navigator.of(dialogContext).pop(),
                      ),
                      const SizedBox(width: 8),
                      _ChecklistDialogButton(
                        label: AppStringKeys.messageChecklistAdd,
                        foreground: c.onAccent,
                        fill: canSubmit ? AppTheme.brand : c.divider,
                        onTap: canSubmit
                            ? () => Navigator.of(
                                dialogContext,
                              ).pop(controller.text.trim())
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _openSharedContact(ChatMessage message) async {
    final contact = message.contact;
    if (contact == null) return;
    final action = await showSharedContactActions(
      context,
      contact,
      showCallAction: Theme.of(context).platform != TargetPlatform.macOS,
    );
    if (action == null || !mounted) return;
    switch (action) {
      case SharedContactAction.viewProfile:
        if (contact.userId > 0) {
          _openUserProfile(contact.userId, contact.displayName);
        }
      case SharedContactAction.message:
        if (contact.userId <= 0) return;
        try {
          final chat = await TdClient.shared.query({
            '@type': 'createPrivateChat',
            'user_id': contact.userId,
            'force': false,
          });
          final chatId = chat.int64('id');
          if (!mounted || chatId == null) return;
          await openChatFromCurrentWindow(
            context,
            chatId: chatId,
            title: contact.displayName,
          );
        } catch (_) {
          if (mounted) {
            showToast(context, AppStringKeys.topicPostContentActionFailed);
          }
        }
      case SharedContactAction.call:
        if (contact.userId > 0) {
          final started = context.read<CallManager>().startCall(
            contact.userId,
            false,
          );
          if (started != CallStartResult.started && mounted) {
            showToast(
              context,
              started == CallStartResult.unsupported
                  ? AppStringKeys.callsUnavailableOnDesktop
                  : AppStringKeys.callAlreadyInProgress,
            );
          }
        }
      case SharedContactAction.copyNumber:
        await Clipboard.setData(ClipboardData(text: contact.phoneNumber));
        if (mounted) showToast(context, AppStringKeys.topicPostContentCopied);
      case SharedContactAction.addContact:
        try {
          await TdClient.shared.query({
            '@type': 'addContact',
            'contact': {
              '@type': 'contact',
              'phone_number': contact.phoneNumber,
              'first_name': contact.firstName,
              'last_name': contact.lastName,
              'vcard': contact.vcard,
              'user_id': contact.userId,
            },
            'share_phone_number': false,
          });
          if (mounted) showToast(context, AppStringKeys.sharedContactAdded);
        } catch (_) {
          if (mounted) showToast(context, AppStringKeys.sharedContactAddFailed);
        }
    }
  }

  void _openSharedStory(ChatMessage message) {
    final story = message.story;
    if (story == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => StoryViewerView(
          chatId: story.posterChatId,
          storyIds: [story.storyId],
        ),
      ),
    );
  }

  bool _needsSeparator(int index, {List<ChatMessage>? messages}) {
    messages ??= _vm.messages;
    if (index < 0 || index >= messages.length) return false;
    if (index == 0) return true;
    return messages[index].date - messages[index - 1].date >
        _ChatViewState._separatorGap;
  }

  int? _topicSectionId(ChatMessage message) =>
      message.forumTopicId ?? (_vm.isForum ? generalForumTopicId : null);

  /// the message attributable either way.
  ({String name, int iconCustomEmojiId, int iconColor, bool isGeneral})
  _topicSectionDisplay(int topicId) {
    final isGeneral = topicId == generalForumTopicId;
    final topic = _topicById(topicId);
    if (topic != null) {
      return (
        name: topic.name,
        iconCustomEmojiId: topic.iconCustomEmojiId,
        iconColor: topic.iconColor,
        isGeneral: isGeneral,
      );
    }
    final indexed = ForumTopicIndex.shared.entryFor(
      _sessionKey.accountSlot,
      widget.chatId,
      topicId,
    );
    if (indexed != null) {
      return (
        name: indexed.name,
        iconCustomEmojiId: indexed.iconCustomEmojiId,
        iconColor: indexed.iconColor,
        isGeneral: isGeneral,
      );
    }
    return (
      name: isGeneral
          ? AppStringKeys.generalTitle.l10n(context)
          : AppStringKeys.topicChatTopicTitle.l10n(context),
      iconCustomEmojiId: 0,
      iconColor: 0,
      isGeneral: isGeneral,
    );
  }

  bool _needsTopicSeparator(int index, {List<ChatMessage>? messages}) {
    if (!_showsForumTopicSections) return false;
    messages ??= _vm.messages;
    if (index < 0 || index >= messages.length) return false;
    final message = messages[index];
    if (message.isService) return false;
    final sectionId = _topicSectionId(message);
    if (sectionId == null) return false;
    var previous = index - 1;
    while (previous >= 0 &&
        (messages[previous].isService ||
            _topicSectionId(messages[previous]) == null)) {
      previous--;
    }
    if (previous < 0) return true;
    return sectionId != _topicSectionId(messages[previous]);
  }

  bool _isRepeatTail(int index) {
    final messages = _vm.messages;
    if (index != messages.length - 1 || index == 0) return false;
    final a = messages[index], b = messages[index - 1];
    if (a.isService || b.isService) return false;
    // 复读 (+1) only echoes identical plain-text OR identical photos. Audio,
    // voice, location, stickers, polls, files, videos, contacts and call logs
    // are never repeatable — even when their placeholder text happens to match.
    if (a.isPlainText && b.isPlainText) {
      final ta = a.text.trim(), tb = b.text.trim();
      return ta.isNotEmpty && ta == tb;
    }
    if (a.isPhoto && b.isPhoto) {
      return a.image != null && b.image != null && a.image!.id == b.image!.id;
    }
    return false;
  }

  void _playVideo(ChatMessage message, {bool muted = false}) {
    if (message.video == null) return;
    final session = _videoSession(message);
    if (supportsDesktopVideoWindows) {
      unawaited(_openDesktopVideoWindow(session, muted: muted));
      return;
    }
    if (VideoSplitController.instance.isOpen) {
      VideoSplitController.instance.play(session);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (routeContext) => VideoOnDemandPlayerView(
          queue: session.queue,
          initialMuted: muted,
          onSwitchMode: (queue, mode) =>
              _switchVideoMode(routeContext, queue, mode),
        ),
      ),
    );
  }

  Future<void> _openDesktopVideoWindow(
    VideoSplitSession session, {
    required bool muted,
  }) async {
    final opened = await DesktopVideoWindowService.instance.open(
      session,
      muted: muted,
    );
    if (!opened && mounted) {
      showToast(context, AppStringKeys.videoPlayerLoadFailed);
    }
  }

  VideoSplitSession _videoSession(ChatMessage message) {
    final videoMessages = _vm.messages
        .where(
          (candidate) =>
              candidate.video != null &&
              canPreviewMediaAlongside(candidate, message),
        )
        .toList();
    if (!videoMessages.any((candidate) => candidate.id == message.id)) {
      videoMessages.add(message);
    }
    final items = [
      for (final candidate in videoMessages)
        VideoPlaybackItem(
          video: candidate.video!,
          accountSlot: _sessionKey.accountSlot,
          thumb: candidate.image,
          width: candidate.imageWidth,
          height: candidate.imageHeight,
          durationSeconds: candidate.videoDuration,
          sourceChatId: widget.chatId,
          messageId: candidate.id,
          title: _videoPlaybackTitle(candidate),
        ),
    ];
    final index = videoMessages.indexWhere(
      (candidate) => candidate.id == message.id,
    );
    return VideoSplitSession.fromQueue(
      VideoPlaybackQueue(items: items, index: index < 0 ? 0 : index),
    );
  }

  String _videoPlaybackTitle(ChatMessage message) {
    final text = message.text.trim().replaceAll('\n', ' ');
    if (text.isEmpty || (text.startsWith('[') && text.endsWith(']'))) {
      return widget.title;
    }
    return text;
  }

  void _switchVideoMode(
    BuildContext routeContext,
    VideoPlaybackQueue queue,
    VideoDisplayMode mode,
  ) {
    final session = VideoSplitSession.fromQueue(queue);
    switch (mode) {
      case VideoDisplayMode.fullscreen:
        break;
      case VideoDisplayMode.pictureInPicture:
        // iOS has already handed the player to AVPictureInPictureController.
        // There is no app-level PiP overlay fallback.
        Navigator.of(routeContext).maybePop();
      case VideoDisplayMode.split:
        VideoSplitController.instance.play(session);
        Navigator.of(routeContext).maybePop();
    }
  }

  ImageViewerMessageActions? _imageMessageActions(List<ChatMessage> pairs) {
    return ImageViewerMessageActions(
      messageIds: [for (final m in pairs) m.id],
      onViewInChat: (messageId) async => _jumpToMessage(messageId),
      onReply: (messageId) async => _jumpToMessage(messageId, reply: true),
    );
  }

  Future<void> _jumpToMessage(int messageId, {bool reply = false}) async {
    if (!mounted) return;
    _captureJumpOrigin();
    _updateState(() => _setScrollTarget(messageId, forceNavigation: true));
    if (!reply) return;
    final target = _vm.messages.where((m) => m.id == messageId).firstOrNull;
    if (target != null) _vm.setReply(target);
  }

  void _openImage(ChatMessage message) {
    final selected = message.image;
    final pairs = _vm.messages
        .where(
          (m) =>
              m.isPhoto &&
              m.image != null &&
              canPreviewMediaAlongside(m, message),
        )
        .toList();
    var start = pairs.indexWhere((m) => m.id == message.id);
    if (start < 0 && selected != null) {
      // The tapped photo is not a transcript photo message — e.g. a lone
      // photo block inside a rich message hands over a synthetic message
      // whose id matches the rich message instead. Dropping it here used to
      // fall back to index 0, opening the viewer on an unrelated chat photo
      // while the tapped image was missing from the gallery entirely.
      // Insert it at its id position so the gallery order still reads as
      // chronology, and open on it.
      final insertion = pairs.indexWhere((m) => m.id > message.id);
      start = insertion < 0 ? pairs.length : insertion;
      pairs.insert(start, message);
    }
    final items = pairs.map((m) => m.image!).toList();
    unawaited(
      openImagePreview(
        context,
        items: items,
        startIndex: start < 0 ? 0 : start,
        messageActions: _imageMessageActions(pairs),
        metadata: MediaMetadata.listFor(
          pairs,
          enabled: context.read<ThemeController>().mediaMetadataEnabled,
        ),
      ),
    );
  }

  void _openImageGallery({
    required List<TdFileRef> items,
    required int startIndex,
  }) {
    // The bubble gallery hands over a collage/slideshow's photo list without
    // message ids; those items came from a single message, so anchoring the
    // jump on any of them is meaningless. View in Chat stays hidden.
    unawaited(openImagePreview(context, items: items, startIndex: startIndex));
  }

  void _openSticker(ChatMessage message) {
    final desktop = isDesktopTargetPlatform(Theme.of(context).platform);
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StickerViewer(
          message: message,
          onOpenSet: desktop ? _openStickerSet : null,
        ),
      ),
    );
  }

  void _openStickerSet(int setId) {
    if (isDesktopTargetPlatform(Theme.of(context).platform)) {
      _updateState(() => _desktopStickerSetId = setId);
      return;
    }
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => StickerSetDetailView(setId: setId)),
      ),
    );
  }

  Future<void> _openMessageComments(ChatMessage message) async {
    await showMessageRepliesSheet(
      context: context,
      chatId: widget.chatId,
      message: message,
      peerTitle: _vm.peerTitle,
      onAvatarTap: _openSenderProfile,
      onOpenReply: _openReplyMessage,
      onOpenImage: _openImage,
      onOpenSticker: _openSticker,
      onPlayVideo: _playVideo,
      onPlayMusic: _playMusicMessage,
      onButtonTap: _pressMessageButton,
      onBotCommandTap: _sendCommand,
      onHashtagTap: _openHashtagSearch,
      onViewInChat: _viewMessageRepliesInChat,
    );
  }

  Future<void> _openForwardedMessage(ChatMessage message) async {
    final chatId = message.forwardFromChatId;
    final messageId = message.forwardFromMessageId;
    if (chatId == null || chatId == 0 || messageId == null || messageId <= 0) {
      return;
    }
    if (chatId == widget.chatId) {
      await _scrollToMessage(messageId);
      return;
    }
    if (!mounted) return;
    await openChatFromCurrentWindow(
      context,
      chatId: chatId,
      title: message.forwardDisplayName,
      initialMessageId: messageId,
    );
  }

  Future<void> _viewMessageRepliesInChat(
    MessageRepliesViewTarget target,
  ) async {
    if (target.chatId == widget.chatId) {
      _captureJumpOrigin();
      await _scrollToMessage(target.messageId);
      return;
    }
    if (!mounted) return;
    await openChatFromCurrentWindow(
      context,
      chatId: target.chatId,
      title: target.title,
      initialMessageId: target.messageId,
    );
  }

  Future<void> _openBotMenuApp(BotMenuInfo menu) async {
    final botUserId = _vm.peerUserId;
    if (botUserId == null) {
      if (!menu.isLegacyMenuUrl && menu.webAppUrl.isNotEmpty) {
        await openLink(context, menu.webAppUrl);
      }
      return;
    }
    final opened = await openTelegramMiniApp(
      context,
      chatId: _vm.chatId,
      botUserId: botUserId,
      url: menu.url,
      title: menu.actionTitle,
      menuWebApp: true,
    );
    if (!opened && mounted) {
      showToast(context, AppStrings.t(AppStringKeys.miniAppCannotStart));
    }
  }

  Future<void> _openLinkFromTranscript(BuildContext context, String url) =>
      openLink(context, url, sourceChat: _internalLinkTarget);

  Future<void> _pressMessageButton(
    ChatMessage message,
    MessageButton button,
  ) async {
    final url = button.url;
    if (url != null && url.isNotEmpty) {
      if (button.isWebApp) {
        final botUserId = await _vm.webAppBotUserId(message);
        if (!mounted) return;
        if (botUserId != null) {
          final opened = await openTelegramMiniApp(
            context,
            chatId: _vm.chatId,
            botUserId: botUserId,
            url: url,
            title: button.text,
            keyboardButtonText: button.isReplyKeyboard ? button.text : null,
          );
          if (opened) return;
        }
        if (!mounted) return;
        showToast(context, AppStrings.t(AppStringKeys.miniAppCannotStart));
        return;
      }
      await _openLinkFromTranscript(context, url);
      return;
    }
    final userId = button.userId;
    if (userId != null && userId > 0) {
      await _openLinkFromTranscript(context, 'tg://user?id=$userId');
      return;
    }
    final copyText = button.copyText;
    if (copyText != null && copyText.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: copyText));
      if (mounted) {
        showToast(context, AppStringKeys.topicPostContentCopied);
      }
      return;
    }
    if (button.isCallback) {
      try {
        final answer = await _vm.answerCallbackButton(message.id, button);
        if (!mounted) return;
        final answerUrl = answer.str('url');
        if (answerUrl != null && answerUrl.isNotEmpty) {
          await _openLinkFromTranscript(context, answerUrl);
          return;
        }
        final text = answer.str('text');
        if (text != null && text.isNotEmpty) {
          showToast(context, text);
        }
      } catch (e) {
        if (!mounted) return;
        showToast(context, AppStringKeys.topicPostContentActionFailed);
      }
      return;
    }
    if (button.isReplyKeyboard && button.type == 'keyboardButtonTypeText') {
      _sendKeyboardButtonText(button.text);
      return;
    }
    if (button.isSwitchInline) {
      await _activateSwitchInlineButton(message, button);
      return;
    }
    showToast(context, AppStringKeys.chatButtonUnsupported);
  }

  Future<void> _activateMessageViaBot(ChatMessage message) async {
    final username = await _vm.resolveInlineBotUsername(message);
    if (!mounted) return;
    if (username == null || username.isEmpty) return;
    if (_vm.canSendMessages) {
      _vm.activateInlineQuery(username);
      return;
    }
    await _openLinkFromTranscript(context, 'https://t.me/$username');
  }

  Future<void> _activateSwitchInlineButton(
    ChatMessage message,
    MessageButton button,
  ) async {
    final query = button.switchInlineQuery ?? '';
    final target =
        button.switchInlineTarget ?? const SwitchInlineTarget.chooseChat();
    if (target.kind == SwitchInlineTargetKind.internalLink &&
        target.internalLink != null) {
      final resolvedUsername = await _vm.resolveInlineBotUsername(message);
      if (!mounted) return;
      final link = Map<String, dynamic>.from(target.internalLink!);
      if (resolvedUsername != null &&
          resolvedUsername.isNotEmpty &&
          link.type == 'internalLinkTypePublicChat' &&
          (link.str('draft_text') ?? '').trim().isEmpty) {
        link['draft_text'] = '@$resolvedUsername $query';
      }
      await openInternalLinkType(context, link);
      return;
    }
    final username = await _vm.resolveInlineBotUsername(message);
    if (!mounted) return;
    if (username == null || username.isEmpty) {
      showToast(context, AppStringKeys.topicPostContentActionFailed);
      return;
    }
    if (target.isCurrentChat && _vm.canSendMessages) {
      _vm.activateInlineQuery(username, query);
      return;
    }
    final allowedKinds = target.isCurrentChat
        ? const {
            ChatKind.privateChat,
            ChatKind.bot,
            ChatKind.group,
            ChatKind.channel,
          }
        : target.allowedChatKinds;
    final picked = await Navigator.of(context).push<ChatSummary>(
      MaterialPageRoute(
        builder: (_) => ChatPickerView(
          allowedKinds: allowedKinds,
          allowChannels: allowedKinds.contains(ChatKind.channel),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (picked.id == _vm.chatId && _vm.canSendMessages) {
      _vm.activateInlineQuery(username, query);
      return;
    }
    try {
      await TdClient.shared.query(
        setTextChatDraftRequest(
          chatId: picked.id,
          date: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          formattedText: {
            '@type': 'formattedText',
            'text': '@$username $query',
            'entities': const <Map<String, dynamic>>[],
          },
        ),
      );
    } catch (_) {}
    if (!mounted) return;
    await openChatFromCurrentWindow(
      context,
      chatId: picked.id,
      title: picked.title,
    );
  }

  Future<void> _perform(MessageAction action, ChatMessage message) async {
    final selectedQuote = _actionQuote;
    final canReplyInCurrentChat =
        _vm.canSendMessages && _actionCanReply == true;
    _updateState(() {
      _actionTarget = null;
      _actionQuote = null;
      _actionRect = null;
      _clearMobileTextSelectionState();
      _actionSource = MessageActionSource.normal;
    });
    switch (action) {
      case MessageAction.viewEdits:
        await _openMessageEdits(message);
      case MessageAction.removeMirror:
        _removeMirrorEntry(message);
      case MessageAction.copy:
        unawaited(Clipboard.setData(ClipboardData(text: message.text)));
      case MessageAction.copyImage:
        await _copyMessageImage(message);
      case MessageAction.copyMessageLink:
        await _copyMessageLink(message);
      case MessageAction.edit:
        unawaited(_editMessage(message));
      case MessageAction.suggestOffer:
        unawaited(_offerSuggestedPost(message));
      case MessageAction.translate:
        unawaited(_translateMessage(message));
      case MessageAction.displayOriginal:
        _updateState(() => _showOriginalTranslationMessageIds.add(message.id));
      case MessageAction.displayTranslation:
        _updateState(
          () => _showOriginalTranslationMessageIds.remove(message.id),
        );
      case MessageAction.reply:
        if (_vm.isChannel &&
            _vm.hasLinkedDiscussion &&
            !canReplyInCurrentChat) {
          // A channel composer does not override the message's same-chat
          // reply permission. When either is unavailable, answer in the
          // linked group instead; its sheet applies that group's permissions.
          await _openMessageComments(message);
        } else if (selectedQuote != null && _vm.canQuoteText) {
          await _quoteMessageText(message, selectedQuote: selectedQuote);
        } else {
          _vm.setReply(message);
        }
      case MessageAction.quote:
        await _quoteMessageText(message, selectedQuote: selectedQuote);
      case MessageAction.replies:
        await _openMessageComments(message);
      case MessageAction.forward:
        unawaited(_forwardMessage(message));
      case MessageAction.repeat:
        try {
          // In a protected chat this rides the copy-forward route: a
          // no-quote re-send of the message into the CURRENT chat.
          final preserveSender = context
              .read<ThemeController>()
              .preserveSenderWhenRepeating;
          await _vm.forward(
            message.id,
            _vm.chatId,
            options: ForwardOptions(removeSender: !preserveSender),
          );
          if (!mounted) return;
          _scrollToBottom();
          _showProtectedCopyResult(_vm.protectedForwardLastPlan);
        } catch (e) {
          if (!mounted) return;
          _showForwardFailure(e);
        }
      case MessageAction.report:
        final confirmed = await confirmDialog(
          context,
          title: AppStringKeys.chatReportTitle,
          message: AppStringKeys.chatReportMessage,
          confirmText: AppStringKeys.chatReportConfirm,
          destructive: true,
        );
        if (!mounted || !confirmed) return;
        try {
          await _vm.reportMessage(message);
          if (!mounted) return;
          showToast(context, AppStringKeys.chatReportSent);
        } catch (e) {
          if (!mounted) return;
          showToast(
            context,
            AppStrings.t(AppStringKeys.chatReportFailed, {'value1': e}),
          );
        }
      case MessageAction.hideSender:
        await _hideSender(message);
      case MessageAction.block:
        final confirmed = await confirmDialog(
          context,
          title: AppStringKeys.chatBlockUserTitle,
          message: AppStringKeys.chatBlockUserMessage,
          confirmText: AppStringKeys.chatBlockUserConfirm,
          destructive: true,
        );
        if (!mounted || !confirmed) return;
        try {
          await _vm.blockAndReportSender(message);
          if (!mounted) return;
          showToast(context, AppStringKeys.chatBlockUserDone);
        } catch (e) {
          if (!mounted) return;
          showToast(
            context,
            AppStrings.t(AppStringKeys.chatBlockUserFailed, {'value1': e}),
          );
        }
      case MessageAction.playMuted:
        _playVideo(message, muted: true);
      case MessageAction.addToPlaylist:
        unawaited(showMusicPlaylists(context, addMessage: message));
      case MessageAction.saveAs:
        await _saveMediaToFolder(message);
      case MessageAction.saveToPhotos:
        DateTime? progressShownAt;
        final progressTimer = Timer(const Duration(milliseconds: 500), () {
          if (!mounted) return;
          progressShownAt = DateTime.now();
          showToast(
            context,
            AppStringKeys.chatSavingToPhotos,
            visibleFor: const Duration(milliseconds: 900),
          );
        });
        final result = await MediaLibrarySaver.save(message);
        progressTimer.cancel();
        if (!mounted) return;
        if (progressShownAt case final shownAt?) {
          final remaining =
              const Duration(milliseconds: 1400) -
              DateTime.now().difference(shownAt);
          if (remaining > Duration.zero) await Future<void>.delayed(remaining);
          if (!mounted) return;
        }
        showToast(context, switch (result) {
          MediaLibrarySaveResult.saved => AppStringKeys.chatSavedToPhotos,
          MediaLibrarySaveResult.permissionDenied =>
            AppStringKeys.chatSaveToPhotosPermissionDenied,
          MediaLibrarySaveResult.failed || MediaLibrarySaveResult.unsupported =>
            AppStringKeys.chatSaveToPhotosFailed,
        }, visibleFor: const Duration(seconds: 2));
      case MessageAction.multiSelect:
        _enterSelection(message);
      case MessageAction.pinTodo:
        try {
          await _vm.pinTodo(message);
          if (!mounted) return;
          showToastOverlay(
            Overlay.of(context),
            AppStrings.t(AppStringKeys.chatTodoSetSuccess),
          );
        } catch (e) {
          if (!mounted) return;
          showToast(
            context,
            AppStrings.t(AppStringKeys.chatTodoSetFailed, {'value1': e}),
          );
        }
      case MessageAction.unpinTodo:
        try {
          await _vm.unpinTodo(message);
          if (!mounted) return;
          showToastOverlay(
            Overlay.of(context),
            AppStrings.t(AppStringKeys.chatTodoUnsetSuccess),
          );
        } catch (e) {
          if (!mounted) return;
          showToast(
            context,
            AppStrings.t(AppStringKeys.chatTodoUnsetFailed, {'value1': e}),
          );
        }
      case MessageAction.save:
        try {
          await _vm.saveToFavorites(message.id);
          if (!mounted) return;
          showToast(context, AppStringKeys.chatSavedToSavedMessages);
        } catch (e) {
          if (!mounted) return;
          showToast(
            context,
            AppStrings.t(AppStringKeys.chatSaveFailed, {'value1': e}),
          );
        }
      case MessageAction.saveSticker:
        final id = message.stickerFileId ?? message.animatedSticker?.id;
        if (id != null) {
          _vm.saveFavoriteSticker(id);
          showToast(context, AppStringKeys.chatStickerAddSuccess);
        }
      case MessageAction.viewStickerSet:
        final sid = message.stickerSetId;
        if (sid != null) _openStickerSet(sid);
      case MessageAction.delete:
        await _performDeleteAction(message);
    }
  }

  Future<void> _saveMediaToFolder(ChatMessage message) async {
    final progressTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      showToast(
        context,
        AppStringKeys.chatSavingToPhotos,
        visibleFor: const Duration(milliseconds: 900),
      );
    });
    final outcome = await MediaDownloadService.saveMessageMedia(message);
    progressTimer.cancel();
    if (!mounted) return;
    final feedback = MediaDownloadService.feedbackFor(outcome);
    if (feedback != null) {
      showToast(context, feedback, visibleFor: const Duration(seconds: 2));
    }
  }

  Future<void> _copyMessageImage(ChatMessage message) async {
    final image = message.isPhoto ? message.image : null;
    if (image == null) return;
    try {
      final path = await TdFileCenter.shared.pathFor(
        image,
        accountSlot: _sessionKey.accountSlot,
      );
      final copied =
          path != null &&
          await DesktopClipboardImageService.copyImageFile(File(path));
      if (!copied && mounted) {
        showToast(context, AppStringKeys.messageActionCopyImageFailed);
      }
    } catch (_) {
      if (mounted) {
        showToast(context, AppStringKeys.messageActionCopyImageFailed);
      }
    }
  }

  Future<void> _copyMessageLink(ChatMessage message) async {
    try {
      final link = await _vm.messageLink(message.id);
      if (!mounted) return;
      if (link.isEmpty) {
        showToast(context, AppStringKeys.messageActionCopyLinkFailed);
        return;
      }
      await Clipboard.setData(ClipboardData(text: link));
      if (mounted) showToast(context, AppStringKeys.messageLinkCopied);
    } catch (_) {
      if (mounted) {
        showToast(context, AppStringKeys.messageActionCopyLinkFailed);
      }
    }
  }

  Future<void> _offerSuggestedPost(ChatMessage message) async {
    final loader = ChannelDirectMessageTopicController(
      chatId: _vm.chatId,
      topicId: 0,
    );
    try {
      final properties = await TdClient.shared.query({
        '@type': 'getMessageProperties',
        'chat_id': _vm.chatId,
        'message_id': message.id,
      });
      if (properties.boolean('can_add_offer') != true &&
          properties.boolean('can_edit_suggested_post_info') != true) {
        if (mounted) {
          showToast(context, AppStringKeys.suggestedPostOfferUnavailable);
        }
        return;
      }
      final limits = await loader.loadLimits();
      if (!mounted) return;
      final draft = await showAppModalSheet<SuggestedPostDraft>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => SuggestedPostComposerSheet(
          limits: limits,
          offerOnly: true,
          initialInfo: message.suggestedPostInfo,
        ),
      );
      if (draft == null || !mounted) return;
      await _vm.addSuggestedPostOffer(
        message.id,
        price: draft.price,
        sendDate: draft.sendDate,
      );
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    } finally {
      loader.dispose();
    }
  }

  Future<void> _hideSender(ChatMessage message) async {
    final senderId = message.senderId;
    if (senderId == null) return;
    final name = _deleteSenderName(message);
    final scope = await showHideSenderDialog(context, name: name);
    if (!mounted || scope == null) return;
    final thisGroup = scope == HideSenderScope.thisGroup;
    HiddenSenderStore.shared.hide(
      HiddenSender(
        senderId: senderId,
        name: name,
        chatId: thisGroup ? _vm.chatId : null,
        chatTitle: thisGroup ? _vm.peerTitle : null,
        hiddenAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ),
    );
    showToast(
      context,
      AppStrings.t(AppStringKeys.hideSenderDone, {'value1': name}),
    );
  }

  Future<void> _performDeleteAction(ChatMessage message) async {
    final options = await _confirmMessageDeleteOptions(message);
    if (!mounted || options == null) return;
    try {
      if (options.reportSpam && !options.blockSender) {
        await _vm.reportMessage(message);
      }
      if (options.blockSender) {
        await _vm.blockAndReportSender(message);
      }
      if (options.deleteAllFromSender) {
        await _vm.deleteMessagesFromSender(message);
      } else if (options.deleteMessage) {
        await _vm.deleteMessage(message.id);
      }
      if (!mounted) return;
      showToast(context, AppStringKeys.chatDeleteActionsDone);
    } catch (e) {
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.chatDeleteActionsFailed, {'value1': e}),
      );
    }
  }

  Future<_MessageDeleteOptions?> _confirmMessageDeleteOptions(
    ChatMessage message,
  ) {
    final senderName = _deleteSenderName(message);
    return showGeneralDialog<_MessageDeleteOptions>(
      context: context,
      barrierDismissible: true,
      barrierLabel: AppStrings.t(AppStringKeys.countryPickerCancel),
      barrierColor: Colors.black.withValues(alpha: 0.42),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, _, _) => _MessageDeleteOptionsDialog(
        canActOnSender: !message.isOutgoing && message.senderId != null,
        canDeleteAllFromSender:
            !message.isOutgoing &&
            message.senderId != null &&
            _vm.canDeleteMessagesBySender,
        senderName: senderName,
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  bool _canHideSender(ChatMessage message) {
    final senderId = message.senderId;
    return _vm.isGroup &&
        !_vm.isChannel &&
        !message.isOutgoing &&
        !message.isService &&
        senderId != null &&
        senderId != 0 &&
        senderId != _vm.chatId;
  }

  String _deleteSenderName(ChatMessage message) {
    final name = (message.senderName ?? message.senderTitle ?? '').trim();
    if (name.isNotEmpty) return name;
    return AppStrings.t(AppStringKeys.topicChatUsers);
  }

  bool _isEditableMediaMessage(ChatMessage message) =>
      message.contentType == 'messagePhoto' ||
      message.contentType == 'messageVideo' ||
      message.contentType == 'messageAnimation' ||
      message.contentType == 'messageAudio' ||
      message.contentType == 'messageDocument';

  Future<void> _editMessage(ChatMessage message) async {
    if (message.checklist case final checklist?) {
      final result = await Navigator.of(context).push<ChecklistComposerResult>(
        MaterialPageRoute(
          builder: (_) => ChecklistComposerView(
            initialTitle: checklist.title,
            initialTasks: [for (final task in checklist.tasks) task.text],
            initialOthersCanAddTasks: checklist.othersCanAddTasks,
            initialOthersCanMarkTasksAsDone: checklist.othersCanMarkTasksAsDone,
          ),
        ),
      );
      if (!mounted || result == null) return;
      try {
        await _vm.editChecklist(message, result);
      } catch (error) {
        if (mounted) showToast(context, error.toString());
      }
      return;
    }
    if (_isEditableMediaMessage(message)) {
      final action = await showGeneralDialog<_MediaEditAction>(
        context: context,
        barrierDismissible: true,
        barrierLabel: AppStringKeys.countryPickerCancel.l10n(context),
        barrierColor: Colors.black.withValues(alpha: 0.38),
        transitionDuration: const Duration(milliseconds: 170),
        pageBuilder: (_, _, _) =>
            _MediaEditActionDialog(mediaLabel: _mediaLabel(message)),
      );
      if (!mounted || action == null) return;
      switch (action) {
        case _MediaEditAction.edit:
          await _editMessageText(message);
        case _MediaEditAction.replace:
          await _replaceMessageMedia(message);
        case _MediaEditAction.delete:
          await _deleteMessageMedia(message);
      }
      return;
    }
    await _editMessageText(message);
  }

  Future<void> _editMessageText(ChatMessage message) {
    _vm.beginMessageEdit(message);
    return Future.value();
  }

  Future<void> _replaceMessageMedia(ChatMessage message) async {
    OutgoingAttachment? replacement;
    if (message.contentType == 'messagePhoto' ||
        message.contentType == 'messageVideo' ||
        message.contentType == 'messageAnimation') {
      final selection = await AppAssetPicker.pickDetailed(
        context,
        type: AppAssetPickerType.imageAndVideo,
        maxAssets: 1,
      );
      if (!mounted || selection.assets.isEmpty) return;
      final asset = selection.assets.first;
      final file = asset.file;
      final kind = isPickedAssetVideo(file)
          ? OutgoingAttachmentKind.video
          : isPickedAssetGif(file)
          ? OutgoingAttachmentKind.animation
          : OutgoingAttachmentKind.photo;
      replacement = OutgoingAttachment(
        path: file.path,
        kind: kind,
        previewBytes: asset.thumbnailBytes,
        width: asset.width,
        height: asset.height,
      );
    } else {
      final picked = await FilePicker.platform.pickFiles(
        type: message.contentType == 'messageAudio'
            ? FileType.audio
            : FileType.any,
      );
      final path = picked?.files.single.path;
      if (!mounted || path == null) return;
      replacement = OutgoingAttachment(
        path: path,
        kind: message.contentType == 'messageAudio'
            ? OutgoingAttachmentKind.audio
            : OutgoingAttachmentKind.document,
      );
    }
    try {
      await _vm.editMessageMedia(
        message.id,
        replacement,
        caption: _editableMessageText(message),
        entities: [
          for (final entity in message.textEntities) entity.toTdJson(),
        ],
      );
    } catch (e) {
      if (mounted) showToast(context, '$e');
    }
  }

  Future<void> _deleteMessageMedia(ChatMessage message) async {
    final confirmed = await confirmDialog(
      context,
      title: AppStringKeys.chatDeleteSingleMessageQuestion,
      confirmText: AppStringKeys.chatDelete,
      destructive: true,
    );
    if (!mounted || !confirmed) return;
    try {
      await _vm.deleteMessage(message.id);
    } catch (e) {
      if (mounted) showToast(context, '$e');
    }
  }

  String _editableMessageText(ChatMessage message) {
    return message.text.trim().isEmpty ? '' : message.text;
  }

  String _mediaLabel(ChatMessage message) => switch (message.contentType) {
    'messagePhoto' => AppStrings.t(AppStringKeys.composerImagePreview),
    'messageVideo' => AppStrings.t(AppStringKeys.chatVideoPlaceholder),
    'messageAnimation' => AppStrings.t(AppStringKeys.tdMessageGif),
    'messageAudio' => AppStrings.t(AppStringKeys.tdMessageMusic),
    _ => AppStrings.t(AppStringKeys.topicPostContentFile),
  };

  void _openSenderProfile(ChatMessage m) {
    if (m.senderIsChat) {
      final senderChatId = m.senderId;
      if (senderChatId == null) return;
      final senderTitle = (m.senderName ?? m.senderTitle ?? _vm.peerTitle)
          .trim();
      final title = senderTitle.isEmpty ? _vm.peerTitle : senderTitle;
      if (senderChatId == widget.chatId) {
        unawaited(_openChatInfo(title: title, useAppPageRoute: true));
        return;
      }
      unawaited(
        openChatFromCurrentWindow(context, chatId: senderChatId, title: title),
      );
      return;
    }
    final uid = m.isOutgoing
        ? _vm.meId
        : (_vm.isGroup ? m.senderId : _vm.peerUserId);
    if (uid == null || uid <= 0) return;
    _openUserProfile(
      uid,
      m.isOutgoing ? _vm.meName : (m.senderName ?? _vm.peerTitle),
    );
  }

  Future<void> _openChatInfo({
    String? title,
    bool useAppPageRoute = false,
  }) async {
    final chatTitle = title ?? _vm.peerTitle;
    // The §1.4 mirror rows act on the OWNING transcript's account, not the
    // store's active one: a stale pane after an account switch must never
    // exclude the other account's chat.
    final accountUserId = allowTelegramTosViolations
        ? _vm.mirrorAccountUserId
        : null;
    final Route<int> route = useAppPageRoute
        ? AppPageRoute<int>(
            pageBuilder: (_, _, _) => ChatInfoView(
              chatId: widget.chatId,
              title: chatTitle,
              accountUserId: accountUserId,
            ),
          )
        : MaterialPageRoute<int>(
            builder: (_) => ChatInfoView(
              chatId: widget.chatId,
              title: chatTitle,
              accountUserId: accountUserId,
            ),
          );
    final messageId = await Navigator.of(context).push<int>(route);
    if (!mounted || messageId == null) return;
    await _scrollToMessage(messageId);
  }

  void _handleInfoPressed() {
    final onInfoPressed = widget.onInfoPressed;
    if (onInfoPressed != null) {
      onInfoPressed();
      return;
    }
    unawaited(_openChatInfo());
  }

  void _handleFullInfoPressed() {
    final onOpenFullInfo = widget.onOpenFullInfo;
    if (onOpenFullInfo != null) {
      onOpenFullInfo();
      return;
    }
    unawaited(_openChatInfo());
  }

  void _openPeerProfile() {
    final uid = _vm.peerUserId;
    if (uid == null || uid <= 0) return;
    _openUserProfile(uid, _vm.peerTitle);
  }

  void _openUserProfile(int userId, String name) {
    final onOpenUserProfile = widget.onOpenUserProfile;
    if (onOpenUserProfile != null) {
      onOpenUserProfile(userId, name);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileDetailView(userId: userId, name: name),
      ),
    );
  }

  Future<void> _startCall(bool isVideo) async {
    if (_vm.isGroup) {
      try {
        await context.read<CallManager>().startGroupCall(
          chatId: _vm.chatId,
          title: _vm.peerTitle,
          isVideo: isVideo,
        );
      } catch (error) {
        if (!mounted) return;
        showToast(context, error.toString());
      }
      return;
    }
    final uid = _vm.peerUserId;
    if (uid == null) {
      showToast(context, AppStringKeys.chatContactCallsOnly);
      return;
    }
    final started = context.read<CallManager>().startCall(uid, isVideo);
    if (started != CallStartResult.started && mounted) {
      showToast(
        context,
        started == CallStartResult.unsupported
            ? AppStringKeys.callsUnavailableOnDesktop
            : AppStringKeys.callAlreadyInProgress,
      );
    }
  }

  List<ChatMessage> _messagesForForward(ChatMessage message) {
    if (message.mediaAlbumId == 0 ||
        !context.read<ThemeController>().groupImageMessages) {
      return [message];
    }
    for (final entry in _transcriptEntries(true)) {
      if (entry.isImageGroup &&
          entry.messages.any((candidate) => candidate.id == message.id)) {
        return entry.messages;
      }
    }
    return [message];
  }

  Future<void> _forwardMessage(ChatMessage message) async {
    if (!_vm.canForwardContent && !_protectedCopyEnabled) {
      _showForwardFailure(const ForwardBlockedException());
      return;
    }
    final messages = _messagesForForward(message);
    await _openForwardPicker(
      messages: messages,
      protectedCopy: _protectedCopyEnabled,
    );
  }

  void _showForwardFailure(Object error) {
    showToast(
      context,
      isForwardProtectedError(error)
          ? AppStringKeys.chatForwardProtected
          : AppStrings.t(AppStringKeys.chatForwardFailed, {'value1': error}),
    );
  }

  ChatWallpaper? _effectiveWallpaper() {
    if (!_themingEnabled) return null;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final chatWallpaper = _wallpaperController.wallpaperFor(
      widget.chatId,
      dark: dark,
    );
    if (chatWallpaper != null) return chatWallpaper;
    final defaultWallpaper = _wallpaperController.defaultWallpaper(dark: dark);
    if (defaultWallpaper != null) {
      return _wallpaperController.resolvedWallpaper(defaultWallpaper);
    }
    final globalChatWallpaper = _wallpaperController.globalThemeWallpaperFor(
      dark: dark,
    );
    final cloudWallpaper = _resolvedCloudTheme?.wallpaper;
    if (cloudWallpaper != null) {
      return _wallpaperController.resolvedWallpaper(cloudWallpaper);
    }
    return globalChatWallpaper == null
        ? null
        : _wallpaperController.resolvedWallpaper(globalChatWallpaper);
  }

  /// Markdown detection over the messages about to be forwarded: the picker

  /// offers the render option when any message carries convertible markers and

  /// pre-checks it when at least one looks like authored Markdown.

  /// Protected-source forwarding entry. When the kept-messages toggle is on,

  /// the regular flow runs and ChatViewModel.forwardMany internally re-sends

  /// as a copy; the UI only swaps the failure toast for the migration toast.

  bool get _protectedCopyEnabled =>
      _vm.hasProtectedContent &&
      MessageHistorySettings.shared.forwardProtectedAsCopy;
  void _showProtectedCopyResult(ProtectedForwardPlan? plan) {
    if (!mounted || plan == null) return;
    if (plan.skippedIds.isNotEmpty) {
      showToast(
        context,
        AppStrings.t(AppStringKeys.keptForwardCopyPartToast, {
          'value1': plan.copiedCount,
          'value2': plan.skippedIds.length,
        }),
      );
    }
  }

  /// The topic [message] belongs to, or null when it is attributable to

  /// none. TDLib omits `topic_id` on General messages of a forum supergroup,

  /// which is why the fallback is the General topic id there. A bot topic

  /// chat has no General topic, so an unattributed message (topics traffic

  /// predating the bot's toggle, say) belongs to no section rather than to a

  /// bucket that cannot exist.

  /// The display data for a topic section header.

  ///

  /// The loaded topic page carries the name and icon; a topic outside that

  /// page still resolves through the shared index, which live topic traffic

  /// keeps current. Both can miss for a topic this session never listed, so

  /// the label falls back to a generic one — the icon and the tap target keep

  /// Whether a topic section header belongs above [index].

  ///

  /// Mirrors Telegram iOS: the header marks the boundary where the topic

  /// changes, so a run of same-topic messages carries exactly one header.

  /// Service messages never carry one — a join/pin event is not attributable

  /// to a topic — and they do not break a run either: the comparison skips

  /// back over them, because TDLib reports them without a topic and a naive

  /// read would file them under General and repeat the header after them.

  /// A bot chat's unattributed messages are the same: no header, no run

  /// break. The very first attributable message starts a section, since

  /// nothing above it can carry one.

  /// Header-bar launcher for a bot's menu mini app (mirrors the composer's

  /// former pill action).

  /// Opens a link as this transcript, even though the State's context is above

  /// its [InternalChatLinkScope]: the scope's target is re-supplied so the

  /// navigation request carries the owning chat and account.

  /// Whether the mirror holds an edit trail for this message (compile-time

  /// gated): the long-press menu then offers the revision sheet.

  bool _actionTargetHasEdits(ChatMessage message) {
    if (!allowTelegramTosViolations) return false;
    final entry = _vm.mirrorEntryForMessage(message);
    return entry != null && entry.events.isNotEmpty;
  }

  Future<void> _openMessageEdits(ChatMessage message) async {
    final entry = message.mirrorEntry ?? _vm.mirrorEntryForMessage(message);
    if (entry == null || entry.events.isEmpty) return;
    await Navigator.of(context).push(
      AppPageRoute<void>(
        pageBuilder: (_, _, _) => MessageHistoryRevisionView(entry: entry),
      ),
    );
  }

  /// Drops a ghost bubble's kept copy (Telegram §1.4 mirror action).

  void _removeMirrorEntry(ChatMessage message) {
    final entry = message.mirrorEntry;
    if (entry == null) return;
    MessageHistoryStore.shared.deleteEntry(entry);
    showToast(
      context,
      AppStringKeys.historyRemovedFromMirrorToast.l10n(context),
    );
  }
}
