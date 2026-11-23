part of 'chat_input_bar.dart';

extension _ChatInputBarPanels on _ChatInputBarState {
  void _queuePanelSearch() {
    _panelSearchTimer?.cancel();
    final query = _panelSearch.text.trim();
    if (query.isEmpty) {
      _panelSearchGeneration++;
      if (mounted) {
        _updateState(() {
          _panelSearchLoading = false;
          _emojiSearchResults = const [];
          _customEmojiSearchResults = const [];
          _stickerSearchResults = const [];
          _gifSearchResults = const [];
          _gifSearchNextOffset = '';
          _gifSearchLoadingMore = false;
        });
      }
      return;
    }
    if (!_isPanelSearchSelected) return;
    _panelSearchTimer = Timer(
      const Duration(milliseconds: 320),
      () => unawaited(_runPanelSearch(query)),
    );
  }

  Future<void> _runPanelSearch(String query) async {
    if (!_isPanelSearchSelected) return;
    final generation = ++_panelSearchGeneration;
    if (mounted) _updateState(() => _panelSearchLoading = true);
    final languageCodes = mounted
        ? [Localizations.localeOf(context).languageCode]
        : const <String>[];
    var emoji = const <String>[];
    var customEmoji = const <StickerItem>[];
    var stickers = const <StickerItem>[];
    var gifs = const <GifItem>[];
    var gifNextOffset = '';
    try {
      if (_mediaPanelOpen &&
          _mediaKind == _MediaKind.emoji &&
          _emojiTab == _ChatInputBarState._emojiSearchTab) {
        final results = await Future.wait([
          TdClient.shared.query({
            '@type': 'searchEmojis',
            'text': query,
            'input_language_codes': languageCodes,
          }),
          TdClient.shared.query({
            '@type': 'searchStickers',
            'sticker_type': {'@type': 'stickerTypeCustomEmoji'},
            'emojis': '',
            'query': query,
            'input_language_codes': languageCodes,
            'offset': 0,
            'limit': 80,
          }),
        ]);
        final values = <String>[];
        for (final keyword
            in results.first.objects('emoji_keywords') ??
                const <Map<String, dynamic>>[]) {
          final value = keyword.str('emoji');
          if (value != null && value.isNotEmpty && !values.contains(value)) {
            values.add(value);
          }
        }
        emoji = values;
        customEmoji = parseStickers(results.last.objects('stickers'));
      } else if (_mediaPanelOpen &&
          _mediaKind == _MediaKind.sticker &&
          _stickerPack == _ChatInputBarState._stickerSearchTabId) {
        final results = await Future.wait<dynamic>([
          TdClient.shared.query({
            '@type': 'searchStickers',
            'sticker_type': {'@type': 'stickerTypeRegular'},
            'emojis': '',
            'query': query,
            'input_language_codes': languageCodes,
            'offset': 0,
            'limit': 100,
          }),
        ]);
        final result = results.first as Map<String, dynamic>;
        stickers = parseStickers(result.objects('stickers'));
      } else if (_mediaPanelOpen &&
          _mediaKind == _MediaKind.gif &&
          _gifSearchSelected) {
        final gifPage = await _searchGifs(query);
        gifs = gifPage.$1;
        gifNextOffset = gifPage.$2;
      }
    } catch (_) {}
    if (!mounted ||
        generation != _panelSearchGeneration ||
        query != _panelSearch.text.trim() ||
        !_isPanelSearchSelected) {
      return;
    }
    _updateState(() {
      _panelSearchLoading = false;
      _emojiSearchResults = emoji;
      _customEmojiSearchResults = customEmoji;
      _stickerSearchResults = stickers;
      _gifSearchResults = gifs;
      _gifSearchNextOffset = gifNextOffset;
      _gifSearchLoadingMore = false;
    });
  }

  Future<(List<GifItem>, String)> _searchGifs(
    String query, {
    String offset = '',
  }) async {
    final option = await TdClient.shared.query({
      '@type': 'getOption',
      'name': 'animation_search_bot_username',
    });
    final username = option.str('value') ?? '';
    if (username.isEmpty) return (const <GifItem>[], '');
    final botChat = await TdClient.shared.query({
      '@type': 'searchPublicChat',
      'username': username,
    });
    final botUserId = botChat.obj('type')?.int64('user_id');
    if (botUserId == null) return (const <GifItem>[], '');
    final response = await TdClient.shared.query({
      '@type': 'getInlineQueryResults',
      'bot_user_id': botUserId,
      'chat_id': vm.chatId,
      'query': query,
      'offset': offset,
    });
    final page = parseInlineGifSearchPage(response);
    return (page.items, page.nextOffset);
  }

