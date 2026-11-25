part of 'chat_input_bar.dart';

extension _ChatInputBarBots on _ChatInputBarState {
  void _updateMentionSuggestions() {
    final query = activeMentionQuery(_controller.text, _controller.selection);
    final includeInlineBots =
        query != null && query.start == 0 && !vm.isSecretChat;
    if (!_focus.hasFocus ||
        query == null ||
        (!vm.isGroup && !includeInlineBots)) {
      _mentionSearchTimer?.cancel();
      _mentionSearchGeneration++;
      if (_mentionQuery != null || _mentionCandidates.isNotEmpty) {
        _mentionQuery = null;
        _mentionCandidates = const [];
        if (mounted) _updateState(() {});
      }
      return;
    }
    if (_mentionQuery?.start == query.start &&
        _mentionQuery?.end == query.end &&
        _mentionQuery?.query == query.query) {
      return;
    }
    _mentionQuery = query;
    _mentionCandidates = const [];
    if (mounted) _updateState(() {});
    _mentionSearchTimer?.cancel();
    final generation = ++_mentionSearchGeneration;
    _mentionSearchTimer = Timer(const Duration(milliseconds: 120), () async {
      final candidates = includeInlineBots
          ? await vm.searchMentionCandidates(
              query.query,
              includeInlineBots: true,
            )
          : await vm.searchMentionCandidates(query.query);
      if (!mounted || generation != _mentionSearchGeneration) return;
      final active = activeMentionQuery(
        _controller.text,
        _controller.selection,
      );
      if (!_focus.hasFocus ||
          active == null ||
          active.start != query.start ||
          active.end != query.end ||
          active.query != query.query) {
        return;
      }
      _updateState(() => _mentionCandidates = candidates);
    });
  }

