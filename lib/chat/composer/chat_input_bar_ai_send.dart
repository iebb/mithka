part of 'chat_input_bar.dart';

extension _ChatInputBarAiSend on _ChatInputBarState {
  void _scheduleKeyboardSend() {
    if (_keyboardSendScheduled) return;
    _keyboardSendScheduled = true;
    scheduleMicrotask(() => unawaited(_sendScheduledKeyboardText()));
  }

  Future<void> _sendScheduledKeyboardText() async {
    try {
      if (mounted) await _sendCurrentText();
    } finally {
      _keyboardSendScheduled = false;
    }
  }

  Future<void> _sendCurrentText() async {
    if (_aiReplyWorkingTargetId != null) return;
    if (vm.editingMessage != null) {
      final (text, entities) = _controller.toFormatted();
      if (!vm.editingMessageUsesCaption && text.trim().isEmpty) {
        showToast(context, AppStringKeys.chatMessageRequired);
        return;
      }
      try {
        final edited = await vm.submitMessageEdit(text, entities: entities);
        if (!mounted || !edited) return;
        _focus.requestFocus();
      } catch (error) {
        if (mounted) showToast(context, '$error');
      }
      return;
    }
    // A pending forward rides the send button first (the reference client parity: the
    // preview panel's send commits the forward; any typed text follows as a
    // normal message).
    if (vm.pendingForward != null) {
      final canAttemptSend = await vm.prepareMessageSend();
      if (!mounted || !canAttemptSend) return;
      try {
        await vm.sendPendingForward();
        if (!mounted) return;
        widget.onMessageSent();
        final plan = vm.protectedForwardLastPlan;
        if (plan != null && plan.skippedIds.isNotEmpty) {
          showToast(
            context,
            AppStrings.t(AppStringKeys.keptForwardCopyPartToast, {
              'value1': plan.copiedCount,
              'value2': plan.skippedIds.length,
            }),
          );
        }
        if (_controller.text.trim().isNotEmpty) {
          await _sendCurrentText();
        } else {
          _focus.requestFocus();
        }
      } catch (error) {
        if (mounted) _showForwardFailureFromComposer(error);
      }
      return;
    }
    if (_voiceDraft != null) {
      await _sendVoiceDraft();
      return;
    }
    if (_pendingClipboardAttachments.isNotEmpty) {
      await _sendPendingClipboardAttachments();
      return;
    }
    if (_controller.text.trim().isEmpty) return;
    final canAttemptSend = await vm.prepareMessageSend();
    if (!mounted || !canAttemptSend) return;
    final (text, entities) = _controller.toFormatted();
    final lengthTier = telegramMessageLengthTier(text);
    if (lengthTier == TelegramMessageLengthTier.exceeded) {
      showToast(
        context,
        AppStringKeys.composerMessageExceedsRichTextLimit.l10n(context),
      );
      return;
    }
    if (lengthTier == TelegramMessageLengthTier.rich) {
      final sendAsRichText = await _confirmLongMessageAsRichText();
      if (!mounted || !sendAsRichText) return;
      if (await _richTextSendMode() == null) {
        if (!mounted) return;
        // This length cannot travel as a plain message, so a declined or
        // failed relay setup keeps the draft and says why instead of dropping
        // the text silently.
        final configured = await _configureRichMessageRelay();
        if (!mounted) return;
        if (!configured) {
          showToast(
            context,
            AppStringKeys.richTextRelayPremiumOrBotRequired.l10n(context),
          );
          return;
        }
      }
      if (vm.requiresPaidMessage) {
        final ok = await _confirmPaidMessageSend();
        if (!mounted || !ok) return;
      }
      final inline = formattedTextToRichInlineHtml(
        text,
        entities,
      ).replaceAll('\n', '<br>');
      final html = '<p>$inline</p>';
      await _sendRichTextResult(
        RichTextComposerResult(
          text: text,
          entities: entities,
          attachments: const [],
          segments: [RichMessageSendSegment.html(html)],
        ),
      );
      return;
    }
    if (vm.requiresPaidMessage) {
      final ok = await _confirmPaidMessageSend();
      if (!mounted || !ok) return;
    }
    final sent = await vm.sendFormatted(text, entities);
    if (!mounted || !sent) return;
    widget.onMessageSent();
    _controller.clear();
    _focus.requestFocus();
  }