  Future<void> _loadMoreGifSearch() async {
    final query = _panelSearch.text.trim();
    final offset = _gifSearchNextOffset;
    if (!_isPanelSearchSelected ||
        query.isEmpty ||
        offset.isEmpty ||
        _gifSearchLoadingMore) {
      return;
    }
    _updateState(() => _gifSearchLoadingMore = true);
    try {
      final page = await _searchGifs(query, offset: offset);
      if (!mounted ||
          query != _panelSearch.text.trim() ||
          !_isPanelSearchSelected) {
        return;
      }
      final known = _gifSearchResults.map((item) => item.id).toSet();
      _updateState(() {
        _gifSearchResults = [
          ..._gifSearchResults,
          ...page.$1.where((item) => known.add(item.id)),
        ];
        _gifSearchNextOffset = page.$2;
        _gifSearchLoadingMore = false;
      });
    } catch (_) {
      if (mounted) _updateState(() => _gifSearchLoadingMore = false);
    }
  }

  void _selectEmojiTab(String tab) {
    if (_emojiTab == tab) return;
    _updateState(() => _emojiTab = tab);
    if (tab == _ChatInputBarState._emojiSearchTab &&
        _panelSearch.text.trim().isNotEmpty) {
      _queuePanelSearch();
    }
  }

  void _selectStickerTab(int tab) {
    if (tab != _ChatInputBarState._stickerSearchTabId) {
      // A pack tab scrolls the continuous list; the search tab swaps content
      // instead and needs no anchor.
      if (_stickerPack != tab) {
        _updateState(() => _stickerPack = tab);
      }
      _scrollStickerPanelToPack(tab);
      if (tab == _ChatInputBarState._gifTabId) {
        GifStore.shared.loadIfNeeded();
      } else if (tab == StickerStore.recentPackId) {
        StickerStore.shared.loadIfNeeded();
      } else {
        final pack = _findStickerPack(tab);
        if (pack != null) _ensureStickerPackLoaded(pack);
      }
      return;
    }
    if (_stickerPack == _ChatInputBarState._stickerSearchTabId) return;
    _updateState(() => _stickerPack = _ChatInputBarState._stickerSearchTabId);
    if (_panelSearch.text.trim().isNotEmpty) {
      _queuePanelSearch();
    }
  }

  void _setPanel(_Panel next) {
    if (_panel == next && !_quickReplyContextVisible) return;
    if (_panel == _Panel.voice && next != _Panel.voice) {
      _cancelVoiceRecording();
    }
    if (next != _Panel.none) _hideDesktopPopovers(rebuild: false);
    _updateState(() {
      _panel = next;
      _quickReplyContextVisible = false;
      _voiceInlineError = _VoiceInlineError.none;
    });
    widget.onPanelGeometryChanged?.call();
  }

  void _selectMediaKind(_MediaKind kind) {
    if (_mediaKind == kind) return;
    var stickerPack = _stickerPack;
    if (kind == _MediaKind.sticker &&
        _stickerPack == _ChatInputBarState._gifTabId) {
      // The saved-GIFs tab belongs to the GIF segment; dropping it lets the
      // sticker segment resolve its own default tab.
      stickerPack = null;
    }
    _updateState(() {
      _mediaKind = kind;
      _stickerPack = stickerPack;
    });
    widget.onMediaKindChanged?.call(kind.name);
    switch (kind) {
      case _MediaKind.emoji:
        EmojiStore.shared.loadIfNeeded();
        EmojiRecentsStore.shared.loadIfNeeded();
      case _MediaKind.sticker:
        FavoriteStickerStore.shared.loadIfNeeded();
        final activeId = _activeStickerTab;
        if (activeId == StickerStore.recentPackId ||
            activeId == _ChatInputBarState._stickerSearchTabId) {
          StickerStore.shared.loadIfNeeded();
        } else {
          _ensureStickerPackLoaded(_findStickerPack(activeId));
        }
      case _MediaKind.gif:
        GifStore.shared.loadIfNeeded();
    }
    if (_isPanelSearchSelected && _panelSearch.text.trim().isNotEmpty) {
      _queuePanelSearch();
    }
  }