  void _selectMention(MentionCandidate candidate) {
    final query = activeMentionQuery(_controller.text, _controller.selection);
    final expected = _mentionQuery;
    if (query == null ||
        expected == null ||
        query.start != expected.start ||
        query.end != expected.end ||
        query.query != expected.query) {
      return;
    }
    _mentionSearchTimer?.cancel();
    _mentionSearchGeneration++;
    _mentionQuery = null;
    _mentionCandidates = const [];
    if (candidate.isInlineBot &&
        query.start == 0 &&
        candidate.username.trim().isNotEmpty) {
      final cleanUsername = candidate.username.trim().replaceFirst(
        RegExp(r'^@+'),
        '',
      );
      final replacement = '@$cleanUsername ';
      final replaceEnd =
          query.end < _controller.text.length &&
              _controller.text[query.end].trim().isEmpty
          ? query.end + 1
          : query.end;
      final newText = _controller.text.replaceRange(
        query.start,
        replaceEnd,
        replacement,
      );
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: query.start + replacement.length,
        ),
      );
      _focus.requestFocus();
      return;
    }
    _controller.insertTextMention(
      start: query.start,
      end: query.end,
      label: candidate.name,
      userId: candidate.userId,
    );
    _focus.requestFocus();
  }

  void _updateBotCommandSuggestions({bool force = false, bool rebuild = true}) {
    final query = activeBotCommandQuery(
      _controller.text,
      _controller.selection,
    );
    // Commands complete in groups (member bots' commands) and in private bot
    // chats (the bot's own command list from userFullInfo).
    final supportsCommands = (vm.isGroup && !vm.isChannel) || vm.peerIsBot;
    if (query == null || !supportsCommands) {
      if (_botCommandQuery == null && _botCommandCandidates.isEmpty) return;
      _botCommandQuery = null;
      _botCommandCandidates = const [];
      if (rebuild && mounted) _updateState(() {});
      return;
    }
    if (!force &&
        _botCommandQuery?.start == query.start &&
        _botCommandQuery?.end == query.end &&
        _botCommandQuery?.query == query.query) {
      return;
    }
    _botCommandQuery = query;
    _botCommandCandidates = matchingBotCommands(vm.botCommands, query.query);
    if (rebuild && mounted) _updateState(() {});
  }

  void _sendBotCommandHint(BotCommandOption command) {
    if (!vm.sendCommand(command.targetedCommand)) return;
    _controller.clear();
    _focus.requestFocus();
    widget.onMessageSent();
  }

  void _insertBotCommandHint(BotCommandOption command) {
    final query = activeBotCommandQuery(
      _controller.text,
      _controller.selection,
    );
    if (query == null) return;
    final replacement = '${command.displayCommand} ';
    final text = _controller.text.replaceRange(
      query.start,
      query.end,
      replacement,
    );
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: query.start + replacement.length,
      ),
    );
    _focus.requestFocus();
  }

  void _queueInlineBotResults() {
    final invocation = _controller.startsWithIdBackedMention
        ? null
        : BotInlineInvocation.fromText(_controller.text);
    _inlineBotTimer?.cancel();
    final generation = ++_inlineBotGeneration;
    if (invocation == null) {
      if (_inlineBotLoading ||
          _inlineBotLoadingMore ||
          _inlineBotResults != null ||
          _inlineBot != null) {
        _inlineBotLoading = false;
        _inlineBotLoadingMore = false;
        _inlineBotResults = null;
        _inlineBot = null;
        if (mounted) _updateState(() {});
      }
      return;
    }
    if (!_inlineBotLoading ||
        _inlineBotLoadingMore ||
        _inlineBotResults != null) {
      _inlineBotLoading = true;
      _inlineBotLoadingMore = false;
      _inlineBotResults = null;
      if (mounted) _updateState(() {});
    }
    _inlineBotTimer = Timer(
      const Duration(milliseconds: 260),
      () => unawaited(_loadInlineBotResults(invocation, generation)),
    );
  }

  Future<void> _loadInlineBotResults(
    BotInlineInvocation invocation,
    int generation,
  ) async {
    try {
      var bot = _inlineBot;
      if (bot == null ||
          bot.username.toLowerCase() != invocation.username.toLowerCase()) {
        bot = await _botPlatform.capabilitiesForUsername(invocation.username);
      }
      if (!bot.inlineMode) throw StateError('BOT_INLINE_MODE_DISABLED');
      final location = bot.needsLocation ? await _inlineBotLocation() : null;
      if (bot.needsLocation && location == null) {
        throw StateError('BOT_INLINE_LOCATION_UNAVAILABLE');
      }
      final response = await _botPlatform.inlineResults(
        botUserId: bot.userId,
        chatId: vm.chatId,
        query: invocation.query,
        location: location,
      );
      final page = BotInlineResultsPage.fromJson(response);
      if (!mounted || generation != _inlineBotGeneration) return;
      _updateState(() {
        _inlineBot = bot;
        _inlineBotResults = page;
        _inlineBotLoading = false;
        _inlineBotLoadingMore = false;
      });
    } catch (_) {
      if (!mounted || generation != _inlineBotGeneration) return;
      _updateState(() {
        _inlineBotResults = null;
        _inlineBotLoading = false;
        _inlineBotLoadingMore = false;
      });
    }
  }

  Future<void> _loadMoreInlineBotResults() async {
    final page = _inlineBotResults;
    final bot = _inlineBot;
    if (page == null ||
        bot == null ||
        !page.hasMore ||
        _inlineBotLoading ||
        _inlineBotLoadingMore) {
      return;
    }
    final invocation = _controller.startsWithIdBackedMention
        ? null
        : BotInlineInvocation.fromText(_controller.text);
    if (invocation == null ||
        invocation.username.toLowerCase() != bot.username.toLowerCase()) {
      return;
    }
    final generation = _inlineBotGeneration;
    _updateState(() => _inlineBotLoadingMore = true);
    try {
      final location = bot.needsLocation ? await _inlineBotLocation() : null;
      final response = await _botPlatform.inlineResults(
        botUserId: bot.userId,
        chatId: vm.chatId,
        query: invocation.query,
        offset: page.nextOffset,
        location: location,
      );
      final nextPage = BotInlineResultsPage.fromJson(response);
      if (!mounted || generation != _inlineBotGeneration) return;
      final current = _inlineBotResults;
      if (current == null) return;
      _updateState(() {
        _inlineBotResults = current.mergeNextPage(nextPage);
        _inlineBotLoadingMore = false;
      });
    } catch (_) {
      if (!mounted || generation != _inlineBotGeneration) return;
      _updateState(() => _inlineBotLoadingMore = false);
    }
  }

  Future<void> _activateInlineResultsButton(
    BotInlineResultsButton button,
  ) async {
    final bot = _inlineBot;
    if (bot == null) return;
    if (button.isWebApp && button.webAppUrl.isNotEmpty) {
      final opened = await openTelegramMiniApp(
        context,
        chatId: vm.chatId,
        botUserId: bot.userId,
        url: button.webAppUrl,
        title: button.text,
      );
      if (!mounted) return;
      if (!opened) {
        showToast(context, AppStrings.t(AppStringKeys.miniAppCannotStart));
      }
      return;
    }
    final parameter = button.startParameter;
    if (parameter.isNotEmpty) {
      final link = 'https://t.me/${bot.username}?start=$parameter';
      await openLink(context, link);
    } else {
      await openLink(context, 'https://t.me/${bot.username}');
    }
  }

  Future<Map<String, dynamic>?> _inlineBotLocation() async {
    if (Platform.isMacOS) return null;
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    final value = await Geolocator.getCurrentPosition();
    return {
      '@type': 'location',
      'latitude': value.latitude,
      'longitude': value.longitude,
      'horizontal_accuracy': value.accuracy,
    };
  }

  void _syncFromVm() {
    // A notification that changed only the typing subtitle or the peer's
    // online status leaves the revision alone; nothing here renders either.
    final revision = vm.composerRevision;
    final revisionChanged = revision != _syncedComposerRevision;
    _syncedComposerRevision = revision;
    final focusTick = vm.composerFocusTick;
    final focusRequested = focusTick != _syncedComposerFocusTick;
    if (focusRequested) {
      _syncedComposerFocusTick = focusTick;
      _focusComposerForTranscriptReply();
    }
    final dismissTick = vm.composerDismissTick;
    final dismissRequested = dismissTick != _syncedComposerDismissTick;
    if (dismissRequested) {
      _syncedComposerDismissTick = dismissTick;
      _setPanel(_Panel.none);
    }
    final hadText = _hasText;
    final controllerTextBeforeSync = _controller.text;
    final previousVmState = _syncedVmState;
    _syncedVmState = _renderedVmState;
    final wasAiDraftEligible = _aiDraftEligible;
    final hadQuickReplyContext = _quickReplyContextVisible;
    final voicePanelWasClosed =
        (!_canSendVoiceNotes || vm.editingMessage != null) &&
        _panel == _Panel.voice;
    if (voicePanelWasClosed) {
      _cancelVoiceRecording();
      _desktopVoiceFocus.unfocus();
      _panel = _Panel.none;
    }
    final previousBotCommandQuery = _botCommandQuery;
    final previousBotCommandCandidates = _botCommandCandidates;
    final workingTargetId = _aiReplyWorkingTargetId;
    final workingUsesExplicitTarget = _aiReplyWorkingUsesExplicitTarget;
    final workingTargetFingerprint = _aiReplyWorkingTargetFingerprint;
    final workingContextSnapshot = _aiReplyWorkingContextSnapshot;
    if (workingTargetId != null &&
        (workingUsesExplicitTarget == null ||
            workingTargetFingerprint == null ||
            workingContextSnapshot == null ||
            !workingContextSnapshot.matches(vm) ||
            !_isCurrentAiReplyTarget(
              workingTargetId,
              usesExplicitTarget: workingUsesExplicitTarget,
              fingerprint: workingTargetFingerprint,
            ))) {
      _invalidateAiReplyGeneration(discardGeneratedDraft: true);
    }
    final editingMessage = vm.editingMessage;
    final editingStateChanged =
        _wasEditingMessage != (editingMessage != null) ||
        _syncedEditingMessageId != editingMessage?.id;
    if (editingStateChanged) {
      _wasEditingMessage = editingMessage != null;
      _syncedEditingMessageId = editingMessage?.id;
      _hideDesktopPopovers(rebuild: false);
      _panel = _Panel.none;
      _replyKeyboardVisible = false;
      _quickReplyContextVisible = false;
      _syncingControllerFromVm = true;
      try {
        _controller.setFormattedText(
          vm.composerFormattedDraft,
          vm.composerDraftEntities,
        );
      } finally {
        _syncingControllerFromVm = false;
      }
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focus.requestFocus();
        widget.onPanelGeometryChanged?.call();
      });
    } else {
      final composing = _controller.value.composing;
      final composingLocally = _focus.hasFocus || composing.isValid;
      if ((!composingLocally || focusRequested) &&
          vm.draft != _controller.text) {
        _controller.value = TextEditingValue(
          text: vm.draft,
          selection: TextSelection.collapsed(offset: vm.draft.length),
        );
      }
    }
    _hasText = _controller.text.trim().isNotEmpty;
    _aiDraftEligible = isTelegramAiDraftEligible(_controller.text);
    if (_hasText) _quickReplyContextVisible = false;
    if (vm.editingMessage == null) {
      _updateBotCommandSuggestions(force: true, rebuild: false);
    } else {
      _botCommandQuery = null;
      _botCommandCandidates = const [];
    }
    _requestInitialFocusIfReady();
    final localChanged =
        editingStateChanged ||
        voicePanelWasClosed ||
        hadText != _hasText ||
        controllerTextBeforeSync != _controller.text ||
        wasAiDraftEligible != _aiDraftEligible ||
        hadQuickReplyContext != _quickReplyContextVisible ||
        previousVmState != _syncedVmState ||
        !identical(previousBotCommandQuery, _botCommandQuery) ||
        !identical(previousBotCommandCandidates, _botCommandCandidates);
    if (mounted &&
        shouldRebuildComposerForVmUpdate(
          revisionChanged: revisionChanged,
          localChanged: localChanged,
          hasFocus: _focus.hasFocus,
        )) {
      _updateState(() {});
    }
  }

  AppIconData _inlineResultIcon(String type) => switch (type) {
    'inlineQueryResultAnimation' => HeroAppIcons.gif,
    'inlineQueryResultAudio' => HeroAppIcons.music,
    'inlineQueryResultContact' => HeroAppIcons.circleUser,
    'inlineQueryResultDocument' => HeroAppIcons.file,
    'inlineQueryResultGame' => HeroAppIcons.flash,
    'inlineQueryResultLocation' ||
    'inlineQueryResultVenue' => HeroAppIcons.locationDot,
    'inlineQueryResultPhoto' => HeroAppIcons.image,
    'inlineQueryResultSticker' => HeroAppIcons.solidFaceSmile,
    'inlineQueryResultVideo' => HeroAppIcons.video,
    'inlineQueryResultVoiceNote' => HeroAppIcons.microphone,
    _ => HeroAppIcons.font,
  };

  Future<void> _sendInlineBotResult(
    BotInlineResult result, {
    int? queryId,
    MessageSendConfiguration? configuration,
  }) async {
    final resolvedQueryId =
        queryId ??
        (result.queryId != 0
            ? result.queryId
            : (_inlineBotResults?.queryId ?? 0));
    if (resolvedQueryId == 0 || result.id.isEmpty) return;
    try {
      await _botPlatform.sendInlineResult(
        chatId: vm.chatId,
        queryId: resolvedQueryId,
        resultId: result.id,
        topicId: vm.forumTopicSendRef,
        replyTo: vm.replyToInput,
        options: configuration?.messageSendOptions(
          paidStarCount: vm.paidMessageStarCount,
        ),
      );
      if (!mounted) return;
      vm.setReply(null);
      _controller.clear();
      _focus.requestFocus();
      widget.onMessageSent();
    } catch (error) {
      _showBotPlatformFailure(error);
    }
  }

  Future<void> _sendInlineBotResultWithOptions(BotInlineResult result) async {
    final capturedQueryId = result.queryId != 0
        ? result.queryId
        : (_inlineBotResults?.queryId ?? 0);
    if (capturedQueryId == 0 || result.id.isEmpty) return;
    final configuration = await showMessageSendOptionsSheet(
      context,
      allowWhenOnline: vm.canSendWhenOnline,
      effects: vm.availableMessageEffects,
      onOpenScheduledMessages: _openScheduledMessages,
    );
    if (!mounted || configuration == null) return;
    await _sendInlineBotResult(
      result,
      queryId: capturedQueryId,
      configuration: configuration,
    );
  }

  void _showSenderPicker() {
    final options = vm.availableMessageSenders;
    if (options.length <= 1) return;
    showAppModalSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final c = context.colors;
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < options.length; i++) ...[
                  _senderOptionRow(options[i]),
                  if (i < options.length - 1)
                    const InsetDivider(leadingInset: 64),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _showBotMenu({bool forceMenu = false}) {
    final commands = vm.botCommands;
    final menu = vm.botMenu;
    final showTools = vm.peerIsBot || _guestQueries.isNotEmpty;
    if (!(menu?.isWebApp ?? false) && commands.isEmpty && !showTools) return;
    if (!forceMenu && (menu?.isWebApp ?? false)) {
      unawaited(_openBotMenuWebApp(menu!));
      return;
    }
    showAppModalSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final c = context.colors;
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                if (menu?.isWebApp ?? false) ...[
                  _botMenuRow(
                    icon: HeroAppIcons.bot,
                    title: menu!.actionTitle,
                    subtitle: '',
                    onTap: () {
                      Navigator.of(context).pop();
                      unawaited(_openBotMenuWebApp(menu));
                    },
                  ),
                  if (commands.isNotEmpty || showTools)
                    const InsetDivider(leadingInset: 56),
                ],
                for (var i = 0; i < commands.length; i++) ...[
                  _botMenuRow(
                    icon: HeroAppIcons.code,
                    title: '/${commands[i].command}',
                    subtitle: commands[i].description,
                    onTap: () {
                      Navigator.of(context).pop();
                      _insertBotCommand(commands[i].command);
                    },
                  ),
                  if (i < commands.length - 1 || showTools)
                    const InsetDivider(leadingInset: 56),
                ],
                if (showTools)
                  _botMenuRow(
                    icon: HeroAppIcons.gear,
                    title: AppStrings.t(AppStringKeys.chatInputBarBotTools),
                    subtitle: _guestQueries.isEmpty
                        ? 'Inline mode, topics, and automation'
                        : '${_guestQueries.length} guest ${_guestQueries.length == 1 ? 'query' : 'queries'} waiting',
                    onTap: () {
                      Navigator.of(context).pop();
                      unawaited(_showBotTools());
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openBotMenuWebApp(BotMenuInfo menu) async {
    final botUserId = vm.peerUserId;
    if (botUserId == null) {
      if (!menu.isLegacyMenuUrl && menu.webAppUrl.isNotEmpty) {
        await openLink(context, menu.webAppUrl);
      }
      return;
    }
    final opened = await openTelegramMiniApp(
      context,
      chatId: vm.chatId,
      botUserId: botUserId,
      url: menu.url,
      title: menu.actionTitle,
      menuWebApp: true,
    );
    if (!opened && mounted) {
      showToast(context, AppStrings.t(AppStringKeys.miniAppCannotStart));
    }
  }

  void _insertBotCommand(String command) {
    final text = '/${command.trim()} ';
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _focus.requestFocus();
  }

  Future<void> _showBotTools() async {
    BotPlatformCapabilities? capabilities;
    final botUserId = vm.peerUserId;
    if (vm.peerIsBot && botUserId != null) {
      try {
        capabilities = await _botPlatform.capabilitiesForUserId(botUserId);
      } catch (_) {
        // The menu still exposes account-bot and received guest-query tools.
      }
    }

    var currentAccountIsBot = false;
    try {
      currentAccountIsBot = await _botPlatform.currentAccountIsBot();
    } catch (_) {
      // User accounts don't need the bot update status action.
    }
    if (!mounted) return;

    await showAppModalSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final c = sheetContext.colors;
        final entries =
            <
              ({
                AppIconData icon,
                String title,
                String subtitle,
                VoidCallback onTap,
              })
            >[];
        final resolved = capabilities;
        if (resolved?.inlineMode == true &&
            resolved!.username.trim().isNotEmpty) {
          entries.add((
            icon: HeroAppIcons.at,
            title: AppStrings.t(AppStringKeys.chatInputBarUseInlineMode),
            subtitle: resolved.inlinePlaceholder.trim().isEmpty
                ? '@${resolved.username}'
                : resolved.inlinePlaceholder,
            onTap: () {
              Navigator.of(sheetContext).pop();
              _insertInlineBot(resolved);
            },
          ));
        }
        if (resolved?.hasTopics == true &&
            resolved?.allowsUsersToCreateTopics == true) {
          entries.add((
            icon: HeroAppIcons.comments,
            title: AppStrings.t(AppStringKeys.chatInputBarCreateBotTopic),
            subtitle: AppStrings.t(
              AppStringKeys.chatInputBarCreateBotTopicDetail,
            ),
            onTap: () {
              Navigator.of(sheetContext).pop();
              unawaited(_createBotTopic());
            },
          ));
        }
        if (resolved?.canManageBots == true) {
          entries.add((
            icon: HeroAppIcons.userPlus,
            title: AppStrings.t(AppStringKeys.chatInputBarCreateManagedBot),
            subtitle: AppStrings.t(
              AppStringKeys.chatInputBarCreateManagedBotDetailValue1,
              {'value1': resolved!.username},
            ),
            onTap: () {
              Navigator.of(sheetContext).pop();
              unawaited(_createManagedBot(resolved.userId));
            },
          ));
        }
        if (_guestQueries.isNotEmpty) {
          entries.add((
            icon: HeroAppIcons.comments,
            title: AppStrings.t(AppStringKeys.chatInputBarGuestQueries),
            subtitle: AppStrings.plural(
              AppStringKeys.chatInputBarGuestQueriesWaiting,
              _guestQueries.length,
            ),
            onTap: () {
              Navigator.of(sheetContext).pop();
              _showGuestQueries();
            },
          ));
        }
        if (currentAccountIsBot) {
          entries.add((
            icon: HeroAppIcons.gear,
            title: AppStrings.t(AppStringKeys.chatInputBarAutomationStatus),
            subtitle: AppStrings.t(
              AppStringKeys.chatInputBarAutomationStatusDetail,
            ),
            onTap: () {
              Navigator.of(sheetContext).pop();
              unawaited(_updateBotAutomationStatus());
            },
          ));
        }

        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            clipBehavior: Clip.antiAlias,
            child: entries.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      AppStrings.t(
                        AppStringKeys
                            .chatInputBarNoAdditionalToolsAreAvailableForThisBot,
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.textSecondary, fontSize: 14),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: entries.length,
                    separatorBuilder: (_, _) =>
                        const InsetDivider(leadingInset: 56),
                    itemBuilder: (_, index) {
                      final entry = entries[index];
                      return _botMenuRow(
                        icon: entry.icon,
                        title: entry.title,
                        subtitle: entry.subtitle,
                        onTap: entry.onTap,
                      );
                    },
                  ),
          ),
        );
      },
    );
  }

  void _insertInlineBot(BotPlatformCapabilities bot) {
    final clean = bot.username.replaceFirst('@', '').trim();
    if (clean.isEmpty) return;
    _inlineBot = bot;
    final text = '@$clean ';
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _focus.requestFocus();
  }

  Future<void> _createBotTopic() async {
    final name = await _promptBotText(
      title: AppStrings.t(AppStringKeys.chatInputBarCreateBotTopic),
      label: AppStrings.t(AppStringKeys.chatInputBarTopicName),
      actionLabel: AppStrings.t(AppStringKeys.chatInputBarCreateAction),
    );
    if (name == null) return;
    try {
      final result = await _botPlatform.createBotTopic(
        chatId: vm.chatId,
        name: name,
      );
      final topicId = forumTopicIdFromResult(result);
      await vm.loadForumTopics();
      if (!mounted) return;
      final onBotTopicCreated = widget.onBotTopicCreated;
      if (topicId != null && topicId != 0 && onBotTopicCreated != null) {
        onBotTopicCreated(topicId);
        return;
      }
      showToast(
        context,
        AppStrings.t(AppStringKeys.chatInputBarBotTopicCreated),
      );
    } catch (error) {
      _showBotPlatformFailure(error);
    }
  }

  Future<void> _createManagedBot(
    int managerBotUserId, {
    String suggestedName = '',
    String suggestedUsername = '',
  }) async {
    final name = await _promptBotText(
      title: AppStrings.t(AppStringKeys.chatInputBarCreateManagedBot),
      label: AppStrings.t(AppStringKeys.chatInputBarBotName),
      initialValue: suggestedName,
      actionLabel: AppStrings.t(AppStringKeys.chatInputBarNextAction),
    );
    if (name == null) return;
    final username = await _promptBotText(
      title: AppStrings.t(AppStringKeys.chatInputBarCreateManagedBot),
      label: AppStrings.t(AppStringKeys.editProfileUsername),
      initialValue: suggestedUsername,
      actionLabel: AppStrings.t(AppStringKeys.chatInputBarCreateAction),
    );
    if (username == null) return;
    try {
      await _botPlatform.createManagedBot(
        managerBotUserId: managerBotUserId,
        name: name,
        username: username,
      );
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.chatInputBarManagedBotCreated),
        );
      }
    } catch (error) {
      _showBotPlatformFailure(error);
    }
  }

  void _showGuestQueries() {
    showAppModalSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final c = sheetContext.colors;
        return SafeArea(
          child: Container(
            constraints: const BoxConstraints(maxHeight: 420),
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _guestQueries.length,
              separatorBuilder: (_, _) => const InsetDivider(leadingInset: 56),
              itemBuilder: (_, index) {
                final query = _guestQueries[index];
                return _botMenuRow(
                  icon: HeroAppIcons.message,
                  title: _guestQueryPreview(query),
                  subtitle:
                      '${query.referenceMessages.length} reference ${query.referenceMessages.length == 1 ? 'message' : 'messages'}',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(_replyToGuestQuery(query));
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  String _guestQueryPreview(BotGuestQuery query) {
    try {
      final content = query.message.obj('content');
      final text = content == null ? '' : TDParse.messageText(content).trim();
      if (text.isNotEmpty) return text;
    } catch (_) {
      // Fall back to the stable guest query identifier below.
    }
    return AppStrings.t(AppStringKeys.chatInputBarGuestQueryValue1, {
      'value1': query.id,
    });
  }

  Future<void> _replyToGuestQuery(BotGuestQuery query) async {
    final reply = await _promptBotText(
      title: AppStrings.t(AppStringKeys.chatInputBarAnswerGuestQuery),
      label: AppStrings.t(AppStringKeys.chatInputBarReply),
      actionLabel: AppStrings.t(AppStringKeys.chatInputBarSendAction),
    );
    if (reply == null) return;
    try {
      await _botPlatform.answerGuestQuery(
        guestQueryId: query.id,
        result: {
          '@type': 'inputInlineQueryResultArticle',
          'id': 'guest_${query.id}',
          'url': '',
          'title': 'Reply',
          'description': reply,
          'thumbnail_url': '',
          'thumbnail_width': 0,
          'thumbnail_height': 0,
          'reply_markup': null,
          'input_message_content': {
            '@type': 'inputMessageText',
            'text': {
              '@type': 'formattedText',
              'text': reply,
              'entities': <Map<String, dynamic>>[],
            },
            'link_preview_options': null,
            'clear_draft': false,
          },
        },
      );
      if (!mounted) return;
      _updateState(
        () => _guestQueries.removeWhere((item) => item.id == query.id),
      );
      showToast(
        context,
        AppStrings.t(AppStringKeys.chatInputBarGuestQueryAnswered),
      );
    } catch (error) {
      _showBotPlatformFailure(error);
    }
  }

  Future<void> _updateBotAutomationStatus() async {
    final pendingText = await _promptBotText(
      title: AppStrings.t(AppStringKeys.chatInputBarAutomationStatus),
      label: AppStrings.t(AppStringKeys.chatInputBarPendingUpdateCount),
      initialValue: '0',
      actionLabel: AppStrings.t(AppStringKeys.chatInputBarNextAction),
      keyboardType: TextInputType.number,
    );
    if (pendingText == null) return;
    final pendingCount = int.tryParse(pendingText);
    if (pendingCount == null || pendingCount < 0) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.chatInputBarEnterANonNegativeUpdateCount),
        );
      }
      return;
    }
    final errorMessage = await _promptBotText(
      title: AppStrings.t(AppStringKeys.chatInputBarAutomationStatus),
      label: AppStrings.t(AppStringKeys.chatInputBarErrorMessageOptional),
      actionLabel: AppStrings.t(AppStringKeys.chatInputBarReportAction),
      allowEmpty: true,
    );
    if (errorMessage == null) return;
    try {
      await _botPlatform.updateBotAutomationStatus(
        pendingUpdateCount: pendingCount,
        errorMessage: errorMessage,
      );
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.chatInputBarAutomationStatusUpdated),
        );
      }
    } catch (error) {
      _showBotPlatformFailure(error);
    }
  }

  Future<String?> _promptBotText({
    required String title,
    required String label,
    required String actionLabel,
    String initialValue = '',
    bool allowEmpty = false,
    TextInputType? keyboardType,
  }) => showAppTextEntryDialog(
    context,
    title: title,
    label: label,
    actionLabel: actionLabel,
    initial: initialValue,
    allowEmpty: allowEmpty,
    keyboardType: keyboardType,
  );

  void _showBotPlatformFailure(Object error) {
    if (!mounted) return;
    final detail = error is TdError
        ? error.message
        : AppStrings.t(AppStringKeys.chatInputBarActionFailed);
    showToast(context, detail);
  }

  _ReplyKeyboard? _activeReplyKeyboard() {
    for (final message in vm.messages.reversed) {
      // Almost every message has no buttons; skipping them keeps this
      // per-build whole-transcript walk allocation-free.
      if (message.buttonRows.isEmpty) continue;
      final rows = message.buttonRows
          .map((row) => row.where((button) => button.isReplyKeyboard).toList())
          .where((row) => row.isNotEmpty)
          .toList();
      if (rows.isNotEmpty) return _ReplyKeyboard(message: message, rows: rows);
    }
    return null;
  }

  MessageButton? _webAppButton(_ReplyKeyboard? keyboard) {
    if (keyboard == null) return null;
    for (final row in keyboard.rows) {
      for (final button in row) {
        if (button.isWebApp && (button.url?.isNotEmpty ?? false)) {
          return button;
        }
      }
    }
    return null;
  }

  Future<void> _openReplyKeyboardWebApp(
    _ReplyKeyboard keyboard,
    MessageButton button,
  ) async {
    final url = button.url;
    if (url == null || url.isEmpty) return;
    final botUserId = await vm.webAppBotUserId(keyboard.message);
    if (!mounted) return;
    if (botUserId == null) {
      showToast(context, AppStrings.t(AppStringKeys.miniAppCannotStart));
      return;
    }
    final opened = await openTelegramMiniApp(
      context,
      chatId: vm.chatId,
      botUserId: botUserId,
      url: url,
      title: button.text,
      keyboardButtonText: button.text,
    );
    if (!opened && mounted) {
      showToast(context, AppStrings.t(AppStringKeys.miniAppCannotStart));
    }
  }

  void _pressReplyKeyboardButton(
    _ReplyKeyboard keyboard,
    MessageButton button,
  ) {
    if (button.isWebApp) {
      unawaited(_openReplyKeyboardWebApp(keyboard, button));
      return;
    }
    if (button.type == 'keyboardButtonTypeText') {
      vm.sendKeyboardButtonText(button.text);
      widget.onMessageSent();
      return;
    }
    if (button.type == 'keyboardButtonTypeRequestManagedBot') {
      final managerBotUserId = vm.peerUserId;
      if (managerBotUserId != null) {
        unawaited(
          _createManagedBot(
            managerBotUserId,
            suggestedName: button.suggestedName ?? '',
            suggestedUsername: button.suggestedUsername ?? '',
          ),
        );
        return;
      }
    }
    showToast(context, AppStringKeys.chatButtonUnsupported);
  }

  void _toggleReplyKeyboard() {
    _updateState(() {
      _replyKeyboardVisible = !_replyKeyboardVisible;
      if (_replyKeyboardVisible) {
        _panel = _Panel.none;
        _quickReplyContextVisible = false;
      }
    });
    widget.onPanelGeometryChanged?.call();
    if (_replyKeyboardVisible) _focus.unfocus();
  }

  void _handleEmptyInputTap() {
    // With a voice draft waiting, the tap starts its caption.
    if (_hasText ||
        _voiceDraft != null ||
        !_canUseQuickReplies ||
        _replyKeyboardVisible) {
      return;
    }
    if (_quickReplyContextVisible) {
      _updateState(() => _quickReplyContextVisible = false);
      return;
    }
    if (_quickRepliesLoaded) {
      if (_quickReplies.isEmpty) return;
      _focus.unfocus();
      _updateState(() => _quickReplyContextVisible = true);
      return;
    }
    unawaited(_loadQuickReplies(userInitiated: true));
  }
}
