import 'dart:async';

import 'package:flutter/foundation.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';

/// Runtime availability for Telegram Business features.
///
/// TDLib exposes the supported feature set separately from the current
/// account's Premium state. Keeping both values prevents a client upgrade from
/// showing controls for a feature that isn't present in the bundled TDLib.
class BusinessCapabilities {
  const BusinessCapabilities({required this.isPremium, required this.features});

  final bool isPremium;
  final Set<String> features;

  bool supports(String tdType) => features.contains(tdType);
  bool canUse(String tdType) => isPremium && supports(tdType);
}

/// Business feature constructors implemented by the TDLib runtime bundled with
/// Mithka and surfaced by the settings UI.
///
/// `getBusinessFeatures` is server-backed and can temporarily fail or return an
/// empty list while account data is being refreshed. That must not turn a
/// transient response into an empty settings screen. Premium is still checked
/// separately before any mutation is sent.
const bundledBusinessFeatures = <String>{
  'businessFeatureLocation',
  'businessFeatureOpeningHours',
  'businessFeatureStartPage',
  'businessFeatureQuickReplies',
  'businessFeatureGreetingMessage',
  'businessFeatureAwayMessage',
  'businessFeatureAccountLinks',
  'businessFeatureBots',
  'businessFeatureEmojiStatus',
};

@visibleForTesting
Set<String> resolvedBusinessFeatures(Map<String, dynamic>? response) {
  final advertised = <String>{
    for (final feature
        in response?.objects('features') ?? const <Map<String, dynamic>>[])
      if (feature.type != null) feature.type!,
  };
  return advertised.isEmpty ? bundledBusinessFeatures : advertised;
}

class BusinessRecipientsDraft {
  const BusinessRecipientsDraft({
    this.chatIds = const <int>[],
    this.excludedChatIds = const <int>[],
    this.selectExistingChats = true,
    this.selectNewChats = true,
    this.selectContacts = true,
    this.selectNonContacts = true,
    this.excludeSelected = false,
  });

  factory BusinessRecipientsDraft.fromJson(Map<String, dynamic>? value) {
    return BusinessRecipientsDraft(
      chatIds: value?.int64Array('chat_ids') ?? const <int>[],
      excludedChatIds: value?.int64Array('excluded_chat_ids') ?? const <int>[],
      selectExistingChats: value?.boolean('select_existing_chats') ?? true,
      selectNewChats: value?.boolean('select_new_chats') ?? true,
      selectContacts: value?.boolean('select_contacts') ?? true,
      selectNonContacts: value?.boolean('select_non_contacts') ?? true,
      excludeSelected: value?.boolean('exclude_selected') ?? false,
    );
  }

  final List<int> chatIds;
  final List<int> excludedChatIds;
  final bool selectExistingChats;
  final bool selectNewChats;
  final bool selectContacts;
  final bool selectNonContacts;
  final bool excludeSelected;

  Map<String, dynamic> toJson({bool allowExcludedChats = false}) => {
    '@type': 'businessRecipients',
    'chat_ids': chatIds,
    'excluded_chat_ids': allowExcludedChats ? excludedChatIds : const <int>[],
    'select_existing_chats': selectExistingChats,
    'select_new_chats': selectNewChats,
    'select_contacts': selectContacts,
    'select_non_contacts': selectNonContacts,
    'exclude_selected': excludeSelected,
  };

  BusinessRecipientsDraft copyWith({
    List<int>? chatIds,
    List<int>? excludedChatIds,
    bool? selectExistingChats,
    bool? selectNewChats,
    bool? selectContacts,
    bool? selectNonContacts,
    bool? excludeSelected,
  }) {
    return BusinessRecipientsDraft(
      chatIds: chatIds ?? this.chatIds,
      excludedChatIds: excludedChatIds ?? this.excludedChatIds,
      selectExistingChats: selectExistingChats ?? this.selectExistingChats,
      selectNewChats: selectNewChats ?? this.selectNewChats,
      selectContacts: selectContacts ?? this.selectContacts,
      selectNonContacts: selectNonContacts ?? this.selectNonContacts,
      excludeSelected: excludeSelected ?? this.excludeSelected,
    );
  }
}

