part of 'chat_view.dart';

extension _ChatViewTranslationSummary on _ChatViewState {
  bool _isTelegramTranslationOption(String option) =>
      TranslationOptionIds.translationProvider(option) ==
      TranslationProvider.tdlib;

  Future<String> _translateTextWithGoogleCloud(
    String providerId, {
    required String text,
    required String sourceLanguageCode,
    required String targetLanguageCode,
  }) async {
    final provider = _translation.googleCloudProviderById(providerId);
    if (provider == null || !provider.hasApiKey) {
      throw TranslationApiException(
        AppStringKeys.translationAiProviderUnavailable.l10n(context),
      );
    }
    final apiKey = await _translation.googleCloudApiKeyForProvider(providerId);
    if (apiKey.isEmpty) {
      throw TranslationApiException(
        AppStrings.t(AppStringKeys.translationGoogleCloudApiKeyRequired),
      );
    }
    return ThirdPartyTranslationApi.translateGoogleCloud(
      text: text,
      sourceLanguageCode: sourceLanguageCode,
      targetLanguageCode: targetLanguageCode,
      apiKey: apiKey,
    );
  }

  Future<String> _translateTextWithOption(
    String option, {
    required String text,
    required String sourceLanguageCode,
    required String targetLanguageCode,
    List<String> priorMessages = const [],
  }) {
    final googleCloudProviderId = TranslationOptionIds.googleCloudProviderId(
      option,
    );
    if (googleCloudProviderId != null) {
      return _translateTextWithGoogleCloud(
        googleCloudProviderId,
        text: text,
        sourceLanguageCode: sourceLanguageCode,
        targetLanguageCode: targetLanguageCode,
      );
    }
    final candidateId = TranslationOptionIds.aiCandidateId(option);
    if (candidateId != null) {
      final candidate = _ai?.modelCandidateByIdForFeature(
        AiFeature.translation,
        candidateId,
      );
      if (candidate == null) {
        throw TranslationApiException(
          AppStringKeys.translationAiProviderUnavailable.l10n(context),
        );
      }
      return _translateTextWithAi(
        candidate: candidate,
        text: text,
        sourceLanguageCode: sourceLanguageCode,
        targetLanguageCode: targetLanguageCode,
        priorMessages: priorMessages,
      );
    }
    final provider = TranslationOptionIds.translationProvider(option);
    return switch (provider) {
      TranslationProvider.iosSystem ||
      TranslationProvider.androidMlKit => NativeTranslationApi.translate(
        text: text,
        sourceLanguageCode: sourceLanguageCode,
        targetLanguageCode: targetLanguageCode,
      ),
      TranslationProvider.tdlib => _vm.translateText(text, targetLanguageCode),
      TranslationProvider.googleTranslate ||
      TranslationProvider.myMemory ||
      TranslationProvider.lingva ||
      TranslationProvider.libreTranslate => ThirdPartyTranslationApi.translate(
        provider: provider!,
        text: text,
        sourceLanguageCode: sourceLanguageCode,
        targetLanguageCode: targetLanguageCode,
        lingvaEndpoint: _translation.lingvaEndpoint,
        libreTranslateEndpoint: _translation.libreTranslateEndpoint,
        libreTranslateApiKey: _translation.libreTranslateApiKey,
      ),
      null => throw TranslationApiException(
        AppStringKeys.translationAiProviderUnavailable.l10n(context),
      ),
    };
  }

  Future<void> _showReactionUsers(
    ChatMessage message,
    MessageReaction reaction,
  ) async {
    if (!mounted || message.reactions.isEmpty) return;
    // `can_report_reactions` is a messageProperties field, not a field of the
    // message. Start the hydrated permission alongside the sheet so the report
    // action appears only after TDLib granted it, and fails closed otherwise.
    final reportPermission = _vm.canReportMessageReactions(message.id);
    await showReactionUsersModal<void>(
      context,
      builder: (dialogContext) => _ReactionUsersSheet(
        viewModel: _vm,
        message: message,
        initialReaction: reaction,
        reportPermission: reportPermission,
        onOpenSender: _openReactionSender,
        onReportSender: (user) => _reportReactionSender(message, user),
      ),
    );
  }

