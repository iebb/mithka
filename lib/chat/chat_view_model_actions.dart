part of 'chat_view_model.dart';

extension ChatViewModelActions on ChatViewModel {
  Future<void> forward(
    int messageId,
    int targetChatId, {
    ForwardOptions options = const ForwardOptions(),
  }) async {
    await forwardMany([messageId], targetChatId, options: options);
  }

  Future<void> forwardMany(
    List<int> messageIds,
    int targetChatId, {
    ForwardOptions options = const ForwardOptions(),
  }) async {
    // Protected source + the kept-messages toggle: re-send as a copy
    // (the reference client ForwardProtectedAsCopy). The plan's counts surface
    // through ProtectedForwardResult below; a fully-uncopyable selection
    // still throws so the UI keeps its single failure path.
    if (hasProtectedContent &&
        MessageHistorySettings.shared.forwardProtectedAsCopy) {
      final plan = await forwardProtectedAsCopy(
        query: _client.query,
        fromChatId: chatId,
        messageIds: messageIds,
        targetChatId: targetChatId,
        topicId: targetChatId == chatId ? _forumTopicRef : null,
      );
      protectedForwardLastPlan = plan;
      if (plan.anythingSent) return;
      throw const ForwardBlockedException();
    }
    if (hasProtectedContent) throw const ForwardBlockedException();
    final forwardQuery = forwardQueryForOwner(
      _client,
      accountSlot: _accountSlot,
      clientId: _accountClientId,
    );
    var richText = options.richText;
    // Second gate: entry points already hide the option for non-Premium, but
    // forwardMany is callable without them (bot relay, shortcuts), so the
    // entitlement is re-checked here against the live TDLib state.
    if (richText) {
      final user = await forwardQuery({'@type': 'getMe'});
      richText = user.boolean('is_premium') ?? false;
    }
    if (!richText) {
      await forwardMessagesWithOptions(
        client: _client,
        targetChatId: targetChatId,
        fromChatId: chatId,
        messageIds: messageIds,
        topicId: targetChatId == chatId ? _forumTopicRef : null,
        options: options,
        query: forwardQuery,
      );
      return;
    }
    // Process the selection in order so a mix of converted and ordinary
    // messages still arrives in the order the user picked them: ordinary
    // messages are flushed as contiguous forwardMessages batches before the
    // next converted re-send.
    final byId = {for (final message in _allMessages) message.id: message};
    final pendingIds = <int>[];
    Future<void> flush() async {
      if (pendingIds.isEmpty) return;
      final ids = List<int>.of(pendingIds);
      pendingIds.clear();
      await forwardMessagesWithOptions(
        client: _client,
        targetChatId: targetChatId,
        fromChatId: chatId,
        messageIds: ids,
        topicId: targetChatId == chatId ? _forumTopicRef : null,
        options: options,
        query: forwardQuery,
      );
    }

    for (final id in messageIds) {
      final message = byId[id];
      // Markdown detection is best-effort: any message that fails detection
      // or conversion simply falls back to the regular forward batch.
      if (message == null ||
          !forwardMarkdownOfferForMessage(message).available) {
        pendingIds.add(id);
        continue;
      }
      // Flush the ordinary messages selected before this one so the re-send
      // lands after them; if the conversion fails the message rejoins the
      // pending batch and order is still preserved.
      await flush();
      final sent = await sendMarkdownRichTextForward(
        query: forwardQuery,
        fromChatId: chatId,
        messageId: id,
        targetChatId: targetChatId,
        text: message.text,
        topicId: targetChatId == chatId ? _forumTopicRef : null,
      );
      if (!sent) pendingIds.add(id);
    }
    await flush();
  }

  Future<void> saveToFavorites(int messageId) async {
    await saveToFavoritesMany([messageId]);
  }