class BusinessBotRightsDraft {
  const BusinessBotRightsDraft({
    this.canReply = true,
    this.canReadMessages = true,
    this.canDeleteSentMessages = false,
    this.canDeleteAllMessages = false,
    this.canEditName = false,
    this.canEditBio = false,
    this.canEditProfilePhoto = false,
    this.canEditUsername = false,
    this.canViewGiftsAndStars = false,
    this.canSellGifts = false,
    this.canChangeGiftSettings = false,
    this.canTransferAndUpgradeGifts = false,
    this.canTransferStars = false,
    this.canManageStories = false,
  });

  factory BusinessBotRightsDraft.fromJson(Map<String, dynamic>? value) {
    return BusinessBotRightsDraft(
      canReply: value?.boolean('can_reply') ?? true,
      canReadMessages: value?.boolean('can_read_messages') ?? true,
      canDeleteSentMessages:
          value?.boolean('can_delete_sent_messages') ?? false,
      canDeleteAllMessages: value?.boolean('can_delete_all_messages') ?? false,
      canEditName: value?.boolean('can_edit_name') ?? false,
      canEditBio: value?.boolean('can_edit_bio') ?? false,
      canEditProfilePhoto: value?.boolean('can_edit_profile_photo') ?? false,
      canEditUsername: value?.boolean('can_edit_username') ?? false,
      canViewGiftsAndStars: value?.boolean('can_view_gifts_and_stars') ?? false,
      canSellGifts: value?.boolean('can_sell_gifts') ?? false,
      canChangeGiftSettings:
          value?.boolean('can_change_gift_settings') ?? false,
      canTransferAndUpgradeGifts:
          value?.boolean('can_transfer_and_upgrade_gifts') ?? false,
      canTransferStars: value?.boolean('can_transfer_stars') ?? false,
      canManageStories: value?.boolean('can_manage_stories') ?? false,
    );
  }

  final bool canReply;
  final bool canReadMessages;
  final bool canDeleteSentMessages;
  final bool canDeleteAllMessages;
  final bool canEditName;
  final bool canEditBio;
  final bool canEditProfilePhoto;
  final bool canEditUsername;
  final bool canViewGiftsAndStars;
  final bool canSellGifts;
  final bool canChangeGiftSettings;
  final bool canTransferAndUpgradeGifts;
  final bool canTransferStars;
  final bool canManageStories;

  Map<String, dynamic> toJson() => {
    '@type': 'businessBotRights',
    'can_reply': canReply,
    'can_read_messages': canReadMessages,
    'can_delete_sent_messages': canDeleteSentMessages,
    'can_delete_all_messages': canDeleteAllMessages,
    'can_edit_name': canEditName,
    'can_edit_bio': canEditBio,
    'can_edit_profile_photo': canEditProfilePhoto,
    'can_edit_username': canEditUsername,
    'can_view_gifts_and_stars': canViewGiftsAndStars,
    'can_sell_gifts': canSellGifts,
    'can_change_gift_settings': canChangeGiftSettings,
    'can_transfer_and_upgrade_gifts': canTransferAndUpgradeGifts,
    'can_transfer_stars': canTransferStars,
    'can_manage_stories': canManageStories,
  };

