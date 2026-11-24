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

  /// Finds a pack by id in the loaded list, or null.

  StickerPack? _findStickerPack(int id) {
    for (final pack in StickerStore.shared.packs) {
      if (pack.id == id) return pack;
    }
    return null;
  }

  /// A docked panel slot that grows and shrinks with the house motion

  /// language instead of swapping instantly: opening (button tap) and

  /// collapsing (toggle, transcript-drag dismiss, send) both animate. The

  /// outgoing child stays in the tree while the slot collapses, so its state

  /// (scroll offsets, store subscriptions) survives a same-panel reopen only

  /// through the panel's own persistence — never through this animation.

  Widget _animatedDockedPanel({
    required bool visible,
    required Widget Function() builder,
  }) {
    final reduceMotion = AppMotion.isReduced(context);
    // Collapse runs on the accelerate curve (content leaving gets out of the
    // way quickly — the drag-dismiss the user called "not clean"), expansion
    // keeps the standard decelerate. AnimatedSize has no reverseCurve, so the
    // snappier collapse comes from the shorter reverseDuration alone.
    return AnimatedSize(
      duration: reduceMotion
          ? Duration.zero
          : AppMotion.duration(context, AppMotion.responsive),
      reverseDuration: reduceMotion
          ? Duration.zero
          : AppMotion.duration(context, AppMotion.quick),
      curve: AppMotion.standard,
      alignment: Alignment.topCenter,
      clipBehavior: Clip.none,
      child: AnimatedSwitcher(
        duration: reduceMotion
            ? Duration.zero
            : AppMotion.duration(context, AppMotion.quick),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: visible
            ? KeyedSubtree(
                key: const ValueKey('dockedPanelContent'),
                child: builder(),
              )
            : const SizedBox(width: double.infinity),
      ),
    );
  }
  // MARK: Sticker panel

  /// The packs the sticker panel lists vertically, in strip order: recents

  /// first when non-empty, then every installed pack. Favorites render as

  /// their own leading section inside the list.

  List<StickerPack> _stickerPanelPacks() {
    final packs = StickerStore.shared.packs
        .where((p) => p.id != StickerStore.recentPackId)
        .toList(growable: false);
    final recents = StickerStore.shared.packs
        .where((p) => p.id == StickerStore.recentPackId)
        .toList(growable: false);
    return [...recents, ...packs];
  }

  /// Scroll-follow for the sticker strip: the highlighted tab is the pack

  /// whose header last crossed the viewport top, exactly the anchor logic the

  /// unified panel used scoped to packs.

  bool _onStickerPanelScrollNotification(ScrollNotification notification) {
    if (notification is! ScrollEndNotification &&
        notification is! ScrollUpdateNotification) {
      return false;
    }
    if (_stickerPanelAnimatingToPack) {
      if (notification is ScrollEndNotification) {
        _stickerPanelAnimatingToPack = false;
      }
      return false;
    }
    if (!_stickerPanelScroll.hasClients) return false;
    if (_isPanelSearchSelected) return false;
    final packId = _stickerPackAtViewportTop();
    if (packId == null || packId == _stickerAnchorPackId) return false;
    if (packId == _ChatInputBarState._stickerSearchTabId ||
        packId == _ChatInputBarState._gifTabId) {
      return false;
    }
    _updateState(() => _stickerAnchorPackId = packId);
    return false;
  }

  /// The pack whose header sits at (or just above) the viewport top.

  int? _stickerPackAtViewportTop() {
    final position = _stickerPanelScroll.position;
    // Favorites render ahead of every pack: while the favorites header is
    // above the viewport top (and the first pack's header is not), the strip
    // highlights the favorites pseudo-tab.
    if (FavoriteStickerStore.shared.items.isNotEmpty) {
      final favoritesOffset = _packHeaderContextOffset(_favoritesHeaderContext);
      final firstPack = _stickerPanelPacks().firstOrNull;
      final firstPackOffset = firstPack == null
          ? null
          : _packHeaderScrollOffset(firstPack.id, position);
      if (favoritesOffset != null &&
          position.pixels + 2.0 >= favoritesOffset &&
          (firstPackOffset == null ||
              position.pixels + 2.0 < firstPackOffset)) {
        return _ChatInputBarState._favoritesTabId;
      }
    }
    final packs = _stickerPanelPacks();
    if (packs.isEmpty) return null;
    // The scroll cannot advance past maxScrollExtent, so the last packs'
    // headers may never reach the top. At the end of the scroll the tail is
    // what the user is looking at: the last pack wins.
    if (position.pixels >= position.maxScrollExtent - 0.5) {
      return packs.last.id;
    }
    int? best;
    for (final pack in packs) {
      final offset = _packHeaderScrollOffset(pack.id, position);
      if (offset != null && position.pixels + 2.0 >= offset) best = pack.id;
    }
    return best ?? packs.first.id;
  }

  /// The scroll offset that puts a pack header at the viewport top, measured

  /// through the header's live render box so it stays exact even while

  /// earlier packs load or resize.

  double? _packHeaderScrollOffset(int packId, ScrollPosition position) {
    return _packHeaderContextOffset(_packHeaderContexts[packId]);
  }

  double? _packHeaderContextOffset(BuildContext? context) {
    if (context == null) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return null;
    return viewport.getOffsetToReveal(box, 0).offset;
  }

  /// Tab tapped (or the panel reopened on a persisted pack): scroll so that

  /// pack's header sits at the top of the viewport.

  void _scrollStickerPanelToPack(int packId) {
    if (!_stickerPanelScroll.hasClients) {
      // The search overlay can still be unwinding from this same tap: retry
      // once the panel scroll has rebuilt and attached.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            !_isPanelSearchSelected &&
            _stickerPanelScroll.hasClients) {
          _scrollStickerPanelToPack(packId);
        }
      });
      return;
    }
    final position = _stickerPanelScroll.position;
    final target = _packHeaderScrollOffset(packId, position);
    if (target == null) return;
    final clamped = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((clamped - position.pixels).abs() < 0.5) return;
    _stickerPanelAnimatingToPack = true;
    _stickerPanelScroll.animateTo(
      clamped,
      duration: AppMotion.duration(context, AppMotion.routeReverse),
      curve: AppMotion.standard,
    );
  }

  /// Starts the pack's first load the moment its section builds without

  /// contents; one in-flight load per pack per session, retried after a

  /// failure because the entry is removed when the future settles.

  void _ensureStickerPackLoaded(StickerPack? pack) {
    if (pack == null || pack.loaded || pack.stickers.isNotEmpty) return;
    if (_stickerPackLoads.containsKey(pack.id)) return;
    final load = StickerStore.shared
        .loadPack(pack.id)
        .whenComplete(() => _stickerPackLoads.remove(pack.id));
    _stickerPackLoads[pack.id] = load;
  }

  /// A sticker pack's header row; lazily starts the pack's first load the

  /// moment the section builds without contents and registers its context

  /// for the strip's anchor math.

  Widget _mediaStickerPackHeader(StickerPack pack) {
    _ensureStickerPackLoaded(pack);
    final title = pack.id == StickerStore.recentPackId
        ? AppStrings.t(AppStringKeys.stickerStoreRecent)
        : pack.title;
    return Builder(
      builder: (context) {
        _packHeaderContexts[pack.id] = context;
        return _mediaSubsectionHeader(
          ValueKey('mediaStickerPack-${pack.id}'),
          title,
        );
      },
    );
  }

  /// The favorites pseudo-tab scrolls the panel list to the favorites

  /// section header (it is not a real pack, so it has no pack id).

  void _scrollStickerPanelToFavorites() {
    final ctx = _favoritesHeaderContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.attached || !_stickerPanelScroll.hasClients) {
      return;
    }
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    final position = _stickerPanelScroll.position;
    final target = viewport
        .getOffsetToReveal(box, 0)
        .offset
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    _updateState(
      () => _stickerAnchorPackId = _ChatInputBarState._favoritesTabId,
    );
    if ((target - position.pixels).abs() < 0.5) return;
    _stickerPanelAnimatingToPack = true;
    _stickerPanelScroll.animateTo(
      target,
      duration: AppMotion.duration(context, AppMotion.routeReverse),
      curve: AppMotion.standard,
    );
  }

  String _emojiCategoryTabId(int index) => 'category-$index';

  /// Scrolls the emoji panel so the named section's header sits at the top:

  /// 'recent', 'category-i' or 'pack-id'.

  void _scrollEmojiPanelTo(String sectionId) {
    if (_emojiTab != sectionId) {
      _updateState(() => _emojiTab = sectionId);
    }
    final target = _emojiSectionTarget(sectionId);
    if (target == null) return;
    if (!_emojiPanelScroll.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _emojiPanelScroll.hasClients) {
          _scrollEmojiPanelTo(sectionId);
        }
      });
      return;
    }
    final position = _emojiPanelScroll.position;
    final clamped = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((clamped - position.pixels).abs() < 0.5) return;
    _emojiPanelAnimatingToSection = true;
    _emojiPanelScroll.animateTo(
      clamped,
      duration: AppMotion.duration(context, AppMotion.routeReverse),
      curve: AppMotion.standard,
    );
  }

  /// Analytic offset of an emoji section header, exactly like the standalone

  /// pane computes them: headers and grid rows both have fixed extents, so

  /// the sum is exact however far off-screen the section is.

  double? _emojiSectionTarget(String sectionId) {
    final columns = _emojiPanelColumns;
    if (columns == null) return null;
    var offset = 8.0; // top spacer
    if (EmojiRecentsStore.shared.renderableEntries.isNotEmpty) {
      if (sectionId == 'recent') return offset;
      offset +=
          emojiSectionHeaderExtent +
          (EmojiRecentsStore.shared.renderableEntries.length / columns)
                  .ceilToDouble() *
              emojiPanelCellExtent;
    }
    for (var i = 0; i < EmojiCatalog.categories.length; i++) {
      if (sectionId == _emojiCategoryTabId(i)) return offset;
      offset +=
          emojiSectionHeaderExtent +
          (EmojiCatalog.categories[i].emojis.length / columns).ceilToDouble() *
              emojiPanelCellExtent;
    }
    for (final pack in EmojiStore.shared.customPacks) {
      if (sectionId == 'pack-${pack.id}') {
        return offset;
      }
      offset +=
          _ChatInputBarState._emojiPackHeaderExtent +
          (pack.emoji.length / columns).ceilToDouble() * emojiPanelCellExtent;
    }
    return null;
  }

  /// Scroll-follow for the emoji strip: the highlighted entry is the section

  /// whose header last crossed the viewport top.

  bool _onEmojiPanelScrollNotification(ScrollNotification notification) {
    if (notification is! ScrollEndNotification &&
        notification is! ScrollUpdateNotification) {
      return false;
    }
    if (_emojiPanelAnimatingToSection) {
      if (notification is ScrollEndNotification) {
        _emojiPanelAnimatingToSection = false;
      }
      return false;
    }
    if (!_emojiPanelScroll.hasClients) return false;
    if (_isPanelSearchSelected) return false;
    final pixels = _emojiPanelScroll.position.pixels;
    final sectionId = _emojiSectionAt(pixels);
    if (sectionId == null || sectionId == _emojiTab) return false;
    if (sectionId == _ChatInputBarState._emojiSearchTab) return false;
    _updateState(() => _emojiTab = sectionId);
    return false;
  }

  /// The section id whose header last scrolled to (or past) the viewport top.

  String? _emojiSectionAt(double pixels) {
    final columns = _emojiPanelColumns;
    if (columns == null) return null;
    var offset = 8.0;
    String? best;
    bool sawAny = false;
    if (EmojiRecentsStore.shared.renderableEntries.isNotEmpty) {
      sawAny = true;
      best = 'recent';
      offset +=
          emojiSectionHeaderExtent +
          (EmojiRecentsStore.shared.renderableEntries.length / columns)
                  .ceilToDouble() *
              emojiPanelCellExtent;
    }
    for (var i = 0; i < EmojiCatalog.categories.length; i++) {
      if (pixels + 2.0 >= offset) {
        best = _emojiCategoryTabId(i);
      }
      offset +=
          emojiSectionHeaderExtent +
          (EmojiCatalog.categories[i].emojis.length / columns).ceilToDouble() *
              emojiPanelCellExtent;
    }
    for (final pack in EmojiStore.shared.customPacks) {
      if (pixels + 2.0 >= offset) {
        best = 'pack-${pack.id}';
      }
      offset +=
          _ChatInputBarState._emojiPackHeaderExtent +
          (pack.emoji.length / columns).ceilToDouble() * emojiPanelCellExtent;
    }
    return sawAny || best != null ? best : null;
  }

  /// A lighter-weight sub-header for a subsection (sticker pack, custom-emoji

  /// pack) inside a section.

  Widget _mediaSubsectionHeader(Key key, String label) {
    final c = context.colors;
    return SizedBox(
      key: key,
      height: 26,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 14, top: 4),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: c.textTertiary,
            ),
          ),
        ),
      ),
    );
  }

  /// The trailing search affordance on the segment-control row. Tapping it

  /// enters the existing panel-search mode for the active section kind and

  /// swaps the unified scroll for the search results; tapping it again leaves

  /// search and restores the previous scroll offset.

  Widget _mediaPanelSearchButton({required bool active}) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: AppStringKeys.composerMediaSearch.l10n(context),
      child: GestureDetector(
        key: const ValueKey('mediaPanelSearchButton'),
        behavior: HitTestBehavior.opaque,
        onTap: _togglePanelSearch,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Center(
            child: AppIcon(
              HeroAppIcons.magnifyingGlass,
              size: 19,
              color: active ? AppTheme.brand : c.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  /// The search content replacing the unified scroll while search is active:

  /// the existing per-kind search result grids, unchanged.

  Widget _panelSearchContent() {
    return switch (_mediaKind) {
      _MediaKind.emoji => _emojiSearchContent(),
      _MediaKind.sticker => _stickerSearchContent(),
      _MediaKind.gif => _gifSearchContent(),
    };
  }

  /// The active kind's panel scroller, whose offset the search overlay

  /// remembers and restores. GIF keeps no panel scroll (its content is a

  /// plain grid at the top).

  ScrollController? get _activePanelScroll => switch (_mediaKind) {
    _MediaKind.emoji => _emojiPanelScroll,
    _MediaKind.sticker => _stickerPanelScroll,
    _MediaKind.gif => null,
  };

  /// Enters/leaves the panel-search overlay, remembering where the active

  /// kind's panel scroll sat so leaving restores the user's place.

  void _togglePanelSearch() {
    if (_isPanelSearchSelected) {
      final restore = _panelScrollRestoreOffset;
      _updateState(() {
        _exitPanelSearchTabs();
        _panelScrollRestoreOffset = null;
      });
      final controller = _activePanelScroll;
      if (restore != null && controller != null && controller.hasClients) {
        final position = controller.position;
        // correctBy never animates and never throws overscroll notifications;
        // clamping to the live extents keeps a shrunken content height
        // (a pack list that reloads, for example) from restoring past the end.
        final target = restore.clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        position.correctBy(target - position.pixels);
      }
      return;
    }
    _updateState(() {
      final controller = _activePanelScroll;
      _panelScrollRestoreOffset = controller != null && controller.hasClients
          ? controller.position.pixels
          : null;
      switch (_mediaKind) {
        case _MediaKind.emoji:
          _emojiTab = _ChatInputBarState._emojiSearchTab;
        case _MediaKind.sticker:
          _stickerPack = _ChatInputBarState._stickerSearchTabId;
        case _MediaKind.gif:
          _stickerPack = _ChatInputBarState._stickerSearchTabId;
      }
    });
    if (_panelSearch.text.trim().isNotEmpty) {
      _queuePanelSearch();
    }
  }

  /// Returns the tab selectors to their non-search values (called from inside

  /// a setState block).

  void _exitPanelSearchTabs() {
    switch (_mediaKind) {
      case _MediaKind.emoji:
        if (_emojiTab == _ChatInputBarState._emojiSearchTab) {
          _emojiTab = 'standard';
        }
      case _MediaKind.sticker:
        if (_stickerPack == _ChatInputBarState._stickerSearchTabId) {
          _stickerPack = null;
        }
      case _MediaKind.gif:
        if (_stickerPack == _ChatInputBarState._stickerSearchTabId) {
          _stickerPack = _ChatInputBarState._gifTabId;
        }
    }
  }

  /// Maps a segment key like `mediaSegment-gif` to its kind label, so the

  /// selected segment's highlight carries an assertable

  /// `mediaSegmentSelected-<kind>` key.

  String _segmentKindLabel(Key? key) {
    if (key is ValueKey<String>) {
      final value = key.value;
      final dash = value.lastIndexOf('-');
      if (dash >= 0 && dash + 1 < value.length) {
        return value.substring(dash + 1);
      }
      return value;
    }
    return key?.toString() ?? '';
  }

  Future<void> _sendStickerItem(
    StickerItem item, {
    MessageSendConfiguration? config,
  }) async {
    widget.onMediaSendTapped?.call();
    final sent = await widget.vm.sendSticker(item, sendConfiguration: config);
    if (!mounted) return;
    if (sent) {
      _finishPanelSend();
    } else {
      showToast(
        context,
        AppStrings.t(AppStringKeys.stickerSetDetailActionFailed),
      );
    }
  }

  Future<void> _sendGifItem(
    GifItem item, {
    MessageSendConfiguration? config,
  }) async {
    widget.onMediaSendTapped?.call();
    final sent = await widget.vm.sendGif(item, sendConfiguration: config);
    if (!mounted) return;
    if (sent) {
      _finishPanelSend();
    } else {
      showToast(context, AppStrings.t(AppStringKeys.composerGifSendFailed));
    }
  }

  /// Long-press haptic matching the emoji cell's pattern: a light selection

  /// tick on touch platforms only.

  void _mediaTileLongPressHaptic() {
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.android || platform == TargetPlatform.iOS) {
      unawaited(HapticFeedback.selectionClick());
    }
  }

  /// The composer side of the media-tile action sheet: descriptor plus the

  /// actions each row performs. A row the caller passes null for is hidden.

  void _showStickerTileActions(StickerItem item, {required bool isRecentTile}) {
    _mediaTileLongPressHaptic();
    unawaited(
      showMediaTileActionSheet(
        context,
        MediaTileDescriptor.sticker(
          item,
          FavoriteStickerStore.shared.isFavorite(item.id),
          isRecentTile,
        ),
        MediaTileActions(
          send: () => unawaited(_sendStickerItem(item)),
          sendWithoutSound: () => unawaited(
            _sendStickerItem(
              item,
              config: const MessageSendConfiguration(disableNotification: true),
            ),
          ),
          schedule: () => unawaited(_scheduleStickerSend(item)),
          toggleFavorite: () => unawaited(_toggleStickerFavorite(item)),
          viewSet: () => _openStickerSet(item.setId),
          save: () => unawaited(_exportStickerTile(item)),
          copy: () => unawaited(_copyStickerFile(item)),
          removeFromRecent: isRecentTile
              ? () => widget.vm.removeRecentSticker(item.id)
              : null,
        ),
      ),
    );
  }

  void _showGifTileActions(GifItem item) {
    _mediaTileLongPressHaptic();
    unawaited(
      showMediaTileActionSheet(
        context,
        MediaTileDescriptor.gif(item, false),
        MediaTileActions(
          send: () => unawaited(_sendGifItem(item)),
          sendWithoutSound: () => unawaited(
            _sendGifItem(
              item,
              config: const MessageSendConfiguration(disableNotification: true),
            ),
          ),
          schedule: () => unawaited(_scheduleGifSend(item)),
          save: () => unawaited(_saveGifTile(item)),
        ),
      ),
    );
  }

  /// The tile menu's Schedule: the same owned picker the send-options sheet

  /// opens, pre-armed to send this sticker once a future date is confirmed.

  Future<void> _scheduleStickerSend(StickerItem item) async {
    final config = await _pickTileScheduleConfiguration();
    if (config == null) return;
    await _sendStickerItem(item, config: config);
  }

  Future<void> _scheduleGifSend(GifItem item) async {
    final config = await _pickTileScheduleConfiguration();
    if (config == null) return;
    await _sendGifItem(item, config: config);
  }

  /// Opens the app's owned schedule picker (the one showMessageSendOptionsSheet

  /// uses) and turns the picked date into a send configuration.

  Future<MessageSendConfiguration?> _pickTileScheduleConfiguration() async {
    final now = DateTime.now();
    final selected = await showOwnedSchedulePicker(
      context: context,
      initial: now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 366)),
    );
    if (selected == null || !selected.isAfter(now)) return null;
    return MessageSendConfiguration(scheduleAt: selected);
  }

  Future<void> _toggleStickerFavorite(StickerItem item) async {
    final store = FavoriteStickerStore.shared;
    if (store.isFavorite(item.id)) {
      await store.remove(item);
    } else {
      await store.add(item);
    }
  }

  void _openStickerSet(int setId) {
    if (setId == 0) {
      showToast(
        context,
        AppStrings.t(AppStringKeys.stickerSetDetailActionFailed),
      );
      return;
    }
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => StickerSetDetailView(setId: setId),
        ),
      ),
    );
  }

  /// Save/export a panel sticker tile. There is no message to anchor on, so

  /// the tile's file is wrapped in a synthetic one the way the set export

  /// already wraps set entries internally.

  Future<void> _exportStickerTile(StickerItem item) async {
    final file = TdFileRef(id: item.id);
    final message = ChatMessage(
      id: item.id,
      isOutgoing: false,
      text: '',
      date: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      image: item.isAnimated || item.isVideo ? null : file,
      animatedSticker: item.isAnimated ? file : null,
      videoSticker: item.isVideo ? file : null,
    );
    final desktop = isDesktopTargetPlatform(Theme.of(context).platform);
    final result = await StickerExportService.export(
      message,
      format: StickerExportFormat.png,
      destination: desktop
          ? StickerExportDestination.files
          : StickerExportDestination.photos,
    );
    if (!mounted) return;
    if (result != StickerExportResult.cancelled) {
      showToast(
        context,
        AppStrings.t(
          result == StickerExportResult.saved
              ? (desktop
                    ? AppStringKeys.stickerExportSavedToFiles
                    : AppStringKeys.chatSavedToPhotos)
              : result == StickerExportResult.permissionDenied
              ? AppStringKeys.chatSaveToPhotosPermissionDenied
              : AppStringKeys.stickerExportFailed,
        ),
      );
    }
  }

  /// Desktop webp sticker copy: puts the resolved local file path on the

  /// clipboard. The sheet gates the row to static desktop stickers; a vanished

  /// file reports instead of throwing into the zone.

  Future<void> _copyStickerFile(StickerItem item) async {
    try {
      final path = await TdFileCenter.shared.pathFor(
        item.thumb ?? TdFileRef(id: item.id),
      );
      if (path == null || path.isEmpty) throw StateError('no local file');
      await Clipboard.setData(ClipboardData(text: path));
      if (!mounted) return;
      showToast(context, AppStrings.t(AppStringKeys.profileDetailCopied));
    } catch (_) {
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.stickerSetDetailActionFailed),
      );
    }
  }

  /// Save a panel GIF tile. Mobile adds the downloaded mp4 to the photo

  /// library like a chat GIF message; a desktop host has no album, so the

  /// file goes through the same save panel MediaDownloadService already

  /// uses for chat media.

  Future<void> _saveGifTile(GifItem item) async {
    final desktop = isDesktopTargetPlatform(Theme.of(context).platform);
    if (desktop) {
      final outcome = await MediaDownloadService.saveMedia(
        file: item.file,
        isVideo: true,
      );
      if (!mounted) return;
      final feedback = MediaDownloadService.feedbackFor(outcome);
      if (feedback != null) showToast(context, feedback);
      return;
    }
    try {
      final path = await TdFileCenter.shared.pathFor(item.file);
      if (path == null || path.isEmpty) {
        throw StateError('no local file');
      }
      final file = File(path);
      if (!await file.exists()) throw StateError('file missing');
      final result = await MediaLibrarySaver.savePreparedFile(
        file,
        isVideo: true,
      );
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(switch (result) {
          MediaLibrarySaveResult.saved => AppStringKeys.chatSavedToPhotos,
          MediaLibrarySaveResult.permissionDenied =>
            AppStringKeys.chatSaveToPhotosPermissionDenied,
          MediaLibrarySaveResult.unsupported ||
          MediaLibrarySaveResult.failed => AppStringKeys.chatSaveToPhotosFailed,
        }),
      );
    } catch (_) {
      if (!mounted) return;
      showToast(context, AppStrings.t(AppStringKeys.chatSaveToPhotosFailed));
    }
  }
}