  Future<void> _sendPendingClipboardAttachments({
    MessageSendConfiguration sendConfiguration =
        const MessageSendConfiguration(),
  }) async {
    if (_pendingClipboardAttachments.isEmpty) return;
    final canAttemptSend = await vm.prepareMessageSend();
    if (!mounted || !canAttemptSend) return;
    final (caption, entities) = _controller.toFormatted();
    if (telegramMessageLengthTier(caption) ==
        TelegramMessageLengthTier.exceeded) {
      showToast(
        context,
        AppStringKeys.composerMessageExceedsRichTextLimit.l10n(context),
      );
      return;
    }
    if (vm.requiresPaidMessage) {
      final ok = await _confirmPaidMessageSend();
      if (!mounted || !ok) return;
    }
    final attachments = List<OutgoingAttachment>.unmodifiable(
      _pendingClipboardAttachments,
    );
    try {
      await vm.sendAttachments(
        attachments,
        caption: caption,
        captionEntities: entities,
        sendConfiguration: sendConfiguration,
      );
    } catch (error) {
      if (mounted) showToast(context, '$error');
      return;
    }
    if (!mounted) return;
    _updateState(_pendingClipboardAttachments.clear);
    widget.onPanelGeometryChanged?.call();
    widget.onMessageSent();
    _controller.clear();
    _focus.requestFocus();
  }

  Future<void> _openTelegramAiEditor() async {
    if (!vm.canUseAiComposition || _controller.text.trim().isEmpty) return;
    if (_usesNativeDesktopComposer(context)) {
      try {
        await vm.persistComposerDraft();
      } catch (error) {
        if (mounted) showToast(context, error.toString());
        return;
      }
      if (!mounted) return;
      await _openDesktopComposerPicker(
        DesktopUtilityWindowKind.aiEditor,
        AppStringKeys.telegramAiEditorRewriteTitle.l10n(context),
      );
      return;
    }
    final (text, entities) = _controller.toFormatted();
    final result = await Navigator.of(context).push<TelegramAiFormattedText>(
      MaterialPageRoute(
        builder: (_) => TelegramAiEditorView(
          service: vm.telegramAi,
          source: TelegramAiFormattedText(text: text, entities: entities),
        ),
      ),
    );
    if (!mounted || result == null) return;
    _controller.setFormattedText(result.text, result.entities);
    _focus.requestFocus();
  }

  bool _isAiReplyTargetEligible(ChatMessage target) {
    return !vm.isSecretChat &&
        !vm.hasProtectedContent &&
        !target.isService &&
        !target.isContentRestricted &&
        !target.blockedByUser &&
        target.text.trim().isNotEmpty;
  }

  bool _canOfferAiReply(ChatMessage target, AiSettingsController? settings) {
    if (settings?.initialized != true || !_isAiReplyTargetEligible(target)) {
      return false;
    }
    return switch (settings!.replyModelCandidate.kind) {
      AiModelCandidateKind.telegramCocoon =>
        vm.aiCapabilities?.replySupported == true,
      AiModelCandidateKind.applePcc ||
      AiModelCandidateKind.appleOnDevice ||
      AiModelCandidateKind.server => settings.isConfiguredForFeature(
        AiFeature.reply,
      ),
    };
  }