  BusinessBotRightsDraft copyWith({
    bool? canReply,
    bool? canReadMessages,
    bool? canDeleteSentMessages,
    bool? canDeleteAllMessages,
    bool? canEditName,
    bool? canEditBio,
    bool? canEditProfilePhoto,
    bool? canEditUsername,
    bool? canViewGiftsAndStars,
    bool? canSellGifts,
    bool? canChangeGiftSettings,
    bool? canTransferAndUpgradeGifts,
    bool? canTransferStars,
    bool? canManageStories,
  }) {
    return BusinessBotRightsDraft(
      canReply: canReply ?? this.canReply,
      canReadMessages: canReadMessages ?? this.canReadMessages,
      canDeleteSentMessages:
          canDeleteSentMessages ?? this.canDeleteSentMessages,
      canDeleteAllMessages: canDeleteAllMessages ?? this.canDeleteAllMessages,
      canEditName: canEditName ?? this.canEditName,
      canEditBio: canEditBio ?? this.canEditBio,
      canEditProfilePhoto: canEditProfilePhoto ?? this.canEditProfilePhoto,
      canEditUsername: canEditUsername ?? this.canEditUsername,
      canViewGiftsAndStars: canViewGiftsAndStars ?? this.canViewGiftsAndStars,
      canSellGifts: canSellGifts ?? this.canSellGifts,
      canChangeGiftSettings:
          canChangeGiftSettings ?? this.canChangeGiftSettings,
      canTransferAndUpgradeGifts:
          canTransferAndUpgradeGifts ?? this.canTransferAndUpgradeGifts,
      canTransferStars: canTransferStars ?? this.canTransferStars,
      canManageStories: canManageStories ?? this.canManageStories,
    );
  }
}

class BusinessQuickReplyShortcut {
  const BusinessQuickReplyShortcut({
    required this.id,
    required this.name,
    required this.messageCount,
    required this.preview,
  });

  factory BusinessQuickReplyShortcut.fromJson(Map<String, dynamic> value) {
    return BusinessQuickReplyShortcut(
      id: value.integer('id') ?? 0,
      name: value.str('name') ?? '',
      messageCount: value.integer('message_count') ?? 0,
      preview: businessQuickReplyContentPreview(
        value.obj('first_message')?.obj('content'),
      ),
    );
  }

  final int id;
  final String name;
  final int messageCount;
  final String preview;
}

class BusinessQuickReplyMessage {
  const BusinessQuickReplyMessage({
    required this.id,
    required this.canBeEdited,
    required this.contentType,
    required this.preview,
    required this.raw,
  });

  factory BusinessQuickReplyMessage.fromJson(Map<String, dynamic> value) {
    final content = value.obj('content');
    return BusinessQuickReplyMessage(
      id: value.int64('id') ?? 0,
      canBeEdited: value.boolean('can_be_edited') ?? false,
      contentType: content?.type ?? '',
      preview: businessQuickReplyContentPreview(content),
      raw: value,
    );
  }

  final int id;
  final bool canBeEdited;
  final String contentType;
  final String preview;
  final Map<String, dynamic> raw;
}

@visibleForTesting
String businessQuickReplyContentPreview(Map<String, dynamic>? content) {
  if (content == null) return '';
  String caption() => content.obj('caption')?.str('text')?.trim() ?? '';
  switch (content.type) {
    case 'messageText':
      return content.obj('text')?.str('text')?.trim() ?? '';
    case 'messagePhoto':
      return caption().isEmpty ? 'Photo' : caption();
    case 'messageVideo':
      return caption().isEmpty ? 'Video' : caption();
    case 'messageAnimation':
      return caption().isEmpty ? 'GIF' : caption();
    case 'messageAudio':
      return caption().isEmpty ? 'Audio' : caption();
    case 'messageDocument':
      return caption().isEmpty ? 'File' : caption();
    case 'messageSticker':
      return 'Sticker';
    case 'messageVoiceNote':
      return caption().isEmpty ? 'Voice message' : caption();
    case 'messageVideoNote':
      return 'Video message';
    case 'messageChecklist':
      return content.obj('list')?.obj('title')?.str('text') ?? 'Checklist';
    default:
      return (content.type ?? '').replaceFirst('message', '');
  }
}

@visibleForTesting
Map<String, dynamic> businessTextInput(String text) => {
  '@type': 'inputMessageText',
  'text': {
    '@type': 'formattedText',
    'text': text,
    'entities': const <Map<String, dynamic>>[],
  },
  'link_preview_options': null,
  'clear_draft': false,
};

