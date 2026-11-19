part of 'chat_view_model.dart';

extension ChatViewModelSending on ChatViewModel {
  void beginMessageEdit(ChatMessage message) {
    if (editingMessage != null) {
      _restoreComposerAfterMessageEdit(notify: false, scheduleDraftSave: false);
    }
    _draftSaveTimer?.cancel();
    _draftSaveTimer = null;
    _draftBeforeEditing = draft;
    _formattedDraftBeforeEditing = _draftFormattedText;
    _entitiesBeforeEditing = [
      for (final entity in _draftFormattedEntities)
        Map<String, dynamic>.from(entity),
    ];
    _mentionsBeforeEditing = List<_DraftMention>.from(_draftMentions);
    _replyBeforeEditing = replyTo;
    _replyQuoteBeforeEditing = _replyQuote;
    editingMessage = message;
    replyTo = null;
    draft = message.text;
    _draftFormattedText = message.text;
    _draftFormattedEntities = [
      for (final entity in message.textEntities) entity.toTdJson(),
    ];
    _draftMentions.clear();
    notifyListeners();
  }

  void cancelMessageEdit() {
    if (editingMessage == null) return;
    _restoreComposerAfterMessageEdit();
  }

  Future<bool> submitMessageEdit(
    String text, {
    List<Map<String, dynamic>> entities = const [],
  }) async {
    final message = editingMessage;
    if (message == null) return false;
    if (!editingMessageUsesCaption && text.trim().isEmpty) return false;
    final spaced = _spacedOutgoing(text, entities, editing: true);
    if (editingMessageUsesCaption) {
      await editMessageCaption(
        message.id,
        spaced.text,
        entities: spaced.entities,
      );
    } else {
      await editMessageText(message.id, spaced.text, entities: spaced.entities);
    }
    if (editingMessage?.id == message.id) {
      _restoreComposerAfterMessageEdit();
    }
    return true;
  }

  void _restoreComposerAfterMessageEdit({
    bool notify = true,
    bool scheduleDraftSave = true,
  }) {
    final savedDraft = _draftBeforeEditing;
    editingMessage = null;
    if (savedDraft != null) {
      draft = savedDraft;
      _draftFormattedText = _formattedDraftBeforeEditing;
      _draftFormattedEntities = [
        for (final entity in _entitiesBeforeEditing)
          Map<String, dynamic>.from(entity),
      ];
      _draftMentions
        ..clear()
        ..addAll(_mentionsBeforeEditing);
      replyTo = _replyBeforeEditing;
      _replyQuote = _replyQuoteBeforeEditing;
    }
    _draftBeforeEditing = null;
    _formattedDraftBeforeEditing = '';
    _entitiesBeforeEditing = const [];
    _mentionsBeforeEditing = const [];
    _replyBeforeEditing = null;
    _replyQuoteBeforeEditing = null;
    if (scheduleDraftSave) _scheduleDraftSave();
    if (notify) notifyListeners();
  }