  ChatMessage? _contextualAiReplyTarget() {
    final anchorId = vm.anchoredHistory ? vm.historyAnchorMessageId : null;
    if (anchorId != null) {
      final anchor = vm.messages
          .where((message) => message.id == anchorId)
          .firstOrNull;
      if (anchor != null) {
        final safeAnchor =
            anchor.id > 0 &&
            !anchor.isService &&
            !anchor.isContentRestricted &&
            !anchor.blockedByUser &&
            anchor.text.trim().isNotEmpty;
        if (safeAnchor && (!anchor.isOutgoing || vm.isGroup)) return anchor;
        if (!vm.isGroup) return null;
      }
    }
    ChatMessage? groupFallback;
    for (final message in vm.messages.reversed) {
      if (message.isService) continue;
      final safeText =
          message.id > 0 &&
          !message.isContentRestricted &&
          !message.blockedByUser &&
          message.text.trim().isNotEmpty;
      if (safeText) {
        groupFallback ??= message;
        if (!message.isOutgoing) return message;
      }
      // In a busy group, keep looking for the newest participant message even
      // if the account owner or an ineligible message was posted afterwards.
      // Private chats retain the stronger "already answered" behavior.
      if (!vm.isGroup) {
        return null;
      }
    }
    // Group and channel composers also support drafting the next message when
    // the visible context only contains posts sent by the account owner or the
    // currently selected sender identity.
    return groupFallback;
  }

  ChatMessage? _currentAiReplyTarget() =>
      vm.replyTo ?? _contextualAiReplyTarget();

  bool _isCurrentAiReplyTarget(
    int targetMessageId, {
    required bool usesExplicitTarget,
    required int fingerprint,
  }) {
    final ChatMessage? current;
    if (usesExplicitTarget) {
      current = vm.replyTo;
    } else {
      if (vm.replyTo != null) return false;
      current = _contextualAiReplyTarget();
    }
    return current?.id == targetMessageId &&
        _aiReplyTargetFingerprint(current!) == fingerprint;
  }

  int _aiReplyTargetFingerprint(ChatMessage target) => Object.hash(
    target.id,
    target.isOutgoing,
    target.isService,
    target.isContentRestricted,
    target.blockedByUser,
    target.senderName,
    target.text,
  );

  bool _isCurrentAiReplyTargetWithoutFingerprint(
    ChatMessage target, {
    required bool usesExplicitTarget,
  }) {
    final fingerprint = _aiReplyTargetFingerprint(target);
    return _isCurrentAiReplyTarget(
      target.id,
      usesExplicitTarget: usesExplicitTarget,
      fingerprint: fingerprint,
    );
  }

  void _invalidateAiReplyGeneration({
    bool discardGeneratedDraft = false,
    bool clearProgress = false,
  }) {
    final shouldClearProgress = clearProgress || discardGeneratedDraft;
    if (_aiReplyWorkingTargetId == null &&
        _activeAiReplyProvider == null &&
        (!shouldClearProgress || _aiReplyProgressPhases.isEmpty)) {
      return;
    }
    _aiReplyGeneration++;
    _aiReplyWorkingTargetId = null;
    _aiReplyWorkingUsesExplicitTarget = null;
    _aiReplyWorkingTargetFingerprint = null;
    _aiReplyWorkingContextSnapshot = null;
    final activeProvider = _activeAiReplyProvider;
    _activeAiReplyProvider = null;
    if (activeProvider case final HostedAiReplyProvider hosted) {
      hosted.close();
    }
    if (discardGeneratedDraft && _controller.text.isNotEmpty) {
      _applyingAiReplyDraft = true;
      try {
        _controller.setFormattedText('', const []);
      } finally {
        _applyingAiReplyDraft = false;
      }
    }
    if (shouldClearProgress) {
      _aiReplyProgressPhases = const [];
      _aiReplyProgressExpanded = false;
    }
    if (mounted) _updateState(() {});
  }

  void _recordAiReplyProgress(
    AiReplyProgressPhase phase, {
    required int generation,
  }) {
    if (!mounted || generation != _aiReplyGeneration) return;
    if (_aiReplyProgressPhases.contains(phase)) return;
    final wasEmpty = _aiReplyProgressPhases.isEmpty;
    _updateState(() {
      _aiReplyProgressPhases = [..._aiReplyProgressPhases, phase];
    });
    if (wasEmpty) _notifyComposerGeometryChanged();
  }