class BusinessService {
  BusinessService({TdClient? client}) : _client = client ?? TdClient.shared;

  final TdClient _client;

  Future<BusinessCapabilities> capabilities() async {
    final me = await _client.query({'@type': 'getMe'});
    Map<String, dynamic>? businessFeatures;
    try {
      businessFeatures = await _client.query({
        '@type': 'getBusinessFeatures',
        'source': null,
      });
    } catch (_) {
      // The bundled schema is known at build time. Retain the usable settings
      // surface during a transient server/capability-probe failure.
    }
    return BusinessCapabilities(
      isPremium: me.boolean('is_premium') ?? false,
      features: resolvedBusinessFeatures(businessFeatures),
    );
  }

  Future<Map<String, dynamic>?> currentBusinessInfo() async {
    final me = await _client.query({'@type': 'getMe'});
    final userId = me.int64('id');
    if (userId == null) return null;
    final full = await _client.query({
      '@type': 'getUserFullInfo',
      'user_id': userId,
    });
    return full.obj('business_info');
  }

  Future<void> setGreeting({
    required bool enabled,
    required int shortcutId,
    required BusinessRecipientsDraft recipients,
    required int inactivityDays,
  }) {
    return _client
        .query({
          '@type': 'setBusinessGreetingMessageSettings',
          'greeting_message_settings': enabled
              ? {
                  '@type': 'businessGreetingMessageSettings',
                  'shortcut_id': shortcutId,
                  'recipients': recipients.toJson(),
                  'inactivity_days': inactivityDays,
                }
              : null,
        })
        .then((_) {});
  }

  Future<void> setAway({
    required bool enabled,
    required int shortcutId,
    required BusinessRecipientsDraft recipients,
    required Map<String, dynamic> schedule,
    required bool offlineOnly,
  }) {
    return _client
        .query({
          '@type': 'setBusinessAwayMessageSettings',
          'away_message_settings': enabled
              ? {
                  '@type': 'businessAwayMessageSettings',
                  'shortcut_id': shortcutId,
                  'recipients': recipients.toJson(),
                  'schedule': schedule,
                  'offline_only': offlineOnly,
                }
              : null,
        })
        .then((_) {});
  }