  void _scheduleDraftSave() {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 750), () {
      _draftSaveTimer = null;
      _saveDraftNow();
    });
  }

  void _flushPendingDraftSave() {
    final timer = _draftSaveTimer;
    if (timer == null) return;
    timer.cancel();
    _draftSaveTimer = null;
    _saveDraftNow();
  }

  void _clearDraft({bool syncRemote = true}) {
    draft = '';
    _draftFormattedText = '';
    _draftFormattedEntities = const [];
    _draftMentions.clear();
    _draftSaveTimer?.cancel();
    _draftSaveTimer = null;
    if (syncRemote) _saveDraftNow();
  }

  void _saveDraftNow() {
    final text = _draftFormattedText;
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      if (_lastSavedDraftText == '') return;
      _lastSavedDraftText = '';
      _client.send(
        setTextChatDraftRequest(
          chatId: chatId,
          topicId: _forumTopicRef,
          formattedText: null,
          date: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ),
      );
      return;
    }

    final allEntities = [
      ..._draftFormattedEntities,
      ..._mentionEntitiesFor(text, _draftFormattedEntities),
    ];
    if (_lastSavedDraftText == text && allEntities.isEmpty) return;
    _lastSavedDraftText = text;
    _client.send(
      setTextChatDraftRequest(
        chatId: chatId,
        topicId: _forumTopicRef,
        date: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        formattedText: {
          '@type': 'formattedText',
          'text': text,
          if (allEntities.isNotEmpty) 'entities': allEntities,
        },
      ),
    );
  }

  /// Flushes the current composer draft before a separate desktop editor
  /// reads it through the account-scoped TDLib proxy.
  Future<void> persistComposerDraft() async {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = null;
    final text = _draftFormattedText;
    final allEntities = [
      ..._draftFormattedEntities,
      ..._mentionEntitiesFor(text, _draftFormattedEntities),
    ];
    await _client.query(
      setTextChatDraftRequest(
        chatId: chatId,
        topicId: _forumTopicRef,
        date: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        formattedText: text.trim().isEmpty
            ? null
            : {
                '@type': 'formattedText',
                'text': text,
                if (allEntities.isNotEmpty) 'entities': allEntities,
              },
      ),
    );
    _lastSavedDraftText = text.trim().isEmpty ? '' : text;
  }

  void _applyRemoteDraft(
    Map<String, dynamic>? remoteDraft, {
    bool force = false,
    bool notify = true,
  }) {
    if (editingMessage != null) return;
    if (!force && (_draftSaveTimer?.isActive ?? false)) return;
    final text = TDParse.draftText(remoteDraft);
    if (!force && text == _lastSavedDraftText) return;
    draft = text;
    _draftFormattedText = text;
    _draftFormattedEntities = const [];
    _draftMentions.clear();
    _lastSavedDraftText = text;
    if (notify) notifyListeners();
  }

  /// Appends an "@name " mention to the composer (long-press an avatar), backed
  /// by a user-id entity so Telegram doesn't resolve the text as a public user.
  void insertMention(ChatMessage message) {
    final name = message.senderName?.trim() ?? '';
    final userId = message.senderId;
    if (name.isEmpty || userId == null || userId <= 0) return;
    _insertMention(name, userId);
  }

  Future<List<MentionCandidate>> searchMentionCandidates(
    String query, {
    bool includeInlineBots = false,
  }) async {
    final inlineBots = includeInlineBots
        ? await _recentInlineBotCandidates(query)
        : const <MentionCandidate>[];
    if (!isGroup) return inlineBots;
    List<MentionCandidate> memberCandidates;
    try {
      final result = await _client.query({
        '@type': 'searchChatMembers',
        'chat_id': chatId,
        'query': query.trim(),
        'limit': 50,
        'filter': {'@type': 'chatMembersFilterMembers'},
      });
      final members = result.objects('members') ?? const [];
      final resolved = await Future.wait(
        members.map(_mentionCandidateFromMember),
      );
      memberCandidates = resolved.whereType<MentionCandidate>().toList(
        growable: false,
      );
    } catch (_) {
      memberCandidates = _recentMentionCandidates(query);
    }
    if (inlineBots.isEmpty) return memberCandidates;
    final seen = <int>{for (final bot in inlineBots) bot.userId};
    return [
      ...inlineBots,
      for (final member in memberCandidates)
        if (seen.add(member.userId)) member,
    ];
  }

  Future<List<MentionCandidate>> _recentInlineBotCandidates(
    String query,
  ) async {
    if (isSecretChat) return const [];
    try {
      final response = await _client.query({'@type': 'getRecentInlineBots'});
      // The await can outlive the view model (disposed while the response was
      // held): no follow-up getUser may be issued and no candidate returned.
      if (_isDisposed) return const [];
      final rawIds = response['user_ids'];
      if (rawIds is! List || rawIds.isEmpty) return const [];
      final ids = rawIds
          .map(
            (v) => switch (v) {
              final int n => n,
              final String s => int.tryParse(s),
              _ => null,
            },
          )
          .whereType<int>()
          .where((id) => id > 0)
          .take(20)
          .toList(growable: false);
      if (ids.isEmpty) return const [];
      final normalized = query.trim().toLowerCase();
      final resolved = await Future.wait(
        ids.map((userId) async {
          try {
            final user = await _client.query({
              '@type': 'getUser',
              'user_id': userId,
            });
            if (_isDisposed) return null;
            final type = user.obj('type');
            if (type?.type != 'userTypeBot' ||
                (type?.boolean('is_inline') ?? false) == false) {
              return null;
            }
            final username = ChatViewModel._primaryUsername(user);
            if (username.isEmpty) return null;
            final rawName = TDParse.userName(user).trim();
            final name = rawName.isEmpty
                ? username
                : (rawName.startsWith('@') ? rawName.substring(1) : rawName);
            if (normalized.isNotEmpty &&
                !username.toLowerCase().startsWith(normalized) &&
                !name.toLowerCase().contains(normalized)) {
              return null;
            }
            return MentionCandidate(
              userId: userId,
              name: name,
              username: username,
              photo: TDParse.smallPhoto(user.obj('profile_photo')),
              isInlineBot: true,
            );
          } catch (_) {
            return null;
          }
        }),
      );
      if (_isDisposed) return const [];
      return resolved.whereType<MentionCandidate>().toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<MentionCandidate?> _mentionCandidateFromMember(
    Map<String, dynamic> member,
  ) async {
    final sender = member.obj('member_id');
    if (sender?.type != 'messageSenderUser') return null;
    final userId = sender?.int64('user_id');
    if (userId == null || userId <= 0) return null;
    try {
      final user = await _client.query({'@type': 'getUser', 'user_id': userId});
      final name = TDParse.userName(user).trim();
      if (name.isEmpty) return null;
      final usernames = user.obj('usernames');
      final active = usernames?['active_usernames'];
      final activeUsernames = active is List
          ? active.whereType<String>().toList(growable: false)
          : const <String>[];
      final username = activeUsernames.isNotEmpty
          ? activeUsernames.first
          : usernames?.str('editable_username') ?? '';
      return MentionCandidate(
        userId: userId,
        name: name.startsWith('@') ? name.substring(1) : name,
        username: username,
        photo: TDParse.smallPhoto(user.obj('profile_photo')),
        isDeleted: TDParse.isDeletedUser(user),
      );
    } catch (_) {
      return null;
    }
  }

  List<MentionCandidate> _recentMentionCandidates(String query) {
    final normalized = query.trim().toLowerCase();
    final seen = <int>{};
    final result = <MentionCandidate>[];
    for (final message in messages.reversed) {
      final userId = message.senderId;
      final name = message.senderName?.trim() ?? '';
      if (userId == null || userId <= 0 || name.isEmpty || !seen.add(userId)) {
        continue;
      }
      if (normalized.isNotEmpty && !name.toLowerCase().contains(normalized)) {
        continue;
      }
      result.add(
        MentionCandidate(
          userId: userId,
          name: name,
          photo: message.senderPhoto,
          isDeleted: message.senderIsDeleted,
        ),
      );
      if (result.length == 30) break;
    }
    return result;
  }

  void _insertMention(String name, int userId) {
    final mention = '@$name';
    if (_draftMentions.any((m) => m.text == mention && m.userId == userId)) {
      return;
    }
    final sep = (draft.isEmpty || draft.endsWith(' ')) ? '' : ' ';
    draft = '$draft$sep$mention ';
    _draftFormattedText = draft;
    _draftFormattedEntities = const [];
    _draftMentions.add(_DraftMention(text: mention, userId: userId));
    if (editingMessage == null) _scheduleDraftSave();
    notifyListeners();
  }

  /// Replaces the composer draft with `@botUsername query` and asks the
  /// composer to focus and run an inline-bot lookup immediately.
  void activateInlineQuery(String botUsername, [String query = '']) {
    final cleanUsername = botUsername.trim().replaceFirst(RegExp(r'^@+'), '');
    if (cleanUsername.isEmpty) return;
    if (editingMessage != null) {
      _restoreComposerAfterMessageEdit(notify: false, scheduleDraftSave: false);
    }
    final text = '@$cleanUsername $query';
    draft = text;
    _draftFormattedText = text;
    _draftFormattedEntities = const [];
    _draftMentions.clear();
    _scheduleDraftSave();
    _composerFocusTick++;
    notifyListeners();
  }

  Future<bool> send() async {
    if (!canSendMessages) return false;
    final trimmed = draft.trim();
    if (trimmed.isEmpty) return false;
    final spaced = _spacedOutgoing(trimmed, const []);

    final request = <String, dynamic>{
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': {
        '@type': 'inputMessageText',
        'text': {'@type': 'formattedText', 'text': spaced.text},
      },
    };
    final replyRevision = _replyRevision;
    if (replyTo != null) {
      request['reply_to'] = replyToInput;
    }
    final sent = await _submitMessageRequest(request);
    if (!sent) return false;
    _consumeReplyAnchorIfCurrent(replyRevision);
    _clearDraft();
    notifyListeners();
    return true;
  }

  Future<void> sendSuggestedPost({
    required String text,
    OutgoingAttachment? attachment,
    SuggestedPostPrice? price,
    int sendDate = 0,
  }) async {
    if (!canSendMessages || !isDirectMessagesGroup) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachment == null) return;
    final spaced = _spacedOutgoing(trimmed, const []);
    Map<String, dynamic> content;
    if (attachment == null) {
      content = {
        '@type': 'inputMessageText',
        'text': {'@type': 'formattedText', 'text': spaced.text},
      };
    } else {
      final resolved = await resolveAttachmentDimensions(attachment);
      content = attachmentInputMessageContent(resolved, caption: spaced.text);
    }
    final request = <String, dynamic>{
      '@type': 'sendMessage',
      'chat_id': chatId,
      'options': {
        '@type': 'messageSendOptions',
        'suggested_post_info': {
          '@type': 'inputSuggestedPostInfo',
          'price': price?.toTdJson(),
          'send_date': sendDate,
        },
      },
      'input_message_content': content,
    };
    final response = await _client.query(
      _withPaidMessageOptions(_withFixedLinkPreview(request)),
    );
    final message = TDParse.message(response);
    if (message != null) {
      _merge([message]);
      _resolveSendersIfNeeded([message]);
    }
  }

  Future<void> addSuggestedPostOffer(
    int messageId, {
    SuggestedPostPrice? price,
    int sendDate = 0,
  }) async {
    if (!isDirectMessagesGroup) return;
    await _client.query({
      '@type': 'addOffer',
      'chat_id': chatId,
      'message_id': messageId,
      'options': {
        '@type': 'messageSendOptions',
        'suggested_post_info': {
          '@type': 'inputSuggestedPostInfo',
          'price': price?.toTdJson(),
          'send_date': sendDate,
        },
      },
    });
    await _refreshMessage(messageId);
  }

  bool sendBotStart() {
    if (!peerIsBot) return false;
    _clearDraft();
    botStartSent = true;
    _sendText('/start');
    notifyListeners();
    return true;
  }

  void _sendText(String text) {
    if (!canSendMessages) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _submitPanelMessage({
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': {
        '@type': 'inputMessageText',
        'text': {'@type': 'formattedText', 'text': trimmed},
      },
    });
  }

  Future<int> currentUserId() async {
    final user = await _client.query({'@type': 'getMe'});
    final id = user.int64('id');
    if (id == null || id <= 0) throw StateError('Current user is unavailable');
    return id;
  }

  Future<void> _waitForMessageSend(
    int pendingMessageId, {
    Duration timeout = const Duration(seconds: 15),
  }) {
    final recent = _recentMessageSendResults.remove(pendingMessageId);
    if (recent != null) {
      final error = recent.error;
      return error == null ? Future.value() : Future.error(error);
    }
    final waiter = Completer<void>();
    _messageSendWaiters[pendingMessageId] = waiter;
    return waiter.future
        .timeout(
          timeout,
          onTimeout: () {
            // A timeout means TDLib has not reported the final state yet. It
            // does not mean the accepted message failed. In particular, do
            // not mark it discarded: a late updateMessageSendSucceeded would
            // otherwise delete the newly assigned server message id.
            debugPrint(
              'Message $pendingMessageId is still pending; keeping it until '
              'TDLib reports success or failure',
            );
          },
        )
        .whenComplete(() {
          if (identical(_messageSendWaiters[pendingMessageId], waiter)) {
            _messageSendWaiters.remove(pendingMessageId);
          }
        });
  }

  @visibleForTesting
  Future<void> waitForMessageSendTimeoutForTest(
    int pendingMessageId, {
    required Duration timeout,
  }) => _waitForMessageSend(pendingMessageId, timeout: timeout);

  @visibleForTesting
  bool isPendingMessageDiscardedForTest(int pendingMessageId) =>
      _discardedPendingMessageIds.contains(pendingMessageId);

  void _discardPendingMessage(int pendingMessageId) {
    _acknowledgedPendingMessageIds.remove(pendingMessageId);
    _discardedPendingMessageIds.add(pendingMessageId);
    _ignoredMergeMessageIdsCache = null;
    _removeMessages([pendingMessageId]);
    unawaited(_deleteDiscardedPendingMessage(pendingMessageId));
  }

  Future<void> _deleteDiscardedPendingMessage(int pendingMessageId) async {
    try {
      await _client.query({
        '@type': 'deleteMessages',
        'chat_id': chatId,
        'message_ids': [pendingMessageId],
        'revoke': false,
      });
    } catch (error) {
      debugPrint('Failed to delete pending message $pendingMessageId: $error');
    }
  }

  void _recordMessageSendResult(
    int pendingMessageId,
    _MessageSendResult result,
  ) {
    final waiter = _messageSendWaiters.remove(pendingMessageId);
    if (waiter != null) {
      final error = result.error;
      if (error == null) {
        waiter.complete();
      } else {
        waiter.completeError(error);
      }
      return;
    }
    _recentMessageSendResults[pendingMessageId] = result;
    while (_recentMessageSendResults.length > 32) {
      _recentMessageSendResults.remove(_recentMessageSendResults.keys.first);
    }
  }

  Future<bool> _sendDice(String text) async {
    final emoji = text.trim();
    if (!ChatViewModel._diceEmojis.contains(emoji)) return false;
    final request = <String, dynamic>{
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': {'@type': 'inputMessageDice', 'emoji': emoji},
    };
    final replyRevision = _replyRevision;
    if (replyTo != null) {
      request['reply_to'] = replyToInput;
    }
    final sent = await _submitMessageRequest(request);
    if (!sent) return false;
    _consumeReplyAnchorIfCurrent(replyRevision);
    _clearDraft();
    notifyListeners();
    return true;
  }

  /// Sets or clears the reply target without changing the current draft.
  ///
  /// The reply metadata already addresses the sender. Mentions remain an
  /// explicit action so replying cannot accidentally invoke inline-bot search.
  void setReply(ChatMessage? message, {MessageTextQuote? quote}) {
    if (editingMessage != null) {
      _restoreComposerAfterMessageEdit(notify: false);
    }
    replyTo = message;
    if (message != null && !isSecretChat && quote != null) {
      _replyQuote = quote;
    }
    notifyListeners();
  }

  Future<int> messageQuoteLengthLimit() async {
    try {
      final option = await _client.query({
        '@type': 'getOption',
        'name': 'message_reply_quote_length_max',
      });
      final limit = option.integer('value');
      if (limit != null && limit > 0) return limit;
    } catch (_) {}
    return defaultMessageQuoteLengthLimit;
  }

  /// TDLib's longest caption for this account (Premium raises it), in
  /// Unicode characters.
  Future<int> messageCaptionLengthLimit() async {
    try {
      final option = await _client.query({
        '@type': 'getOption',
        'name': 'message_caption_length_max',
      });
      final limit = option.integer('value');
      if (limit != null && limit > 0) return limit;
    } catch (_) {}
    return defaultMessageCaptionLengthLimit;
  }

  List<Map<String, dynamic>> _mentionEntitiesFor(
    String text,
    List<Map<String, dynamic>> existing,
  ) {
    final out = <Map<String, dynamic>>[];
    final occupied = existing.map((e) {
      final offset = e.integer('offset') ?? 0;
      final length = e.integer('length') ?? 0;
      return (offset, offset + length);
    }).toList();
    for (final mention in _draftMentions) {
      var start = 0;
      while (start < text.length) {
        final offset = text.indexOf(mention.text, start);
        if (offset < 0) break;
        final end = offset + mention.text.length;
        final overlaps = occupied.any((r) => offset < r.$2 && end > r.$1);
        if (!overlaps) {
          out.add({
            '@type': 'textEntity',
            'offset': offset,
            'length': mention.text.length,
            'type': {
              '@type': 'textEntityTypeMentionName',
              'user_id': mention.userId,
            },
          });
          occupied.add((offset, end));
          break;
        }
        start = end;
      }
    }
    return out;
  }

  /// Spaces text this model is about to send, moving its entities onto the new
  /// offsets. Applied here rather than in each composer so every surface that
  /// reaches a send — mobile, desktop, picker windows, media captions — spaces
  /// text the same way, and so mention detection still sees the final text.
  ({String text, List<Map<String, dynamic>> entities}) _spacedOutgoing(
    String text,
    List<Map<String, dynamic>> entities, {
    bool editing = false,
  }) => PanguSpacing.gated(
    enabled: editing ? panguOnEdit : panguOnSend,
    text: text,
    entities: entities,
  );

  Future<void> sendAttachments(
    List<OutgoingAttachment> attachments, {
    String caption = '',
    List<Map<String, dynamic>> captionEntities = const [],
    MessageSendConfiguration sendConfiguration =
        const MessageSendConfiguration(),
  }) async {
    if (attachments.isEmpty) return;
    // Capture the reply before re-encoding can yield to a reply change.
    final replyRevision = _replyRevision;
    final replyTo = replyToInput;
    // The picker hands over measured originals, so composers that skip
    // resolveAttachmentDimensions still need Telegram's photo limits applied.
    attachments = await Future.wait(attachments.map(fitPhotoToTelegramLimits));
    final spaced = _spacedOutgoing(caption, captionEntities);
    final allEntities = [
      ...spaced.entities,
      ..._mentionEntitiesFor(spaced.text, spaced.entities),
    ];
    final requests = buildAttachmentSendRequests(
      chatId: chatId,
      topicId: _forumTopicRef,
      attachments: attachments,
      caption: spaced.text,
      captionEntities: allEntities,
      replyTo: replyTo,
      sendConfiguration: sendConfiguration,
    );
    _clearDraft();
    notifyListeners();
    try {
      for (final request in requests) {
        await _client.query(
          _withPaidMessageOptions(
            request,
            sendConfiguration: sendConfiguration,
            consumePendingConfiguration: false,
          ),
        );
      }
      _consumeReplyAnchorIfCurrent(replyRevision);
    } catch (error) {
      _publishSendFailure(
        ChatSendFailure.fromError(
          error,
          paidMessageStarCount: paidMessageStarCount,
        ),
      );
      rethrow;
    }
  }

  void sendPhoto(
    String path, {
    String caption = '',
    List<Map<String, dynamic>> captionEntities = const [],
  }) {
    final captionText = captionEntities.isEmpty ? caption.trim() : caption;
    _submitPanelMessage({
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': {
        '@type': 'inputMessagePhoto',
        'photo': {
          '@type': 'inputPhoto',
          'photo': {'@type': 'inputFileLocal', 'path': path},
        },
        if (captionText.trim().isNotEmpty)
          'caption': {
            '@type': 'formattedText',
            'text': captionText,
            if (captionEntities.isNotEmpty) 'entities': captionEntities,
          },
      },
    });
  }

  void sendVideo(
    String path, {
    String caption = '',
    List<Map<String, dynamic>> captionEntities = const [],
  }) {
    final captionText = captionEntities.isEmpty ? caption.trim() : caption;
    _submitPanelMessage({
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': {
        '@type': 'inputMessageVideo',
        'video': {
          '@type': 'inputVideo',
          'video': {'@type': 'inputFileLocal', 'path': path},
          'supports_streaming': true,
        },
        if (captionText.trim().isNotEmpty)
          'caption': {
            '@type': 'formattedText',
            'text': captionText,
            if (captionEntities.isNotEmpty) 'entities': captionEntities,
          },
      },
    });
  }

  void sendAnimation(
    String path, {
    String caption = '',
    List<Map<String, dynamic>> captionEntities = const [],
  }) {
    final captionText = captionEntities.isEmpty ? caption.trim() : caption;
    _submitPanelMessage({
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': {
        '@type': 'inputMessageAnimation',
        'animation': {
          '@type': 'inputAnimation',
          'animation': {'@type': 'inputFileLocal', 'path': path},
          'duration': 0,
          'width': 0,
          'height': 0,
        },
        if (captionText.trim().isNotEmpty)
          'caption': {
            '@type': 'formattedText',
            'text': captionText,
            if (captionEntities.isNotEmpty) 'entities': captionEntities,
          },
      },
    });
  }

  @visibleForTesting
  Map<String, dynamic> stickerMessageRequest(StickerItem sticker) {
    final remoteId = sticker.remoteId?.trim();
    final inputFile = remoteId != null && remoteId.isNotEmpty
        ? {'@type': 'inputFileRemote', 'id': remoteId}
        : {'@type': 'inputFileId', 'id': sticker.id};
    return _withPaidMessageOptions({
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': {
        '@type': 'inputMessageSticker',
        // The bundled TDLib schema carries sticker file metadata in an
        // inputSticker object rather than directly on inputMessageSticker.
        'sticker': {
          '@type': 'inputSticker',
          'sticker': inputFile,
          'width': sticker.width,
          'height': sticker.height,
        },
        'emoji': sticker.emoji,
      },
    });
  }

  void sendDocument(String path, {String caption = ''}) {
    _submitPanelMessage({
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': {
        '@type': 'inputMessageDocument',
        'document': {
          '@type': 'inputDocument',
          'document': {'@type': 'inputFileLocal', 'path': path},
        },
        if (caption.trim().isNotEmpty)
          'caption': {'@type': 'formattedText', 'text': caption.trim()},
      },
    });
  }

  void sendLocation(double latitude, double longitude) {
    _submitPanelMessage({
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': {
        '@type': 'inputMessageLocation',
        'location': {
          '@type': 'location',
          'latitude': latitude,
          'longitude': longitude,
          'horizontal_accuracy': 0,
        },
      },
    });
  }

  Future<bool> sendVenue({
    required double latitude,
    required double longitude,
    required String title,
    required String address,
  }) async {
    final venueTitle = title.trim();
    if (venueTitle.isEmpty) return false;
    try {
      final stamped = _withReplyAnchor(
        _withPaidMessageOptions({
          '@type': 'sendMessage',
          'chat_id': chatId,
          'input_message_content': {
            '@type': 'inputMessageVenue',
            'venue': {
              '@type': 'venue',
              'location': {
                '@type': 'location',
                'latitude': latitude,
                'longitude': longitude,
                'horizontal_accuracy': 0,
              },
              'title': venueTitle,
              'address': address.trim(),
              'provider': '',
              'id': '',
              'type': '',
            },
          },
        }),
      );
      await _client.query(stamped.request);
      _consumeReplyAnchorIfCurrent(stamped.revision);
      return true;
    } catch (error) {
      _publishSendFailure(
        ChatSendFailure.fromError(
          error,
          paidMessageStarCount: paidMessageStarCount,
        ),
      );
      return false;
    }
  }

  Future<bool> sendContact(MessageContactCard contact) async {
    if (contact.phoneNumber.trim().isEmpty) return false;
    try {
      final stamped = _withReplyAnchor(
        _withPaidMessageOptions({
          '@type': 'sendMessage',
          'chat_id': chatId,
          'input_message_content': {
            '@type': 'inputMessageContact',
            'contact': {
              '@type': 'contact',
              'phone_number': contact.phoneNumber,
              'first_name': contact.firstName,
              'last_name': contact.lastName,
              'vcard': contact.vcard,
              'user_id': contact.userId,
            },
          },
        }),
      );
      await _client.query(stamped.request);
      _consumeReplyAnchorIfCurrent(stamped.revision);
      return true;
    } catch (error) {
      _publishSendFailure(
        ChatSendFailure.fromError(
          error,
          paidMessageStarCount: paidMessageStarCount,
        ),
      );
      return false;
    }
  }

  Future<bool> sendVideoNote(
    String path,
    int duration, {
    MessageSendConfiguration sendConfiguration =
        const MessageSendConfiguration(),
  }) async {
    try {
      final stamped = _withReplyAnchor(
        _withPaidMessageOptions({
          '@type': 'sendMessage',
          'chat_id': chatId,
          'input_message_content': {
            '@type': 'inputMessageVideoNote',
            'video_note': {
              '@type': 'inputVideoNote',
              'video_note': {'@type': 'inputFileLocal', 'path': path},
              'duration': duration,
              'length': 0,
            },
            'self_destruct_type': ?sendConfiguration.selfDestructType,
          },
        }, sendConfiguration: sendConfiguration),
      );
      await _client.query(stamped.request);
      _consumeReplyAnchorIfCurrent(stamped.revision);
      return true;
    } catch (error) {
      debugPrint('Failed to send video note: $error');
      _publishSendFailure(
        ChatSendFailure.fromError(
          error,
          paidMessageStarCount: paidMessageStarCount,
        ),
      );
      return false;
    }
  }

  /// 音频: send a picked audio file as a music message (TDLib computes metadata).
  void sendAudio(String path) {
    _submitPanelMessage({
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': {
        '@type': 'inputMessageAudio',
        'audio': {
          '@type': 'inputAudio',
          'audio': {'@type': 'inputFileLocal', 'path': path},
          'duration': 0,
          'title': '',
          'performer': '',
        },
      },
    });
  }

  /// 音频搜索: send a clean copy of an existing Telegram audio message.
  Future<void> sendAudioFromMessage(
    int sourceChatId,
    ChatMessage message,
  ) async {
    await assertForwardAllowed(
      query: _client.query,
      fromChatId: sourceChatId,
      messageIds: [message.id],
      options: const ForwardOptions(removeSender: true),
    );
    final music = message.music;
    final fileId = music?.file?.id;
    if (music != null && fileId != null && fileId > 0) {
      try {
        await _client.query(
          _withPaidMessageOptions({
            '@type': 'sendMessage',
            'chat_id': chatId,
            'input_message_content': {
              '@type': 'inputMessageAudio',
              'audio': {
                '@type': 'inputAudio',
                'audio': {'@type': 'inputFileId', 'id': fileId},
                'duration': music.duration,
                'title': music.title,
                'performer': music.performer ?? '',
              },
            },
          }),
        );
        return;
      } catch (_) {}
    }
    await _client.query(
      _withPaidMessageOptions({
        '@type': 'forwardMessages',
        'chat_id': chatId,
        'from_chat_id': sourceChatId,
        'message_ids': [message.id],
        'options': {'@type': 'messageSendOptions'},
        'send_copy': true,
        'remove_caption': false,
      }),
    );
  }

  /// 清单: send a checklist (to-do list). Creating checklists needs Premium.
  void sendChecklist(ChecklistComposerResult draft) {
    if (draft.title.trim().isEmpty || draft.tasks.isEmpty) return;
    _submitPanelMessage({
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': {
        '@type': 'inputMessageChecklist',
        'checklist': ChecklistRequests.inputChecklist(draft),
      },
    });
  }

  Future<void> editChecklist(
    ChatMessage message,
    ChecklistComposerResult draft,
  ) async {
    final checklist = message.checklist;
    if (checklist == null) return;
    await _client.query(
      ChecklistRequests.edit(
        chatId: chatId,
        messageId: message.id,
        original: checklist,
        draft: draft,
      ),
    );
    await _refreshMessage(message.id);
  }

  Future<int> pollAnswerCountMax() async {
    try {
      final option = await _client.query({
        '@type': 'getOption',
        'name': 'poll_answer_count_max',
      });
      return (option.integer('value') ?? 30).clamp(2, 100);
    } catch (_) {
      return 30;
    }
  }

  Future<bool> sendPoll(PollComposerResult draft) async {
    final question = draft.question.trim();
    final options = draft.options
        .where((option) => option.text.trim().isNotEmpty)
        .toList(growable: false);
    if (question.isEmpty || options.length < 2) return false;
    if (draft.isQuiz && draft.correctOptionIndexes.isEmpty) return false;
    try {
      final stamped = _withReplyAnchor(
        _withPaidMessageOptions({
          '@type': 'sendMessage',
          'chat_id': chatId,
          'input_message_content': {
            '@type': 'inputMessagePoll',
            'question': {'@type': 'formattedText', 'text': question},
            'options': [
              for (final option in options)
                {
                  '@type': 'inputPollOption',
                  'text': {
                    '@type': 'formattedText',
                    'text': option.text.trim(),
                  },
                  if (option.mediaPath case final path?)
                    'media': _inputPollPhoto(path),
                },
            ],
            if (draft.description.trim().isNotEmpty)
              'description': {
                '@type': 'formattedText',
                'text': draft.description.trim(),
              },
            if (draft.pollMediaPath case final path?)
              'media': _inputPollPhoto(path),
            'is_anonymous': draft.isAnonymous,
            'allows_multiple_answers': draft.allowsMultipleAnswers,
            'allows_revoting': draft.allowsRevoting,
            'shuffle_options': draft.shuffleOptions,
            'hide_results_until_closes': draft.hideResultsUntilCloses,
            'type': draft.isQuiz
                ? {
                    '@type': 'inputPollTypeQuiz',
                    'correct_option_ids': draft.correctOptionIndexes.toList()
                      ..sort(),
                    'explanation': {
                      '@type': 'formattedText',
                      'text': draft.explanation.trim(),
                    },
                  }
                : {
                    '@type': 'inputPollTypeRegular',
                    'allow_adding_options': draft.allowAddingOptions,
                  },
            'open_period': draft.openPeriod,
          },
        }),
      );
      await _client.query(stamped.request);
      _consumeReplyAnchorIfCurrent(stamped.revision);
      return true;
    } catch (error) {
      debugPrint('Failed to send poll: $error');
      _publishSendFailure(
        ChatSendFailure.fromError(
          error,
          paidMessageStarCount: paidMessageStarCount,
        ),
      );
      return false;
    }
  }

  Map<String, dynamic> _inputPollPhoto(String path) => {
    '@type': 'inputPollMediaPhoto',
    'photo': {
      '@type': 'inputPhoto',
      'photo': {'@type': 'inputFileLocal', 'path': path},
    },
  };

  Future<void> addPollOption(ChatMessage message, String text) async {
    final value = text.trim();
    if (message.poll == null || value.isEmpty) return;
    await _client.query({
      '@type': 'addPollOption',
      'chat_id': chatId,
      'message_id': message.id,
      'option': {
        '@type': 'inputPollOption',
        'text': {'@type': 'formattedText', 'text': value},
      },
    });
    await _refreshMessage(message.id);
  }

  Future<void> recognizeSpeech(ChatMessage message) async {
    if (!canUseSpeechRecognition) {
      throw StateError('SPEECH_RECOGNITION_UNAVAILABLE');
    }
    final properties = await _client.query({
      '@type': 'getMessageProperties',
      'chat_id': chatId,
      'message_id': message.id,
    });
    if (properties.boolean('can_recognize_speech') != true) {
      _speechRecognitionEligibility[message.id] = false;
      for (final target in _messageRefs(message.id)) {
        target.canRecognizeSpeech = false;
      }
      _notifyLocalizedMessages([message.id]);
      throw StateError('SPEECH_RECOGNITION_UNAVAILABLE');
    }
    await _client.query({
      '@type': 'recognizeSpeech',
      'chat_id': chatId,
      'message_id': message.id,
    });
    await _refreshMessage(message.id);
  }

  Future<Map<String, dynamic>> pollVoteStatistics(
    ChatMessage message, {
    required bool isDark,
  }) => _client.query({
    '@type': 'getPollVoteStatistics',
    'chat_id': chatId,
    'message_id': message.id,
    'is_dark': isDark,
  });

  Future<List<Map<String, dynamic>>> pollVoters(
    ChatMessage message,
    int optionIndex, {
    int offset = 0,
  }) async {
    final response = await _client.query({
      '@type': 'getPollVoters',
      'chat_id': chatId,
      'message_id': message.id,
      'option_id': optionIndex,
      'offset': offset,
      'limit': 50,
    });
    return response.objects('voters') ?? const <Map<String, dynamic>>[];
  }

  Future<void> votePoll(ChatMessage message, int optionIndex) async {
    final poll = message.poll;
    if (poll == null || poll.isClosed) return;
    final selected = <int>[...poll.chosenOptionIndexes];
    if (poll.allowsMultipleAnswers) {
      selected.contains(optionIndex)
          ? selected.remove(optionIndex)
          : selected.add(optionIndex);
    } else if (selected.length == 1 && selected.first == optionIndex) {
      if (!poll.allowsRevoting) return;
      selected.clear();
    } else {
      selected
        ..clear()
        ..add(optionIndex);
    }
    await _client.query({
      '@type': 'setPollAnswer',
      'chat_id': chatId,
      'message_id': message.id,
      'option_ids': selected,
    });
    await _refreshMessage(message.id);
  }

  Future<void> stopPoll(ChatMessage message) async {
    if (message.poll == null || message.poll!.isClosed) return;
    await _client.query({
      '@type': 'stopPoll',
      'chat_id': chatId,
      'message_id': message.id,
    });
    await _refreshMessage(message.id);
  }

  Future<void> toggleChecklistTask(
    ChatMessage message,
    MessageChecklistTask task,
  ) async {
    final checklist = message.checklist;
    if (checklist == null || !checklist.canMarkTasksAsDone) return;
    await _client.query({
      '@type': 'markChecklistTasksAsDone',
      'chat_id': chatId,
      'message_id': message.id,
      'marked_as_done_task_ids': task.isCompleted ? <int>[] : [task.id],
      'marked_as_not_done_task_ids': task.isCompleted ? [task.id] : <int>[],
    });
    await _refreshMessage(message.id);
  }

  Future<void> addChecklistTask(ChatMessage message, String text) async {
    final checklist = message.checklist;
    final value = text.trim();
    if (checklist == null || !checklist.canAddTasks || value.isEmpty) return;
    final nextId =
        checklist.tasks.fold<int>(
          0,
          (current, task) => math.max(current, task.id),
        ) +
        1;
    await _client.query({
      '@type': 'addChecklistTasks',
      'chat_id': chatId,
      'message_id': message.id,
      'tasks': [
        {
          '@type': 'inputChecklistTask',
          'id': nextId,
          'text': {'@type': 'formattedText', 'text': value},
        },
      ],
    });
    await _refreshMessage(message.id);
  }

  /// Re-sends the same content (the "+1" quick repeat) — only plain text and
  /// photos; the badge that calls this is gated to those kinds too.
  void repeatMessage(ChatMessage message) {
    if (hasProtectedContent) return;
    // Photo: send a clean copy (forwardMessages send_copy drops the "转发"
    // header and works regardless of the original file's upload state).
    if (message.isPhoto && message.image != null) {
      _submitMessageRequestWithoutWaiting({
        '@type': 'forwardMessages',
        'chat_id': chatId,
        'from_chat_id': chatId,
        'message_ids': [message.id],
        'send_copy': true,
      });
      return;
    }
    if (!message.isPlainText) return;
    final text = message.text.trim();
    if (text.isEmpty) return;
    _submitMessageRequestWithoutWaiting({
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': {
        '@type': 'inputMessageText',
        'text': {'@type': 'formattedText', 'text': text},
      },
    });
  }

  bool sendKeyboardButtonText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    _submitMessageRequestWithoutWaiting({
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': {
        '@type': 'inputMessageText',
        'text': {'@type': 'formattedText', 'text': trimmed},
      },
    });
    return true;
  }

  bool sendCommand(String command) {
    final trimmed = command.trim();
    if (!trimmed.startsWith('/')) return false;
    _sendText(trimmed);
    return true;
  }

  Future<Map<String, dynamic>> answerCallbackButton(
    int messageId,
    MessageButton button,
  ) async {
    final answer = await _client.query({
      '@type': 'getCallbackQueryAnswer',
      'chat_id': chatId,
      'message_id': messageId,
      'payload': {
        '@type': 'callbackQueryPayloadData',
        'data': button.data ?? '',
      },
    });
    await _refreshMessage(messageId);
    unawaited(
      Future<void>.delayed(
        const Duration(milliseconds: 700),
        () => _refreshMessage(messageId),
      ),
    );
    return answer;
  }

  Future<void> _refreshMessage(int messageId) async {
    if (_isDisposed) return;
    try {
      final raw = await _client.query({
        '@type': 'getMessage',
        'chat_id': chatId,
        'message_id': messageId,
      });
      if (_isDisposed) return;
      final refreshed = TDParse.message(raw);
      if (refreshed == null) return;
      _merge([refreshed]);
      _resolveRichMessagesIfNeeded([refreshed]);
      _resolveSendersIfNeeded([refreshed]);
      _resolveRepliesIfNeeded([refreshed]);
      _resolveForwardsIfNeeded([refreshed]);
      _resolveServiceUsersIfNeeded([refreshed]);
    } catch (_) {
      // Live TDLib updates remain the source of truth if a direct refresh fails.
    }
  }

  Future<MessageTranslationResult> translateMessage(
    int messageId,
    String toLanguageCode,
  ) async {
    _setTranslationLoading(messageId, true);
    try {
      final formatted = await _client.query({
        '@type': 'translateMessageText',
        'chat_id': chatId,
        'message_id': messageId,
        'to_language_code': toLanguageCode,
      });
      final result = (
        text: formatted.str('text') ?? '',
        entities: TDParse.textEntities(formatted),
        languageCode: toLanguageCode,
      );
      _replaceTranslation(
        messageId,
        result.text,
        result.entities,
        result.languageCode,
      );
      return result;
    } catch (_) {
      _setTranslationLoading(messageId, false);
      rethrow;
    }
  }

  Future<String> translateText(String text, String toLanguageCode) async {
    final formatted = await _client.query({
      '@type': 'translateText',
      'text': {
        '@type': 'formattedText',
        'text': text,
        'entities': const <Map<String, dynamic>>[],
      },
      'to_language_code': toLanguageCode,
    });
    return formatted.str('text') ?? '';
  }

  Future<void> summarizeMessage(
    ChatMessage message, {
    String translateToLanguageCode = '',
    String tone = 'neutral',
  }) async {
    if (!canUseAiSummary ||
        message.summaryLanguageCode.isEmpty ||
        message.aiSummaryLoading) {
      return;
    }
    final targets = _messageRefs(message.id);
    for (final target in targets) {
      target.aiSummaryLoading = true;
    }
    _notifyLocalizedMessages([message.id]);
    try {
      final result = await telegramAi.summarize(
        chatId: chatId,
        messageId: message.id,
        translateToLanguageCode: translateToLanguageCode,
        tone: tone,
      );
      final formatted = result.toTdJson();
      for (final target in _messageRefs(message.id)) {
        target.aiSummaryText = result.text;
        target.aiSummaryEntities = TDParse.textEntities(formatted);
        target.aiSummaryLoading = false;
      }
      _notifyLocalizedMessages([message.id]);
    } catch (_) {
      for (final target in _messageRefs(message.id)) {
        target.aiSummaryLoading = false;
      }
      _notifyLocalizedMessages([message.id]);
      rethrow;
    }
  }

  Future<MessageTranslationResult> translateMessageExternally(
    int messageId,
    String toLanguageCode,
    Future<String> Function() translate, {
    bool showLoading = true,
  }) async {
    if (showLoading) _setTranslationLoading(messageId, true);
    try {
      final translated = await translate();
      _replaceTranslation(messageId, translated, const [], toLanguageCode);
      return (
        text: translated,
        entities: const <MessageTextEntity>[],
        languageCode: toLanguageCode,
      );
    } catch (_) {
      if (showLoading) _setTranslationLoading(messageId, false);
      rethrow;
    }
  }
}