  void _openReactionSender(MessageReactionUser user) {
    final senderId = user.senderId;
    if (user.isDeleted || senderId == 0) return;
    // The list is left either way: it belongs to the message behind it, and
    // keeping it alive under a pushed profile leaves a stale sheet to come
    // back to.
    Navigator.of(context).pop();
    if (senderId > 0) {
      _openUserProfile(senderId, user.title);
      return;
    }
    if (senderId == widget.chatId) {
      unawaited(_openChatInfo(title: user.title, useAppPageRoute: true));
      return;
    }
    unawaited(
      openChatFromCurrentWindow(context, chatId: senderId, title: user.title),
    );
  }

  Future<void> _reportReactionSender(
    ChatMessage message,
    MessageReactionUser user,
  ) async {
    if (user.isDeleted) return;
    if (user.senderId == _vm.meId) return;
    final confirmed = await showAppConfirmDialog(
      context,
      title: AppStrings.t(AppStringKeys.chatReactionReportTitle),
      message: AppStrings.t(AppStringKeys.chatReactionReportMessage, {
        'value1': user.title,
      }),
      confirmText: AppStrings.t(AppStringKeys.chatReportConfirm),
      destructive: true,
    );
    // The permission and the write belong to the pane's own account: a switch
    // while the dialog was open must drop the report entirely.
    if (!mounted || !confirmed || !_vm.isAccountCurrent) return;
    try {
      await _vm.reportReaction(message, user.senderId);
      if (!mounted) return;
      showToast(context, AppStringKeys.chatReactionReportSent);
    } catch (e) {
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.chatReactionReportFailed, {'value1': e}),
      );
    }
  }

  Future<bool> _translateMessage(
    ChatMessage message, {
    bool showErrors = true,
    bool allowWhenManualTranslationDisabled = false,
    String sourceLanguageCode = 'autodetect',
  }) async {
    final translation = context.read<TranslationController>();
    if (!translation.enabled && !allowWhenManualTranslationDisabled) {
      return true;
    }
    final sourceText = _translationSourceText(message);
    if (sourceText.trim().isEmpty) return true;
    final targetLanguage = _translationTargetLanguage(translation);
    final noProviderMessage = AppStringKeys.translationAiProviderUnavailable
        .l10n(context);
    final ai = _ai;
    if (ai != null && !ai.initialized) {
      try {
        await ai.initialize();
      } catch (_) {
        // Keep the non-AI providers in the fallback chain available.
      }
    }
    final options = _effectiveTranslationOptions;
    if (options.isEmpty) return false;
    try {
      final cached = await translation.messageCache.resolve(
        MessageTranslationCacheKey(
          accountSlot: _sessionKey.accountSlot,
          chatId: widget.chatId,
          messageId: message.id,
          sourceText: sourceText,
          targetLanguageCode: targetLanguage,
        ),
        () async {
          Object? lastError;
          MessageTranslationResult? result;
          for (final option in options) {
            try {
              result = await _translateMessageWithOption(
                option,
                message: message,
                sourceText: sourceText,
                sourceLanguageCode: sourceLanguageCode,
                targetLanguageCode: targetLanguage,
              );
              break;
            } catch (error) {
              lastError = error;
              if (_isTelegramTranslationOption(option) &&
                  isTelegramTranslationRateLimit(error)) {
                translation.markTelegramTranslationUnavailable();
              }
            }
          }
          if (result == null) {
            throw lastError ?? TranslationApiException(noProviderMessage);
          }
          return MessageTranslationValue(
            text: result.text,
            entities: result.entities,
            languageCode: result.languageCode,
          );
        },
      );
      if (mounted) {
        _vm.restoreMessageTranslation(message.id, (
          text: cached.text,
          entities: cached.entities,
          languageCode: cached.languageCode,
        ));
      }
      return true;
    } catch (e) {
      if (!mounted) return false;
      if (showErrors) {
        showToast(
          context,
          _translationFailureMessage(e),
          visibleFor: isTelegramAiPremiumFlood(e)
              ? const Duration(seconds: 4)
              : const Duration(milliseconds: 1400),
        );
      }
      return false;
    }
  }

  Future<MessageTranslationResult> _translateMessageWithOption(
    String option, {
    required ChatMessage message,
    required String sourceText,
    required String sourceLanguageCode,
    required String targetLanguageCode,
  }) {
    if (_isTelegramTranslationOption(option)) {
      return _vm.translateMessage(message.id, targetLanguageCode);
    }
    final provider = TranslationOptionIds.translationProvider(option);
    return _vm.translateMessageExternally(
      message.id,
      targetLanguageCode,
      () => _translateTextWithOption(
        option,
        text: sourceText,
        sourceLanguageCode: sourceLanguageCode,
        targetLanguageCode: targetLanguageCode,
        priorMessages: _aiTranslationContextFor(message),
      ),
      showLoading:
          provider != TranslationProvider.iosSystem ||
          defaultTargetPlatform != TargetPlatform.iOS,
    );
  }

  String _translationFailureMessage(Object error) {
    if (isTelegramAiPremiumFlood(error)) {
      return '${AppStrings.t(AppStringKeys.telegramAiDailyLimitReached)}\n'
          '${AppStrings.t(AppStringKeys.telegramAiDailyLimitMessage)}';
    }
    return AppStrings.t(AppStringKeys.chatTranslateFailed, {'value1': error});
  }

  Future<void> _loadNativeTranslationProviders() async {
    final providers = await NativeTranslationApi.availableProviders();
    if (!mounted || setEquals(providers, _nativeTranslationProviders)) return;
    _updateState(() => _nativeTranslationProviders = providers);
    _scheduleChatLanguageDetection(force: true);
    _scheduleAutomaticTranslations();
  }

  Future<void> _loadBotApiWarningDismissal() async {
    final prefs = await SharedPreferences.getInstance();
    final mask = prefs.getInt(_botApiWarningDismissalKey);
    if (mask != null) {
      _ChatViewState._dismissedBotApiWarningByChat[widget.chatId] = mask;
    }
    if (!mounted || mask == _dismissedBotApiWarningMask) return;
    _updateState(() => _dismissedBotApiWarningMask = mask);
  }

  void _dismissBotApiAccessWarning() {
    final mask = _botApiWarningMask;
    if (mask == 0) return;
    _ChatViewState._dismissedBotApiWarningByChat[widget.chatId] = mask;
    _updateState(() => _dismissedBotApiWarningMask = mask);
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setInt(_botApiWarningDismissalKey, mask),
      ),
    );
  }

  void _onTranslationSettingsChanged() {
    if (!mounted) return;
    if (_translation.displayStyle != TranslationDisplayStyle.translatedOnly) {
      _showOriginalTranslationMessageIds.clear();
    }
    _autoTranslationFailedMessageIds.clear();
    if (!_automaticTranslationEnabled && _autoTranslatedMessageIds.isNotEmpty) {
      _vm.clearTranslations(_autoTranslatedMessageIds);
      _autoTranslatedMessageIds.clear();
    }
    _scheduleChatLanguageDetection(force: true);
    _scheduleAutomaticTranslations();
    _updateState(() {});
  }

  void _scheduleChatLanguageDetection({bool force = false}) {
    if (!_hasAvailableTranslationOption ||
        !_translation.translateChats ||
        _chatLanguageDetectionRunning) {
      return;
    }
    if (!force && _chatLanguageDetectionComplete) {
      final detectedAt = _chatLanguageDetectedAt;
      if (_detectedChatLanguage != null &&
          detectedAt != null &&
          DateTime.now().difference(detectedAt) < const Duration(hours: 1)) {
        return;
      }
    }
    final samples = automaticTranslationLanguageSamples(_vm.messages);
    if (samples.isEmpty) return;
    final newestId = _vm.messages.reversed
        .firstWhere(
          (message) =>
              !message.isOutgoing &&
              !message.isService &&
              automaticTranslationSourceText(message).trim().length >= 10,
          orElse: () => _vm.messages.last,
        )
        .id;
    if (!force && _chatLanguageDetectionComplete) {
      if (_chatLanguageDetectionNewestMessageId == newestId) return;
    }
    _chatLanguageDetectionRunning = true;
    unawaited(() async {
      final detections = await Future.wait(
        samples.map(NativeTranslationApi.identifyLanguage),
      );
      final evidence = <AutomaticTranslationLanguageEvidence>[
        for (var index = 0; index < samples.length; index++)
          if (detections[index] case final detected?)
            AutomaticTranslationLanguageEvidence(
              languageCode: detected.languageCode,
              confidence: detected.confidence,
              characterCount: samples[index].runes.length,
            ),
      ];
      final detected = dominantAutomaticTranslationLanguage(evidence);
      if (!mounted) return;
      _chatLanguageDetectionRunning = false;
      _chatLanguageDetectionComplete = true;
      _chatLanguageDetectionNewestMessageId = newestId;
      _chatLanguageDetectedAt = DateTime.now();
      _detectedChatLanguage = detected;
      ChatHeaderStateCache.updateLanguageState(
        accountSlot: TdClient.shared.activeSlot,
        chatId: widget.chatId,
        detectedChatLanguage: detected,
        complete: true,
        detectedAt: DateTime.now(),
        newestMessageId: newestId,
      );
      _scheduleAutomaticTranslations();
      _updateState(() {});
    }());
  }

  void _scheduleAutomaticTranslations() {
    if (!_automaticTranslationEnabled) return;
    if (_autoTranslationRunning) {
      _autoTranslationPassPending = true;
      return;
    }
    if (_autoTranslationPassPending) return;
    _autoTranslationPassPending = true;
    scheduleMicrotask(() {
      _autoTranslationPassPending = false;
      if (!mounted || !_automaticTranslationEnabled) return;
      unawaited(_runAutomaticTranslationPass());
    });
  }

  Future<void> _runAutomaticTranslationPass() async {
    if (_autoTranslationRunning || !_automaticTranslationEnabled) return;
    _autoTranslationRunning = true;
    if (mounted) _updateState(() {});
    try {
      final messages = _vm.messages.length > 32
          ? _vm.messages.sublist(_vm.messages.length - 32)
          : _vm.messages;
      final candidates = automaticTranslationCandidates(
        messages,
        targetLanguageCode: _translationTargetLanguage(_translation),
        excludedMessageIds: _autoTranslationFailedMessageIds,
      );
      for (final message in candidates) {
        if (!mounted || !_automaticTranslationEnabled) break;
        final translated = await _translateMessage(
          message,
          showErrors: false,
          allowWhenManualTranslationDisabled: true,
          sourceLanguageCode: _detectedChatLanguage ?? 'autodetect',
        );
        if (translated) {
          _autoTranslatedMessageIds.add(message.id);
        } else {
          _autoTranslationFailedMessageIds.add(message.id);
        }
      }
    } finally {
      _autoTranslationRunning = false;
      if (mounted) _updateState(() {});
      if (_autoTranslationPassPending) {
        _autoTranslationPassPending = false;
        _scheduleAutomaticTranslations();
      }
    }
  }

  void _toggleAutomaticTranslation() {
    final active = _translation.autoTranslateEnabledFor(widget.chatId);
    _translation.setAutoTranslateEnabledFor(widget.chatId, !active);
  }

  void _dismissAutomaticTranslation() {
    _translation.dismissAutoTranslateSuggestionFor(widget.chatId);
  }

  Future<void> _showChatTranslationLanguagePicker() async {
    final c = context.colors;
    await showAppModalSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
          ),
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: TranslationController.targetLanguages.length,
            separatorBuilder: (_, _) => const InsetDivider(leadingInset: 54),
            itemBuilder: (_, index) {
              final language = TranslationController.targetLanguages[index];
              final selected = _translation.targetLanguageCode == language.code;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _translation.targetLanguageCode = language.code;
                  Navigator.of(sheetContext).pop();
                },
                child: SizedBox(
                  height: 52,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        AppIcon(
                          HeroAppIcons.globe,
                          size: 19,
                          color: selected ? AppTheme.brand : c.textSecondary,
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Text(
                            language.label.l10n(sheetContext),
                            style: TextStyle(
                              fontSize: 16,
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                        if (selected)
                          AppIcon(
                            HeroAppIcons.check,
                            size: 18,
                            color: AppTheme.brand,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  String _translationSourceText(ChatMessage message) =>
      automaticTranslationSourceText(message);

  String _translationTargetLanguage(TranslationController translation) {
    if (translation.targetLanguageCode != 'auto') {
      return translation.targetLanguageCode;
    }
    final locale = Localizations.localeOf(context);
    final country = locale.countryCode?.toUpperCase();
    if (locale.languageCode == 'zh') {
      return switch (country) {
        'TW' || 'HK' || 'MO' => 'zh-Hant',
        _ => 'zh-Hans',
      };
    }
    return locale.languageCode;
  }

  Future<String> _translateTextWithAi({
    required AiModelCandidate candidate,
    required String text,
    required String sourceLanguageCode,
    required String targetLanguageCode,
    List<String> priorMessages = const [],
  }) async {
    final unavailableMessage = AppStringKeys.translationAiProviderUnavailable
        .l10n(context);
    final targetLanguageName = _translation.targetLanguageLabel.l10n(context);
    final ai = _ai;
    if (ai == null) throw TranslationApiException(unavailableMessage);
    if (!ai.initialized) await ai.initialize();
    if (!ai.isConfiguredCandidate(candidate)) {
      throw TranslationApiException(unavailableMessage);
    }
    final service = AiChatTranslationService.fromCandidate(
      ai,
      candidate,
      instructions: _translation.aiTranslationPrompt,
      telegramAi: _vm.telegramAi,
    );
    try {
      return await service.translate(
        text: text,
        sourceLanguageCode: sourceLanguageCode,
        targetLanguageCode: targetLanguageCode,
        targetLanguageName: targetLanguageName,
        priorMessages: priorMessages,
      );
    } finally {
      service.dispose();
    }
  }

  List<String> _aiTranslationContextFor(ChatMessage message) {
    final index = _vm.messages.indexWhere((item) => item.id == message.id);
    if (index <= 0) return const [];
    final contextMessages = <String>[];
    for (var i = index - 1; i >= 0 && contextMessages.length < 4; i--) {
      final source = automaticTranslationSourceText(
        _vm.messages[i],
      ).replaceAll(RegExp(r'\s+'), ' ').trim();
      if (source.isEmpty) continue;
      contextMessages.add(
        source.length > 400 ? source.substring(0, 400) : source,
      );
    }
    return contextMessages.reversed.toList(growable: false);
  }

  bool _canOfferUnreadSummary(AiSettingsController? settings) =>
      shouldShowUnreadChatSummaryAttachment(
        unreadMessageCount: _remainingUnreadCount,
        providerAvailable:
            settings?.initialized == true &&
            settings?.enabled == true &&
            settings?.isConfiguredForFeature(AiFeature.summary) == true &&
            _vm.unreadSummarySnapshot != null &&
            !_vm.isSecretChat &&
            !_vm.hasProtectedContent,
      );

  Future<void> _openUnreadSummary() async {
    final snapshot = _vm.unreadSummarySnapshot;
    final settings = context.read<AiSettingsController?>();
    if (snapshot == null || !_canOfferUnreadSummary(settings)) return;
    _updateState(() => _openingUnreadSummary = true);

    final configuration = settings!.configurationForFeature(AiFeature.summary);
    final endpoint = configuration.endpoint;
    final endpointStyle = configuration.endpointStyle;
    final model = configuration.model;
    final apiKey = configuration.apiKey;
    final hostedContextSize =
        configuration.candidate.kind == AiModelCandidateKind.server
        ? configuration.contextWindowTokens
        : null;
    final pccContextSize =
        configuration.candidate.kind == AiModelCandidateKind.applePcc
        ? configuration.contextWindowTokens
        : null;
    final onDeviceContextSize =
        configuration.candidate.kind == AiModelCandidateKind.appleOnDevice
        ? configuration.contextWindowTokens
        : null;
    final outputLanguage = Localizations.localeOf(context).toLanguageTag();
    final session = _createUnreadSummarySession(
      candidateKind: configuration.candidate.kind,
      endpoint: endpoint,
      endpointStyle: endpointStyle,
      model: model,
      apiKey: apiKey,
      hostedContextSize: hostedContextSize,
      pccContextSize: pccContextSize,
      onDeviceContextSize: onDeviceContextSize,
      outputLanguage: outputLanguage,
      summaryGuidance: settings.aiSummaryPrompt,
    );
    int? messageId;
    try {
      messageId = await Navigator.of(context).push<int>(
        MaterialPageRoute<int>(
          builder: (_) => UnreadChatSummaryView(
            snapshot: snapshot,
            summarize: (onProgress, onDraft) => session.summarize(
              snapshot,
              onProgress: onProgress,
              onDraft: onDraft,
            ),
          ),
        ),
      );
    } finally {
      session.dispose();
      if (mounted) _updateState(() => _openingUnreadSummary = false);
    }
    if (!mounted) return;
    if (messageId != null) await _scrollToMessage(messageId);
  }

  _UnreadSummarySession _createUnreadSummarySession({
    required AiModelCandidateKind candidateKind,
    required Uri? endpoint,
    required AiEndpointStyle endpointStyle,
    required String model,
    required String apiKey,
    required int? hostedContextSize,
    required int? pccContextSize,
    required int? onDeviceContextSize,
    required String outputLanguage,
    required String summaryGuidance,
  }) {
    final loader = UnreadChatHistoryLoader(
      query: (accountSlot, request) {
        final clientId = TdClient.shared.clientId(accountSlot);
        if (clientId == null) {
          throw StateError('The account used for this chat is unavailable.');
        }
        return TdClient.shared.queryTo(request, clientId);
      },
    );
    final guidanceTokenEstimate = estimateUnreadSummaryPromptTokens({
      'user_guidance': summaryGuidance,
    });
    int messagePayloadBudget(int totalPayloadTokens) =>
        math.max(1, totalPayloadTokens - guidanceTokenEstimate);

    switch (candidateKind) {
      case AiModelCandidateKind.telegramCocoon:
        const contextWindow = 8192;
        final tokenBudget = unreadSummaryTokenBudget(
          contextWindow,
          trustedInstructions: unreadChatSummaryCompactTrustedInstructions,
          maximumResponseTokens: 1300,
          maximumPayloadTokens: 5500,
        );
        return _UnreadSummarySession(
          UnreadChatSummaryService(
            historyLoader: loader,
            maxChunkMessages: 180,
            maxChunks: 5,
            maxConcurrentRequests: 1,
            maxChunkTokenEstimate: messagePayloadBudget(
              tokenBudget.payloadTokens,
            ),
            mergeChunkSummariesLocally: true,
            trustedInstructions: unreadChatSummaryCompactTrustedInstructions,
            summaryGuidance: summaryGuidance,
            providerCode: 'telegram_cocoon',
            contextWindowTokens: contextWindow,
            outputLanguage: outputLanguage,
            initialPromptTokenEstimate: tokenBudget.initialPromptTokens,
            reservedNonPayloadTokenEstimate:
                tokenBudget.reservedNonPayloadTokens,
            provider: TelegramCocoonUnreadSummaryProvider(
              telegramAi: _vm.telegramAi,
            ),
          ),
        );
      case AiModelCandidateKind.applePcc:
        final contextWindow = math.min(
          pccContextSize ?? applePccContextTokenLimit,
          applePccContextTokenLimit,
        );
        final tokenBudget = unreadSummaryTokenBudget(
          contextWindow,
          trustedInstructions: unreadChatSummaryTrustedInstructions,
          maximumResponseTokens: 1300,
        );
        return _UnreadSummarySession(
          UnreadChatSummaryService(
            historyLoader: loader,
            maxChunkMessages: 180,
            maxChunks: 5,
            maxChunkTokenEstimate: math.min(
              7000,
              messagePayloadBudget(tokenBudget.payloadTokens),
            ),
            mergeChunkSummariesLocally: true,
            summaryGuidance: summaryGuidance,
            providerCode: 'apple_pcc',
            contextWindowTokens: contextWindow,
            outputLanguage: outputLanguage,
            initialPromptTokenEstimate: tokenBudget.initialPromptTokens,
            reservedNonPayloadTokenEstimate:
                tokenBudget.reservedNonPayloadTokens,
            provider: ApplePccUnreadSummaryProvider(
              api: ApplePccApi(summaryTimeout: const Duration(seconds: 50)),
              reasoningLevel: ApplePccReasoningLevel.light,
              chunkMaximumResponseTokens: 1300,
            ),
          ),
        );
      case AiModelCandidateKind.appleOnDevice:
        final contextWindow = math.min(
          onDeviceContextSize ?? appleOnDeviceContextTokenLimit,
          appleOnDeviceContextTokenLimit,
        );
        final tokenBudget = unreadSummaryTokenBudget(
          contextWindow,
          maximumContextSize: appleOnDeviceContextTokenLimit,
          trustedInstructions: unreadChatSummaryCompactTrustedInstructions,
          maximumResponseTokens: 650,
        );
        return _UnreadSummarySession(
          UnreadChatSummaryService(
            historyLoader: loader,
            maxChunkMessages: 70,
            maxChunks: 4,
            maxConcurrentRequests: 1,
            maxChunkTokenEstimate: messagePayloadBudget(
              tokenBudget.payloadTokens,
            ),
            mergeChunkSummariesLocally: true,
            trustedInstructions: unreadChatSummaryCompactTrustedInstructions,
            summaryGuidance: summaryGuidance,
            providerCode: 'apple_on_device',
            contextWindowTokens: contextWindow,
            outputLanguage: outputLanguage,
            initialPromptTokenEstimate: tokenBudget.initialPromptTokens,
            reservedNonPayloadTokenEstimate:
                tokenBudget.reservedNonPayloadTokens,
            provider: ApplePccUnreadSummaryProvider(
              api: ApplePccApi(summaryTimeout: const Duration(seconds: 40)),
              model: AppleAiModel.onDevice,
              reasoningLevel: ApplePccReasoningLevel.light,
              chunkMaximumResponseTokens: 650,
              mergeMaximumResponseTokens: 650,
            ),
          ),
        );
      case AiModelCandidateKind.server:
        if (endpoint == null || model.trim().isEmpty) {
          throw StateError('The summary server is not configured.');
        }
        final contextWindow =
            hostedContextSize ?? AiModelProfile.defaultContextWindowTokens;
        // Reserve response space while selecting input, but do not send a
        // generation cap to user-configured servers.
        const responseTokenReserve = 4096;
        final tokenBudget = unreadSummaryTokenBudget(
          contextWindow,
          maximumContextSize: AiModelProfile.maximumContextWindowTokens,
          trustedInstructions: unreadChatSummaryCompactTrustedInstructions,
          maximumResponseTokens: responseTokenReserve,
          maximumPayloadTokens: contextWindow,
        );
        final provider = OpenAiCompatibleUnreadSummaryProvider(
          serverBaseUri: endpoint,
          model: model.trim(),
          apiKey: apiKey,
          endpointStyle: endpointStyle,
        );
        return _UnreadSummarySession(
          UnreadChatSummaryService(
            historyLoader: loader,
            provider: provider,
            maxChunkMessages: 1000000,
            maxChunks: 4,
            maxConcurrentRequests: 4,
            maxChunkTokenEstimate: messagePayloadBudget(
              tokenBudget.payloadTokens,
            ),
            maxChunkTimeGapSeconds: 0,
            trustedInstructions: unreadChatSummaryCompactTrustedInstructions,
            summaryGuidance: summaryGuidance,
            providerCode: '${endpointStyle.storageValue}/$model',
            contextWindowTokens: contextWindow,
            outputLanguage: outputLanguage,
            initialPromptTokenEstimate: tokenBudget.initialPromptTokens,
            reservedNonPayloadTokenEstimate:
                tokenBudget.reservedNonPayloadTokens,
          ),
          onDispose: provider.close,
        );
    }
  }

  Future<void> _openUnreadMention() async {
    if (_openingUnreadMention || _vm.unreadMentionCount <= 0) return;
    _updateState(() => _openingUnreadMention = true);
    final messageId = await _vm.openNextUnreadMention();
    if (messageId != null && mounted) {
      await _scrollToMessage(messageId);
      if (_vm.messages.any((message) => message.id == messageId)) {
        await _vm.markUnreadMentionRead(messageId);
      }
    }
    if (mounted) _updateState(() => _openingUnreadMention = false);
  }

  Future<void> _openUnreadReaction() async {
    if (_openingUnreadReaction || _vm.unreadReactionCount <= 0) return;
    _updateState(() => _openingUnreadReaction = true);
    final messageId = await _vm.openNextUnreadReaction();
    if (messageId != null && mounted) {
      await _scrollToMessage(messageId);
      if (_vm.messages.any((message) => message.id == messageId)) {
        await _vm.markUnreadReactionRead(messageId);
      }
    }
    if (mounted) _updateState(() => _openingUnreadReaction = false);
  }
}