  Future<void> saveToFavoritesMany(List<int> messageIds) async {
    if (messageIds.isEmpty) return;
    if (hasProtectedContent) throw const ForwardBlockedException();
    final me = await _client.query({'@type': 'getMe'});
    final myId = me.int64('id');
    if (myId == null) throw TdError({'message': 'Missing current user id'});
    final saved = await _client.query({
      '@type': 'createPrivateChat',
      'user_id': myId,
      'force': false,
    });
    final savedChatId = saved.int64('id');
    if (savedChatId == null) {
      throw TdError({'message': 'Missing Saved Messages chat id'});
    }
    await forwardMessagesWithOptions(
      client: _client,
      targetChatId: savedChatId,
      fromChatId: chatId,
      messageIds: messageIds,
    );
  }

  void saveFavoriteSticker(int fileId) {
    _client.send({
      '@type': 'addFavoriteSticker',
      'sticker': {'@type': 'inputFileId', 'id': fileId},
    });
  }

  Future<void> deleteMessage(int id) {
    return deleteMessages([id]);
  }

  Future<void> deleteMessages(List<int> ids) async {
    if (ids.isEmpty) return;
    await _client.query({
      '@type': 'deleteMessages',
      'chat_id': chatId,
      'message_ids': ids,
      'revoke': true,
    });
    _removeMessages(ids);
  }

  Future<void> deleteMessagesFromSender(ChatMessage message) async {
    final senderId = message.senderId;
    final sender = _messageSenderFor(message);
    if (senderId == null || sender == null) {
      throw TdError({'message': 'Missing message sender'});
    }
    await _client.query({
      '@type': 'deleteChatMessagesBySender',
      'chat_id': chatId,
      'sender_id': sender,
    });
    final ids = _allMessages
        .where((candidate) => candidate.senderId == senderId)
        .map((candidate) => candidate.id)
        .toList();
    _removeMessages(ids);
  }

  Future<void> reportMessage(ChatMessage message) async {
    await _reportTelegramContent(message);
  }

  /// Reports one sender's reaction on a message. The caller must have checked
  /// the message's `can_report_reactions` property first; the write stays on
  /// the client that owns this pane, so a dialog confirmed after an account
  /// switch cannot report into the replacement account.
  Future<void> reportReaction(ChatMessage message, int senderId) async {
    await _client.queryTo({
      '@type': 'reportMessageReactions',
      'chat_id': chatId,
      'message_id': message.id,
      'sender_id': senderId > 0
          ? {'@type': 'messageSenderUser', 'user_id': senderId}
          : {'@type': 'messageSenderChat', 'chat_id': senderId},
    }, _accountClientId);
  }

  Future<void> blockSender(ChatMessage message) async {
    final senderId = message.senderId;
    final sender = _messageSenderFor(message);
    if (senderId == null || sender == null) {
      throw TdError({'message': 'Missing message sender'});
    }
    _blockedSenderIds.add(senderId);
    KeywordBlocker.shared.addBlockedSender(senderId);
    _applyKeywordFilter();
    try {
      await _client.query({
        '@type': 'setMessageSenderBlockList',
        'sender_id': sender,
        'block_list': {'@type': 'blockListMain'},
      });
    } catch (_) {
      _blockedSenderIds.remove(senderId);
      KeywordBlocker.shared.removeBlockedSender(senderId);
      _applyKeywordFilter();
      rethrow;
    }
  }

  Future<void> blockAndReportSender(ChatMessage message) async {
    await blockSender(message);
    unawaited(_reportTelegramContent(message).catchError((_) {}));
  }

  Map<String, dynamic>? _messageSenderFor(ChatMessage message) {
    final senderId = message.senderId;
    if (senderId == null) return null;
    if (senderId > 0) {
      return {'@type': 'messageSenderUser', 'user_id': senderId};
    }
    return {'@type': 'messageSenderChat', 'chat_id': senderId};
  }

  Future<void> _reportTelegramContent(ChatMessage message) async {
    final sender = _messageSenderFor(message);
    final base = <String, dynamic>{
      '@type': 'reportChat',
      'chat_id': chatId,
      'message_ids': [message.id],
      'sender_id': sender,
      'option_id': '',
      'text': 'Objectionable or abusive content reported from Mithka.',
    };
    final result = await _client.query(base);
    if (result.type != 'reportChatResultOptionRequired') return;
    final options = result.objects('options') ?? const <Map<String, dynamic>>[];
    if (options.isEmpty) return;
    await _client.query({...base, 'option_id': options.first['id'] ?? ''});
  }