  void _notifyComposerGeometryChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onPanelGeometryChanged?.call();
    });
  }

  bool _isAiReplyGenerationCurrent({
    required int generation,
    required ChatViewModel requestVm,
    required AiSettingsController settings,
    required String modelCandidateId,
    required ChatMessage target,
    required int targetMessageId,
    required bool usesExplicitTarget,
    required int targetFingerprint,
    required int draftRevision,
    required _AiReplyContextSnapshot contextSnapshot,
  }) =>
      mounted &&
      generation == _aiReplyGeneration &&
      identical(vm, requestVm) &&
      settings.replyModelCandidate.id == modelCandidateId &&
      (widget.aiReplyHistoryLoader != null || vm.canShareAiReplyContext) &&
      _canOfferAiReply(target, settings) &&
      _isCurrentAiReplyTarget(
        targetMessageId,
        usesExplicitTarget: usesExplicitTarget,
        fingerprint: targetFingerprint,
      ) &&
      contextSnapshot.matches(vm) &&
      _composerRevision == draftRevision;

  bool _applyAiReplyDraft(
    TelegramAiFormattedText draft, {
    required int generation,
    required ChatViewModel requestVm,
    required AiSettingsController settings,
    required String modelCandidateId,
    required ChatMessage target,
    required int targetMessageId,
    required bool usesExplicitTarget,
    required int targetFingerprint,
    required int draftRevision,
    required _AiReplyContextSnapshot contextSnapshot,
  }) {
    if (!_isAiReplyGenerationCurrent(
      generation: generation,
      requestVm: requestVm,
      settings: settings,
      modelCandidateId: modelCandidateId,
      target: target,
      targetMessageId: targetMessageId,
      usesExplicitTarget: usesExplicitTarget,
      targetFingerprint: targetFingerprint,
      draftRevision: draftRevision,
      contextSnapshot: contextSnapshot,
    )) {
      if (mounted && generation == _aiReplyGeneration) {
        _invalidateAiReplyGeneration(
          discardGeneratedDraft: _composerRevision == draftRevision,
        );
      }
      return false;
    }
    _applyingAiReplyDraft = true;
    try {
      _controller.setFormattedText(draft.text, draft.entities);
    } finally {
      _applyingAiReplyDraft = false;
    }
    return true;
  }

  Future<bool> _revealCompletedAiReply(
    TelegramAiFormattedText result, {
    required bool Function(TelegramAiFormattedText draft) applyDraft,
  }) async {
    final characters = result.text.characters.toList(growable: false);
    if (characters.length < 2) return true;

    // Telegram Cocoon and Apple's native model bridge currently return one
    // completed value rather than transport-level deltas. Reveal those replies
    // through the same composer path so every AI Reply provider has consistent
    // incremental input feedback. Keep the animation bounded for long replies
    // and apply the provider's formatted entities only with the final value.
    const maximumFrames = 48;
    const frameDuration = Duration(milliseconds: 12);
    final charactersPerFrame = math.max(
      1,
      (characters.length / maximumFrames).ceil(),
    );
    final buffer = StringBuffer();
    var offset = 0;
    while (offset < characters.length) {
      final end = math.min(characters.length, offset + charactersPerFrame);
      buffer.writeAll(characters.getRange(offset, end));
      offset = end;
      if (offset == characters.length) break;
      if (!applyDraft(TelegramAiFormattedText(text: buffer.toString()))) {
        return false;
      }
      await Future<void>.delayed(frameDuration);
    }
    return true;
  }

  Future<void> _generateAiReply(
    ChatMessage target, {
    String? requiredModelCandidateId,
  }) async {
    if (_aiReplyWorkingTargetId == target.id) return;
    final usesExplicitTarget = vm.replyTo?.id == target.id;
    if (!_isCurrentAiReplyTargetWithoutFingerprint(
      target,
      usesExplicitTarget: usesExplicitTarget,
    )) {
      showToast(context, AppStringKeys.aiReplyStale.l10n(context));
      return;
    }
    final settings = context.read<AiSettingsController?>();
    if (!_canOfferAiReply(target, settings)) {
      showToast(context, AppStringKeys.aiReplyUnavailable.l10n(context));
      return;
    }

    final configuration = settings!.configurationForFeature(AiFeature.reply);
    final modelCandidateId = configuration.candidate.id;
    if (requiredModelCandidateId != null &&
        modelCandidateId != requiredModelCandidateId) {
      showToast(context, AppStringKeys.aiReplyUnavailable.l10n(context));
      return;
    }
    final (draftText, _) = _controller.toFormatted();
    final AiReplyRequest request;
    try {
      request = AiReplyRequest.fromChatMessages(
        chatTitle: vm.peerTitle,
        currentUserName: vm.meName,
        currentUserId: vm.meId,
        currentUserUsernames: vm.meUsernames,
        target: target,
        visibleMessages: vm.messages,
        isGroupChat: vm.isGroup,
        currentDraft: draftText,
        guidance: settings.aiReplyPrompt,
        outputLanguageCode: Localizations.localeOf(context).toLanguageTag(),
        contextWindowTokens: configuration.contextWindowTokens,
        historyLoader: widget.aiReplyHistoryLoader ?? vm.loadAiReplyContext,
      );
    } on AiReplyException catch (error) {
      showToast(context, error.message);
      return;
    }

    AiReplyProvider? provider;
    if (widget.aiReplyGenerator == null &&
        widget.aiReplyStreamingGenerator == null) {
      switch (configuration.candidate.kind) {
        case AiModelCandidateKind.telegramCocoon:
          provider = TelegramCocoonAiReplyProvider(service: vm.telegramAi);
        case AiModelCandidateKind.applePcc:
          provider = AppleAiReplyProvider(api: ApplePccApi());
        case AiModelCandidateKind.appleOnDevice:
          provider = AppleAiReplyProvider(
            api: ApplePccApi(),
            model: AppleAiModel.onDevice,
          );
        case AiModelCandidateKind.server:
          final endpoint = configuration.endpoint;
          if (endpoint == null || configuration.model.isEmpty) {
            showToast(context, AppStringKeys.aiReplyUnavailable.l10n(context));
            return;
          }
          provider = HostedAiReplyProvider(
            endpoint: endpoint,
            model: configuration.model,
            endpointStyle: configuration.endpointStyle,
            apiKey: configuration.apiKey,
          );
      }
    }

    final targetMessageId = target.id;
    final targetFingerprint = _aiReplyTargetFingerprint(target);
    final requestVm = vm;
    final draftRevision = _composerRevision;
    final initialContextSnapshot = _AiReplyContextSnapshot.capture(
      requestVm,
      request,
    );
    final generation = ++_aiReplyGeneration;
    _updateState(() {
      _aiReplyWorkingTargetId = targetMessageId;
      _aiReplyWorkingUsesExplicitTarget = usesExplicitTarget;
      _aiReplyWorkingTargetFingerprint = targetFingerprint;
      _aiReplyWorkingContextSnapshot = initialContextSnapshot;
      _activeAiReplyProvider = provider;
      _aiReplyProgressPhases = const [
        AiReplyProgressPhase.readingRecentMessages,
      ];
      _aiReplyProgressExpanded = false;
    });
    _notifyComposerGeometryChanged();
    try {
      var groundedRequest = request;
      try {
        groundedRequest = await request.withEarlierContext();
      } on AiReplyPrivacyException {
        rethrow;
      } catch (_) {
        groundedRequest = request.copyWith(contextExpanded: true);
      }
      if (!_isAiReplyGenerationCurrent(
        generation: generation,
        requestVm: requestVm,
        settings: settings,
        modelCandidateId: modelCandidateId,
        target: target,
        targetMessageId: targetMessageId,
        usesExplicitTarget: usesExplicitTarget,
        targetFingerprint: targetFingerprint,
        draftRevision: draftRevision,
        contextSnapshot: initialContextSnapshot,
      )) {
        return;
      }
      final contextSnapshot = _AiReplyContextSnapshot.capture(
        requestVm,
        groundedRequest,
      );
      _aiReplyWorkingContextSnapshot = contextSnapshot;
      bool applyDraft(TelegramAiFormattedText draft) => _applyAiReplyDraft(
        draft,
        generation: generation,
        requestVm: requestVm,
        settings: settings,
        modelCandidateId: modelCandidateId,
        target: target,
        targetMessageId: targetMessageId,
        usesExplicitTarget: usesExplicitTarget,
        targetFingerprint: targetFingerprint,
        draftRevision: draftRevision,
        contextSnapshot: contextSnapshot,
      );

      void onDraft(TelegramAiFormattedText draft) {
        applyDraft(draft);
      }

      void onProgress(AiReplyProgressPhase phase) {
        _recordAiReplyProgress(phase, generation: generation);
      }

      late final TelegramAiFormattedText result;
      var revealCompletedResult = false;
      final streamingGenerator = widget.aiReplyStreamingGenerator;
      if (streamingGenerator != null) {
        result = await streamingGenerator(
          groundedRequest,
          onDraft: onDraft,
          onProgress: onProgress,
        );
      } else if (widget.aiReplyGenerator case final generator?) {
        result = await generator(groundedRequest);
        revealCompletedResult = true;
      } else if (provider case final StreamingAiReplyProvider streaming) {
        result = await streaming.generateStreaming(
          groundedRequest,
          onDraft: onDraft,
          onProgress: onProgress,
        );
      } else {
        result = await provider!.generate(groundedRequest);
        revealCompletedResult = true;
      }
      onProgress(AiReplyProgressPhase.writingReply);
      if (revealCompletedResult &&
          !await _revealCompletedAiReply(result, applyDraft: applyDraft)) {
        return;
      }
      if (!applyDraft(result)) {
        return;
      }
      _focus.requestFocus();
    } catch (error) {
      if (mounted && generation == _aiReplyGeneration) {
        _updateState(() {
          _aiReplyProgressPhases = const [];
          _aiReplyProgressExpanded = false;
        });
        _notifyComposerGeometryChanged();
        showToast(
          context,
          error is AiReplyException ? error.message : error.toString(),
        );
      }
      return;
    } finally {
      if (provider case final HostedAiReplyProvider hosted) hosted.close();
      if (identical(_activeAiReplyProvider, provider)) {
        _activeAiReplyProvider = null;
      }
      if (mounted && generation == _aiReplyGeneration) {
        _updateState(() {
          _aiReplyWorkingTargetId = null;
          _aiReplyWorkingUsesExplicitTarget = null;
          _aiReplyWorkingTargetFingerprint = null;
          _aiReplyWorkingContextSnapshot = null;
        });
      }
    }
  }

  Future<void> _showTextSendOptions() async {
    // The options apply to what waited when they were opened: a chat switch,
    // or a voice draft sent, deleted or recorded meanwhile, drops them.
    final target = vm;
    final draft = _voiceDraft;
    MessageSendConfiguration? configuration;
    if (_usesNativeDesktopComposer(context)) {
      _hideDesktopPopovers();
      final target = _desktopSendOptionsTargetKey.currentContext
          ?.findRenderObject();
      final anchorTop = target is RenderBox && target.hasSize
          ? target.localToGlobal(Offset.zero).dy
          : MediaQuery.sizeOf(context).height;
      final menu = showMessageSendOptionsContextMenu(
        context,
        anchor: _desktopSendOptionsLink,
        maxHeight: math.max(80, anchorTop - 12),
        allowWhenOnline: widget.vm.canSendWhenOnline,
        effects: widget.vm.availableMessageEffects,
        onOpenScheduledMessages: _openScheduledMessages,
      );
      _desktopSendOptionsMenu = menu;
      configuration = await menu.result;
      if (identical(_desktopSendOptionsMenu, menu)) {
        _desktopSendOptionsMenu = null;
      }
    } else {
      if (draft?.sending ?? false) return;
      configuration = await showMessageSendOptionsSheet(
        context,
        allowWhenOnline: target.canSendWhenOnline,
        // Telegram takes View Once and self-destructing voice messages only
        // in one-on-one chats with a person.
        voiceOptions: draft != null && target.canSendSelfDestructingMedia,
        effects: target.availableMessageEffects,
        onOpenScheduledMessages: _openScheduledMessages,
      );
    }
    if (!mounted || configuration == null || !identical(target, vm)) return;
    if (!identical(draft, _voiceDraft)) return;
    if (draft != null && vm.editingMessage == null) {
      await _sendVoiceDraft(sendConfiguration: configuration);
      return;
    }
    if (_pendingClipboardAttachments.isNotEmpty) {
      await _sendPendingClipboardAttachments(sendConfiguration: configuration);
      return;
    }
    widget.vm.useNextSendConfiguration(configuration);
    await _sendCurrentText();
  }

  void _openScheduledMessages() {
    if (_usesNativeDesktopComposer(context)) {
      unawaited(
        _openDesktopComposerPicker(
          DesktopUtilityWindowKind.scheduledMessages,
          AppStrings.t(AppStringKeys.messageSendOptionsScheduledMessages),
        ),
      );
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ScheduledMessagesView(
            chatId: widget.vm.chatId,
            chatTitle: widget.vm.peerTitle,
          ),
        ),
      );
    });
  }

  Future<void> _openRichTextComposer() async {
    // Every account can compose rich text; whether it can be delivered as a
    // rich message is resolved at send time, so the editor itself is never
    // gated behind the relay bot.
    if (!mounted) return;
    if (_usesNativeDesktopComposer(context)) {
      try {
        await vm.persistComposerDraft();
      } catch (error) {
        if (mounted) showToast(context, error.toString());
        return;
      }
      if (!mounted) return;
      await _openDesktopComposerPicker(
        DesktopUtilityWindowKind.richTextComposer,
        AppStringKeys.composerRichTextMessageTitle.l10n(context),
      );
      return;
    }
    final (initialText, initialEntities) = _controller.toFormatted();
    final result = await showRichTextComposerSheet(
      context,
      initialText: initialText,
      initialEntities: initialEntities,
      title: AppStringKeys.composerRichTextMessageTitle,
      submitText: AppStringKeys.composerSend,
    );
    if (result == null || !mounted) return;
    if (result.text.trim().isEmpty &&
        result.attachments.isEmpty &&
        result.segments.isEmpty) {
      return;
    }
    final canAttemptSend = await vm.prepareMessageSend();
    if (!mounted || !canAttemptSend) return;
    if (vm.requiresPaidMessage) {
      final ok = await _confirmPaidMessageSend();
      if (!mounted || !ok) return;
    }
    await _sendRichTextResult(result);
  }

  Future<bool> _confirmPaidMessageSend() {
    return confirmDialog(
      context,
      title: AppStrings.t(AppStringKeys.composerSendPaidMessageQuestion),
      message: AppStrings.t(AppStringKeys.composerPaidMessageCost, {
        'value1': vm.paidMessageStarCount,
      }),
      confirmText: AppStrings.t(AppStringKeys.composerSend),
    );
  }

  Future<bool> _confirmLongMessageAsRichText() async {
    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: AppStringKeys.countryPickerCancel.l10n(context),
      barrierColor: Colors.black.withValues(alpha: 0.42),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, _, _) => _LongMessageRichTextPrompt(
        onCancel: () => Navigator.of(dialogContext).pop(false),
        onConfirm: () => Navigator.of(dialogContext).pop(true),
      ),
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
    return result ?? false;
  }

  Future<void> _handlePaste([ContextMenuButtonItem? pasteItem]) async {
    // The field is read-only while a voice draft sends, and the text it
    // holds is cleared once the send lands.
    bool voiceDraftSending() => _voiceDraft?.sending ?? false;
    if (voiceDraftSending()) return;
    if (vm.editingMessage == null) {
      if (_usesNativeDesktopComposer(context)) {
        if (await _queueDesktopClipboardImages()) return;
      } else {
        final image = await _readClipboardImage();
        if (image != null) {
          final queued = await _queueClipboardImageData(
            DesktopClipboardImageData(
              data: image.data,
              mimeType: image.mimeType,
            ),
          );
          if (queued) return;
        }
      }
    }

    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || voiceDraftSending()) return;
    final text = clipboard?.text;
    if (text != null && text.isNotEmpty) {
      _controller.insertText(text);
    } else {
      pasteItem?.onPressed?.call();
    }
    _restoreKeyboardFocus();
  }

  Future<void> _showComposerFormatMenu(
    EditableTextState editableTextState,
  ) async {
    final selection = _controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    final start = math.min(selection.start, selection.end);
    final end = math.max(selection.start, selection.end);
    final anchor = editableTextState.contextMenuAnchors.primaryAnchor;
    editableTextState.hideToolbar();
    final action = await showGeneralDialog<_ComposerFormatAction>(
      context: context,
      requestFocus: false,
      barrierDismissible: true,
      barrierLabel: AppStringKeys.countryPickerCancel.l10n(context),
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (dialogContext, _, _) => _ComposerFormatMenu(anchor: anchor),
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
    if (!mounted) return;
    if (action == null) {
      _focus.unfocus();
      return;
    }
    _controller.selection = TextSelection(baseOffset: start, extentOffset: end);
    if (action == _ComposerFormatAction.link) {
      final url = await showGeneralDialog<String>(
        context: context,
        barrierDismissible: true,
        barrierLabel: AppStringKeys.countryPickerCancel.l10n(context),
        barrierColor: Colors.black.withValues(alpha: 0.36),
        transitionDuration: const Duration(milliseconds: 160),
        pageBuilder: (dialogContext, _, _) => const _ComposerLinkDialog(),
      );
      if (!mounted || url == null || url.trim().isEmpty) return;
      final normalized = _normalizeComposerUrl(url);
      _controller.applyEntityFormat(start, end, {
        '@type': 'textEntityTypeTextUrl',
        'url': normalized,
      });
    } else {
      _controller.toggleFormat(action.entityType);
    }
    _controller.selection = TextSelection(baseOffset: start, extentOffset: end);
    _focus.requestFocus();
  }

  String _normalizeComposerUrl(String value) {
    final trimmed = value.trim();
    final parsed = Uri.tryParse(trimmed);
    if (parsed?.hasScheme ?? false) return trimmed;
    return 'https://$trimmed';
  }

  void _restoreKeyboardFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
    });
  }

  String _aiReplyProgressLabel(AiReplyProgressPhase phase) => switch (phase) {
    AiReplyProgressPhase.readingRecentMessages =>
      AppStringKeys.aiReplyProcessReading.l10n(context),
    AiReplyProgressPhase.checkingEarlierContext =>
      AppStringKeys.aiReplyProcessChecking.l10n(context),
    AiReplyProgressPhase.writingReply =>
      AppStringKeys.aiReplyProcessWriting.l10n(context),
  };

  Future<void> _showAiReplyModelPicker(ChatMessage target) async {
    if (_aiReplyWorkingTargetId != null) return;
    final settings = context.read<AiSettingsController?>();
    if (settings?.initialized != true) {
      showToast(context, AppStringKeys.aiReplyUnavailable.l10n(context));
      return;
    }
    final candidate = await showAiFeatureModelPicker(
      context,
      settings: settings!,
      feature: AiFeature.reply,
    );
    if (!mounted || candidate == null) return;
    await _generateAiReply(target, requiredModelCandidateId: candidate.id);
  }
}