  Future<Map<String, dynamic>?> connectedBot() async {
    try {
      return await _client.query({'@type': 'getBusinessConnectedBot'});
    } on TdError catch (error) {
      if (error.code == 404) return null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> resolveBot(String username) async {
    final normalized = username.trim().replaceFirst(RegExp(r'^@'), '');
    final chat = await _client.query({
      '@type': 'searchPublicChat',
      'username': normalized,
    });
    final userId = chat.obj('type')?.int64('user_id');
    if (userId == null) throw const FormatException('Not a private bot chat');
    final user = await _client.query({'@type': 'getUser', 'user_id': userId});
    if (user.obj('type')?.type != 'userTypeBot') {
      throw const FormatException('The selected account is not a bot');
    }
    return user;
  }

  Future<void> setConnectedBot({
    required int botUserId,
    required BusinessRecipientsDraft recipients,
    required BusinessBotRightsDraft rights,
  }) {
    return _client
        .query({
          '@type': 'setBusinessConnectedBot',
          'bot': {
            '@type': 'businessConnectedBot',
            'bot_user_id': botUserId,
            'recipients': recipients.toJson(allowExcludedChats: true),
            'rights': rights.toJson(),
          },
        })
        .then((_) {});
  }

  Future<void> confirmConnectedBot(int botUserId) => _client
      .query({'@type': 'confirmBusinessConnectedBot', 'bot_user_id': botUserId})
      .then((_) {});

  Future<void> deleteConnectedBot(int botUserId) => _client
      .query({'@type': 'deleteBusinessConnectedBot', 'bot_user_id': botUserId})
      .then((_) {});

  Future<void> setBotPausedInChat(int chatId, bool paused) => _client
      .query({
        '@type': 'toggleBusinessConnectedBotChatIsPaused',
        'chat_id': chatId,
        'is_paused': paused,
      })
      .then((_) {});

  Future<void> removeBotFromChat(int chatId) => _client
      .query({'@type': 'removeBusinessConnectedBotFromChat', 'chat_id': chatId})
      .then((_) {});
}

/// Update-backed quick-reply repository. TDLib's load methods return `ok` and
/// deliver the actual objects through updates, so querying them like ordinary
/// getters loses data and races the UI.
class BusinessQuickReplyService extends ChangeNotifier {
  BusinessQuickReplyService._();

  static final BusinessQuickReplyService shared = BusinessQuickReplyService._();

  final TdClient _client = TdClient.shared;
  final Map<int, BusinessQuickReplyShortcut> _shortcuts = {};
  final Map<int, List<BusinessQuickReplyMessage>> _messages = {};
  List<int> _order = const [];
  // Process-lifetime subscriptions owned by the process-lifetime singleton.
  // ignore: cancel_subscriptions
  StreamSubscription<Map<String, dynamic>>? _updates;
  // ignore: cancel_subscriptions
  StreamSubscription<int>? _slotChanges;
  Completer<void>? _shortcutLoad;
  final Map<int, Completer<void>> _messageLoads = {};

  List<BusinessQuickReplyShortcut> get shortcuts => [
    for (final id in _order)
      if (_shortcuts[id] != null) _shortcuts[id]!,
    for (final entry in _shortcuts.entries)
      if (!_order.contains(entry.key)) entry.value,
  ];

  List<BusinessQuickReplyMessage> messages(int shortcutId) =>
      List.unmodifiable(_messages[shortcutId] ?? const []);

  void _ensureListening() {
    _updates ??= _client.subscribe().listen(_handleUpdate);
    _slotChanges ??= _client.subscribeActiveSlotChanges().listen((_) {
      _shortcuts.clear();
      _messages.clear();
      _order = const [];
      _completeLoads();
      notifyListeners();
    });
  }

  void _completeLoads() {
    final shortcut = _shortcutLoad;
    if (shortcut != null && !shortcut.isCompleted) shortcut.complete();
    for (final waiter in _messageLoads.values) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _messageLoads.clear();
  }

  void _handleUpdate(Map<String, dynamic> update) {
    switch (update.type) {
      case 'updateQuickReplyShortcut':
        final raw = update.obj('shortcut');
        if (raw == null) return;
        final shortcut = BusinessQuickReplyShortcut.fromJson(raw);
        _shortcuts[shortcut.id] = shortcut;
        notifyListeners();
      case 'updateQuickReplyShortcutDeleted':
        final id = update.integer('shortcut_id');
        if (id == null) return;
        _shortcuts.remove(id);
        _messages.remove(id);
        _order = _order.where((value) => value != id).toList();
        notifyListeners();
      case 'updateQuickReplyShortcuts':
        _order = update.int64Array('shortcut_ids') ?? const [];
        final waiter = _shortcutLoad;
        if (waiter != null && !waiter.isCompleted) waiter.complete();
        notifyListeners();
      case 'updateQuickReplyShortcutMessages':
        final id = update.integer('shortcut_id');
        if (id == null) return;
        _messages[id] = [
          for (final raw in update.objects('messages') ?? const [])
            BusinessQuickReplyMessage.fromJson(raw),
        ];
        final waiter = _messageLoads.remove(id);
        if (waiter != null && !waiter.isCompleted) waiter.complete();
        notifyListeners();
    }
  }

  Future<List<BusinessQuickReplyShortcut>> loadShortcuts() async {
    _ensureListening();
    final inFlight = _shortcutLoad;
    if (inFlight != null) {
      try {
        await inFlight.future.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        // The active caller will still return any update-backed cache it has.
      }
      return shortcuts;
    }
    final waiter = Completer<void>();
    _shortcutLoad = waiter;
    try {
      await _client.query({'@type': 'loadQuickReplyShortcuts'});
      await waiter.future.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      // Returning the cache is useful when TDLib doesn't emit an unchanged
      // aggregate update after it was already loaded.
    } finally {
      if (identical(_shortcutLoad, waiter)) _shortcutLoad = null;
    }
    return shortcuts;
  }

  Future<List<BusinessQuickReplyMessage>> loadMessages(int shortcutId) async {
    _ensureListening();
    final inFlight = _messageLoads[shortcutId];
    if (inFlight != null) {
      try {
        await inFlight.future.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        // The active caller will still return any update-backed cache it has.
      }
      return messages(shortcutId);
    }
    final waiter = Completer<void>();
    _messageLoads[shortcutId] = waiter;
    try {
      await _client.query({
        '@type': 'loadQuickReplyShortcutMessages',
        'shortcut_id': shortcutId,
      });
      await waiter.future.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      // See [loadShortcuts].
    } finally {
      if (identical(_messageLoads[shortcutId], waiter)) {
        _messageLoads.remove(shortcutId);
      }
    }
    return messages(shortcutId);
  }

  Future<void> checkName(String name) => _client
      .query({'@type': 'checkQuickReplyShortcutName', 'name': name})
      .then((_) {});

  Future<BusinessQuickReplyMessage> addText({
    required String shortcutName,
    required String text,
    int replyToMessageId = 0,
  }) async {
    final result = await _client.query({
      '@type': 'addQuickReplyShortcutMessage',
      'shortcut_name': shortcutName,
      'reply_to_message_id': replyToMessageId,
      'input_message_content': businessTextInput(text),
    });
    return BusinessQuickReplyMessage.fromJson(result);
  }

  Future<Map<String, dynamic>> addContent({
    required String shortcutName,
    required Map<String, dynamic> inputMessageContent,
    int replyToMessageId = 0,
  }) => _client.query({
    '@type': 'addQuickReplyShortcutMessage',
    'shortcut_name': shortcutName,
    'reply_to_message_id': replyToMessageId,
    'input_message_content': inputMessageContent,
  });

  Future<void> rename(int shortcutId, String name) => _client
      .query({
        '@type': 'setQuickReplyShortcutName',
        'shortcut_id': shortcutId,
        'name': name,
      })
      .then((_) {});

  Future<void> reorder(List<int> shortcutIds) => _client
      .query({
        '@type': 'reorderQuickReplyShortcuts',
        'shortcut_ids': shortcutIds,
      })
      .then((_) {});

  Future<void> deleteShortcut(int shortcutId) => _client
      .query({'@type': 'deleteQuickReplyShortcut', 'shortcut_id': shortcutId})
      .then((_) {});

  Future<void> editText({
    required int shortcutId,
    required int messageId,
    required String text,
  }) => _client
      .query({
        '@type': 'editQuickReplyMessage',
        'shortcut_id': shortcutId,
        'message_id': messageId,
        'input_message_content': businessTextInput(text),
      })
      .then((_) {});

  Future<void> editContent({
    required int shortcutId,
    required int messageId,
    required Map<String, dynamic> inputMessageContent,
  }) => _client
      .query({
        '@type': 'editQuickReplyMessage',
        'shortcut_id': shortcutId,
        'message_id': messageId,
        'input_message_content': inputMessageContent,
      })
      .then((_) {});

  Future<void> deleteMessages(int shortcutId, List<int> messageIds) => _client
      .query({
        '@type': 'deleteQuickReplyShortcutMessages',
        'shortcut_id': shortcutId,
        'message_ids': messageIds,
      })
      .then((_) {});

  Future<void> send(int chatId, int shortcutId) => _client
      .query({
        '@type': 'sendQuickReplyShortcutMessages',
        'chat_id': chatId,
        'shortcut_id': shortcutId,
        'sending_id': DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
      })
      .then((_) {});
}