  Future<void> editMessageText(
    int id,
    String text, {
    List<Map<String, dynamic>> entities = const [],
  }) async {
    if (text.trim().isEmpty) return;
    final parsed = TDParse.textEntities({
      '@type': 'formattedText',
      'text': text,
      'entities': entities,
    });
    final previewUrl = LinkPreviewFixer.shared.previewUrl(
      text,
      entities: parsed,
    );
    await _client.query({
      '@type': 'editMessageText',
      'chat_id': chatId,
      'message_id': id,
      'input_message_content': {
        '@type': 'inputMessageText',
        'text': {
          '@type': 'formattedText',
          'text': text,
          if (entities.isNotEmpty) 'entities': entities,
        },
        'link_preview_options': {
          '@type': 'linkPreviewOptions',
          'is_disabled': false,
          'url': ?previewUrl,
        },
        'clear_draft': false,
      },
    });
    _replaceText(
      id,
      text,
      edited: true,
      entities: parsed,
      customEmoji: TDParse.customEmojiEntitiesFrom(parsed),
    );
  }

  Future<void> editMessageCaption(
    int id,
    String caption, {
    List<Map<String, dynamic>> entities = const [],
  }) async {
    await _client.query({
      '@type': 'editMessageCaption',
      'chat_id': chatId,
      'message_id': id,
      'caption': {
        '@type': 'formattedText',
        'text': caption,
        if (entities.isNotEmpty) 'entities': entities,
      },
    });
    _replaceText(
      id,
      caption,
      edited: true,
      entities: TDParse.textEntities({
        '@type': 'formattedText',
        'text': caption,
        'entities': entities,
      }),
      customEmoji: TDParse.customEmojiEntitiesFrom(
        TDParse.textEntities({
          '@type': 'formattedText',
          'text': caption,
          'entities': entities,
        }),
      ),
    );
  }

  Future<void> editMessageMedia(
    int id,
    OutgoingAttachment attachment, {
    required String caption,
    List<Map<String, dynamic>> entities = const [],
  }) async {
    attachment = await fitPhotoToTelegramLimits(attachment);
    await _client.query({
      '@type': 'editMessageMedia',
      'chat_id': chatId,
      'message_id': id,
      'input_message_content': attachmentInputMessageContent(
        attachment,
        caption: caption,
        captionEntities: entities,
      ),
    });
  }

  // MARK: - Paging

  Future<MessageReactionAvailability> messageReactionAvailability(
    int messageId, {
    int rowSize = 7,
  }) async {
    try {
      final responses = await Future.wait([
        _client.queryTo({
          '@type': 'getMessageAvailableReactions',
          'chat_id': chatId,
          'message_id': messageId,
          'row_size': rowSize.clamp(5, 25),
        }, _accountClientId),
        _client.queryTo({
          '@type': 'getOption',
          'name': 'is_premium',
        }, _accountClientId),
      ]);
      return MessageReactionAvailability.fromTd(
        responses.first,
        isPremium: responses.last.boolean('value') ?? false,
      );
    } catch (_) {
      if (!_usesBotApiBackend) rethrow;
      // The direct Bot API has no per-message availability method. Keep the
      // picker hidden instead of presenting reactions that this message may
      // reject. Existing reaction buckets remain toggleable below, where the
      // awaited Bot API send is the authoritative availability check.
      return MessageReactionAvailability.fallback(
        choices: const <QuickReactionChoice>[],
        allowArbitraryCustom: false,
      );
    }
  }