  void _toggleMediaPanel() {
    if (_mediaPanelOpen) {
      _toggle(_Panel.none);
      return;
    }
    switch (_mediaKind) {
      case _MediaKind.emoji:
        EmojiStore.shared.loadIfNeeded();
        EmojiRecentsStore.shared.loadIfNeeded();
      case _MediaKind.sticker:
        StickerStore.shared.loadIfNeeded();
        FavoriteStickerStore.shared.loadIfNeeded();
      case _MediaKind.gif:
        GifStore.shared.loadIfNeeded();
    }
    _toggle(_mediaKind == _MediaKind.emoji ? _Panel.emoji : _Panel.sticker);
    if (_mediaPanelOpen &&
        _isPanelSearchSelected &&
        _panelSearch.text.trim().isNotEmpty) {
      _queuePanelSearch();
    }
  }

  void _finishPanelSend() {
    if (_desktopSenderPopoverVisible || _desktopMediaPopoverVisible) {
      _hideDesktopPopovers();
    } else {
      _setPanel(_Panel.none);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onMessageSent();
    });
  }

  void _removeClipboardAttachment(int index) {
    if (index < 0 || index >= _pendingClipboardAttachments.length) {
      return;
    }
    final attachment = _pendingClipboardAttachments[index];
    _updateState(() => _pendingClipboardAttachments.removeAt(index));
    widget.onPanelGeometryChanged?.call();
    unawaited(_deleteTempFile(attachment.path));
  }

  String _replyPreview(ChatMessage m) {
    if (m.document != null) {
      return AppStrings.t(AppStringKeys.composerFilePreview, {
        'value1': m.document!.fileName,
      });
    }
    if (m.voice != null) {
      return AppStrings.t(AppStringKeys.composerVoicePreview);
    }
    if (m.location != null) {
      return AppStrings.t(AppStringKeys.composerLocationPreview);
    }
    if (m.isDice) {
      return m.diceEmoji ?? m.text;
    }
    if (m.isAnimatedEmoji) {
      return m.text;
    }
    if (m.animatedSticker != null) {
      return AppStrings.t(AppStringKeys.composerAnimatedEmojiPreview);
    }
    if (m.image != null) {
      return m.text.isEmpty
          ? AppStrings.t(AppStringKeys.composerImagePreview)
          : m.text;
    }
    return m.text;
  }

  void _hideDesktopPopovers({bool rebuild = true}) {
    _desktopSendOptionsMenu?.dismiss();
    _desktopSendOptionsMenu = null;
    final changed = _desktopSenderPopoverVisible || _desktopMediaPopoverVisible;
    if (_desktopSenderPopoverVisible) {
      _desktopSenderPopoverController.hide();
      _desktopSenderPopoverVisible = false;
    }
    if (_desktopMediaPopoverVisible) {
      _desktopMediaPopoverController.hide();
      _desktopMediaPopoverVisible = false;
    }
    if (changed && rebuild && mounted) _updateState(() {});
  }

  void _toggleDesktopSenderPopover() {
    if (_desktopSenderPopoverVisible) {
      _hideDesktopPopovers();
      return;
    }
    _hideDesktopPopovers(rebuild: false);
    _desktopSenderPopoverController.show();
    _updateState(() => _desktopSenderPopoverVisible = true);
  }

  void _toggleDesktopMediaPopover() {
    if (_desktopMediaPopoverVisible) {
      _hideDesktopPopovers();
      return;
    }
    _hideDesktopPopovers(rebuild: false);
    if (_panel != _Panel.none) {
      _panel = _Panel.none;
      widget.onPanelGeometryChanged?.call();
    }
    switch (_mediaKind) {
      case _MediaKind.emoji:
        EmojiStore.shared.loadIfNeeded();
        EmojiRecentsStore.shared.loadIfNeeded();
      case _MediaKind.sticker:
        StickerStore.shared.loadIfNeeded();
        FavoriteStickerStore.shared.loadIfNeeded();
      case _MediaKind.gif:
        GifStore.shared.loadIfNeeded();
    }
    _desktopMediaPopoverController.show();
    _updateState(() => _desktopMediaPopoverVisible = true);
    if (_isPanelSearchSelected && _panelSearch.text.trim().isNotEmpty) {
      _queuePanelSearch();
    }
  }

  Future<List<BusinessQuickReplyShortcut>> _fetchQuickReplies() async {
    final injected = widget.quickReplyLoader;
    if (injected != null) return injected();
    return BusinessQuickReplyService.shared.preloadShortcuts();
  }

  Future<void> _loadQuickReplies({required bool userInitiated}) async {
    if (_quickRepliesLoaded || !_canUseQuickReplies) return;
    try {
      final replies = await _fetchQuickReplies();
      if (!mounted) return;
      _updateState(() {
        _quickReplies = replies;
        _quickRepliesLoaded = true;
        _quickReplyContextVisible =
            userInitiated && replies.isNotEmpty && _canUseQuickReplies;
      });
      if (userInitiated && replies.isNotEmpty) _focus.unfocus();
    } catch (error) {
      if (!mounted) return;
      _updateState(() => _quickReplyContextVisible = false);
      if (userInitiated) {
        showToast(
          context,
          AppStrings.t(
            AppStringKeys.businessToolsCouldNotLoadQuickRepliesValue1,
            {'value1': error},
          ),
        );
        _restoreKeyboardFocus();
      }
    }
  }

  Future<void> _sendQuickReply(BusinessQuickReplyShortcut shortcut) async {
    if (_quickReplySendingId != null) return;
    _updateState(() => _quickReplySendingId = shortcut.id);
    try {
      final injected = widget.quickReplySender;
      if (injected != null) {
        await injected(vm.chatId, shortcut.id);
      } else {
        await BusinessQuickReplyService.shared.send(vm.chatId, shortcut.id);
      }
      if (!mounted) return;
      _updateState(() {
        _quickReplySendingId = null;
        _quickReplyContextVisible = false;
      });
      widget.onMessageSent();
    } catch (error) {
      if (!mounted) return;
      _updateState(() => _quickReplySendingId = null);
      showToast(
        context,
        AppStrings.t(AppStringKeys.businessToolsCouldNotSendQuickReplyValue1, {
          'value1': error,
        }),
      );
    }
  }

  double _touchTextFieldMaxHeight() {
    // Read above Scaffold's resized body: its descendant MediaQuery has already
    // removed the keyboard inset, but still reports the full screen size.
    final viewportContext = Scaffold.maybeOf(context)?.context ?? context;
    final viewportElement = viewportContext
        .getElementForInheritedWidgetOfExactType<MediaQuery>();
    // Subscribe THIS composer to the original metrics, not Scaffold's context:
    // cached chat shells otherwise keep a stale cap during keyboard resizing.
    final viewport = viewportElement == null
        ? MediaQuery.of(context)
        : (context.dependOnInheritedElement(viewportElement) as MediaQuery)
              .data;
    final availableHeight = math.max(
      0.0,
      viewport.size.height - viewport.viewInsets.bottom,
    );
    final data = ContentSizeScope.of(context);
    final fontSize = data.systemTextScaler.scale(
      AppTextSize.messageBody(Theme.of(context).platform) * data.appScale,
    );
    final painter = TextPainter(
      text: TextSpan(
        text: ' ',
        style: Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(fontSize: fontSize),
      ),
      textDirection: Directionality.of(context),
    )..layout();
    final lineHeight = painter.preferredLineHeight;
    painter.dispose();
    return math.max(lineHeight, availableHeight * .35);
  }

  bool _usesNativeDesktopComposer(BuildContext context) {
    if (kIsWeb) return false;
    return switch (Theme.of(context).platform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      _ => false,
    };
  }

  void _insertComposerLineBreak() {
    final value = _controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final text = value.text.replaceRange(start, end, '\n');
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: start + 1),
    );
  }

  bool _simpleComposerFitsLeadingCell({
    required double width,
    required bool hasText,
    required double leadingActionWidth,
  }) {
    if (!hasText) return true;
    final typingField =
        width -
        2 * AppSpacing.xs -
        2 * AppSpacing.xxs -
        3 * AppMetric.simpleComposerCell -
        _phoneSendSlotWidth -
        leadingActionWidth;
    return typingField >= AppMetric.simpleComposerNarrowField;
  }

  void _showKeyboardFromSimplePanel() {
    _setPanel(_Panel.none);
    _focus.requestFocus();
  }

  void _openSimpleVoicePanel() {
    _replyKeyboardVisible = false;
    _toggleVoice();
  }

  void _openSimpleMediaPanel() {
    _replyKeyboardVisible = false;
    _toggleMediaPanel();
  }

  void _toggleSimpleMorePanel() {
    if (_panel != _Panel.function) _replyKeyboardVisible = false;
    _toggle(_Panel.function);
  }
}