  /// Whether Telegram allows reporting a reaction on [messageId]
  /// (`messageProperties.can_report_reactions`).
  ///
  /// This is a property of the message, not a field of the `message` object:
  /// the pinned TDLib schema returns it only from `getMessageProperties`, and
  /// `reportMessageReactions` depends on that same property. Fail closed — an
  /// error or a switch away from this pane's account hides the action.
  Future<bool> canReportMessageReactions(int messageId) async {
    try {
      final properties = await _client.queryTo({
        '@type': 'getMessageProperties',
        'chat_id': chatId,
        'message_id': messageId,
      }, _accountClientId);
      if (_isDisposed || !isAccountCurrent) return false;
      return properties.boolean('can_report_reactions') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Per-message action availability from `messageProperties`: whether a
  /// shareable link exists (`can_get_link`) and whether Telegram accepts a
  /// reply in this chat (`can_be_replied`). Both live only on the server
  /// object, so one query answers the menu; a property error propagates and
  /// the caller keeps both entries hidden.
  Future<({bool canGetLink, bool canBeReplied})> messageActionAvailability(
    int messageId,
  ) async {
    final properties = await _client.queryTo({
      '@type': 'getMessageProperties',
      'chat_id': chatId,
      'message_id': messageId,
    }, _accountClientId);
    return (
      canGetLink: properties.boolean('can_get_link') ?? false,
      canBeReplied: properties.boolean('can_be_replied') ?? false,
    );
  }

  /// The HTTPS link TDLib generated for the message. Returns the raw
  /// `messageLink.link`; [getMessageLink] is authoritative for when a link
  /// exists, so a plain error propagates to the action's failure toast.
  Future<String> messageLink(int messageId) async {
    final link = await _client.queryTo({
      '@type': 'getMessageLink',
      'chat_id': chatId,
      'message_id': messageId,
      'media_timestamp': 0,
      'checklist_task_id': 0,
      'poll_option_id': '',
      'for_album': false,
      'in_message_thread': false,
    }, _accountClientId);
    return link.str('link') ?? '';
  }

  Future<void> addReaction(int messageId, String emoji) =>
      _addReactionChoice(messageId, QuickReactionChoice.emoji(emoji));

  /// Custom (premium) emoji reaction.
  Future<void> addCustomReaction(int messageId, int customEmojiId) =>
      _addReactionChoice(messageId, QuickReactionChoice.custom(customEmojiId));

  Future<void> _addReactionChoice(
    int messageId,
    QuickReactionChoice requested,
  ) async {
    final availability = await messageReactionAvailability(messageId);
    final reaction = availability.canonicalChoice(requested);
    if (reaction == null) throw const MessageReactionUnavailableException();
    await _sendReactionChoice(messageId, reaction);
  }

  Future<void> _sendReactionChoice(
    int messageId,
    QuickReactionChoice reaction,
  ) async {
    await _client.queryTo({
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
    }, _accountClientId);
  }

  Future<void> toggleReaction(ChatMessage m, MessageReaction r) async {
    if (r.chosen) {
      // TDLib guarantees that a chosen reaction remains removable even when
      // the user can no longer add reactions to the message.
      await _client.queryTo({
        '@type': 'removeMessageReaction',
        'chat_id': chatId,
        'message_id': m.id,
        'reaction_type': r.type,
      }, _accountClientId);
    } else {
      final reaction = r.customEmojiId != 0
          ? QuickReactionChoice.custom(r.customEmojiId)
          : QuickReactionChoice.emoji(r.emoji ?? '');
      if (_usesBotApiBackend) {
        // A Bot API message can expose a reaction bucket even though the API
        // can't enumerate all reactions allowed for that individual message.
        // Let the server accept or reject that exact existing bucket.
        await _sendReactionChoice(m.id, reaction);
      } else {
        await _addReactionChoice(m.id, reaction);
      }
    }
  }

  Future<List<MessageReactionUser>> reactionUsers(
    ChatMessage message,
    MessageReaction reaction,
  ) async {
    final res = await _client.query({
      '@type': 'getMessageAddedReactions',
      'chat_id': chatId,
      'message_id': message.id,
      'reaction_type': reaction.type,
      'offset': '',
      'limit': 100,
    });
    final added = res.objects('reactions') ?? const <Map<String, dynamic>>[];
    final users = <MessageReactionUser>[];
    for (final item in added) {
      final senderId = _senderIdFromTd(item.obj('sender_id'));
      if (senderId == null) continue;
      final info = await _reactionSenderInfo(senderId);
      users.add(
        MessageReactionUser(
          senderId: senderId,
          title: info.name,
          photo: info.photo,
          date: item.integer('date') ?? 0,
          isDeleted: info.isDeleted,
        ),
      );
    }
    return users;
  }

  int? _senderIdFromTd(Map<String, dynamic>? sender) {
    return switch (sender?.type) {
      'messageSenderUser' => sender?.int64('user_id'),
      'messageSenderChat' => sender?.int64('chat_id'),
      _ => null,
    };
  }

  Future<_SenderInfo> _reactionSenderInfo(int senderId) async {
    final cached = _senderCache[senderId];
    if (cached != null) return cached;
    if (senderId > 0) {
      try {
        final user = await _client.query({
          '@type': 'getUser',
          'user_id': senderId,
        });
        return _SenderInfo(
          TDParse.userName(user),
          TDParse.smallPhoto(user.obj('profile_photo')),
          MemberRole.member,
          null,
          isDeleted: TDParse.isDeletedUser(user),
        );
      } catch (_) {
        return _SenderInfo(
          AppStrings.t(AppStringKeys.chatUserFallbackName, {
            'value1': senderId,
          }),
          null,
          MemberRole.member,
          null,
        );
      }
    }
    try {
      final chat = await _client.query({
        '@type': 'getChat',
        'chat_id': senderId,
      });
      return _SenderInfo(
        chat.str('title') ?? AppStrings.t(AppStringKeys.chatInfoGroupMembers),
        TDParse.smallPhoto(chat.obj('photo')),
        MemberRole.member,
        null,
      );
    } catch (_) {
      return _SenderInfo(
        AppStrings.t(AppStringKeys.chatInfoGroupMembers),
        null,
        MemberRole.member,
        null,
      );
    }
  }

  void _restartTypingTimer() {
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 6), () {
      if (_chatActions.isNotEmpty) {
        _chatActions.clear();
        _notifyComposerNeutral();
      }
    });
  }

  String _chatActionLabel(String type) {
    switch (type) {
      case 'chatActionRecordingVideo':
        return AppStrings.t(AppStringKeys.chatActionRecordingVideo);
      case 'chatActionUploadingVideo':
        return AppStrings.t(AppStringKeys.chatActionUploadingVideo);
      case 'chatActionRecordingVoiceNote':
        return AppStrings.t(AppStringKeys.chatActionRecordingVoice);
      case 'chatActionUploadingVoiceNote':
        return AppStrings.t(AppStringKeys.chatActionUploadingVoice);
      case 'chatActionUploadingPhoto':
        return AppStrings.t(AppStringKeys.chatActionUploadingPhoto);
      case 'chatActionUploadingDocument':
        return AppStrings.t(AppStringKeys.chatActionUploadingFile);
      case 'chatActionChoosingSticker':
        return AppStrings.t(AppStringKeys.chatActionChoosingSticker);
      case 'chatActionChoosingLocation':
        return AppStrings.t(AppStringKeys.chatActionChoosingLocation);
      case 'chatActionChoosingContact':
        return AppStrings.t(AppStringKeys.chatActionChoosingContact);
      case 'chatActionStartPlayingGame':
        return AppStrings.t(AppStringKeys.chatActionPlayingGame);
      case 'chatActionRecordingVideoNote':
        return AppStrings.t(AppStringKeys.chatActionRecordingVideoNote);
      case 'chatActionUploadingVideoNote':
        return AppStrings.t(AppStringKeys.chatActionUploadingVideoNote);
      case 'chatActionWatchingAnimations':
        return AppStrings.t(AppStringKeys.chatActionWatchingAnimations);
      case 'chatActionTyping':
      default:
        return AppStrings.t(AppStringKeys.chatTyping);
    }
  }

  // MARK: - 引用 reply-quote resolution
}
