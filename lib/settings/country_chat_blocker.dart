import 'dart:async';

import 'package:flutter/foundation.dart';

import '../notifications/notification_settings_payload.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import 'country_message_filter.dart';

typedef CountryBlockerQuery =
    Future<Map<String, dynamic>> Function(
      Map<String, dynamic> request,
      int clientId,
    );

typedef CountryFolderSnapshot = Map<String, dynamic>? Function(int clientId);

/// Applies the country policy to the first inbound message of a private chat.
///
/// A positive decision is remembered immediately, before any TDLib mutation,
/// so notification surfaces can synchronously suppress every message while the
/// chat is being muted, marked read, and added to the `_Blocked` folder.
class CountryChatBlocker {
  CountryChatBlocker({
    CountryMessageFilter? filter,
    CountryBlockerQuery? query,
    CountryFolderSnapshot? folderSnapshot,
  }) : _filter = filter ?? CountryMessageFilter.shared,
       _queryOverride = query,
       _folderSnapshotOverride = folderSnapshot;

  static final CountryChatBlocker shared = CountryChatBlocker();
  static const folderTitle = '_Blocked';

  final CountryMessageFilter _filter;
  final CountryBlockerQuery? _queryOverride;
  final CountryFolderSnapshot? _folderSnapshotOverride;
  final Map<(int, int), bool> _decisions = <(int, int), bool>{};
  final Map<(int, int), Future<bool>> _pending = <(int, int), Future<bool>>{};

  bool suppressesChat(int chatId, int clientId) =>
      _decisions[(clientId, chatId)] ?? false;

  Future<bool> handleIncomingMessage(
    Map<String, dynamic> message, {
    required int clientId,
  }) async {
    final outgoing = message.boolean('is_outgoing') ?? false;
    final chatId = message.int64('chat_id');
    final messageId = message.int64('id');
    if (!_filter.isEnabled || outgoing) return false;
    if (chatId == null || messageId == null) return false;
    final key = (clientId, chatId);
    final decided = _decisions[key];
    if (decided != null) {
      if (decided) await _markRead(chatId, messageId, clientId);
      return decided;
    }
    final pending = _pending[key];
    if (pending != null) {
      final blocked = await pending;
      if (blocked) await _markRead(chatId, messageId, clientId);
      return blocked;
    }
    final evaluation = _evaluateIncomingMessage(
      message,
      chatId: chatId,
      messageId: messageId,
      clientId: clientId,
      key: key,
    );
    _pending[key] = evaluation;
    try {
      return await evaluation;
    } finally {
      final _ = _pending.remove(key);
    }
  }

  Future<bool> _evaluateIncomingMessage(
    Map<String, dynamic> message, {
    required int chatId,
    required int messageId,
    required int clientId,
    required (int, int) key,
  }) async {
    try {
      final chat = await _query({
        '@type': 'getChat',
        'chat_id': chatId,
      }, clientId);
      final type = chat.obj('type');
      final accountInfo = chat.obj('action_bar')?.obj('account_info');
      final accountCountryCode = accountInfo?.str('phone_number_country_code');
      if (type?.type != 'chatTypePrivate' && type?.type != 'chatTypeSecret') {
        _decisions[key] = false;
        return false;
      }
      final userId = await _peerUserId(type, clientId);
      if (userId == null) {
        _decisions[key] = false;
        return false;
      }
      // account_info exists only while Telegram is presenting the unsolicited
      // first-contact action bar. History length is deliberately not used as a
      // fallback: a cleared/reopened old conversation must never be mistaken
      // for a new inbound chat.
      if (accountInfo == null) {
        _decisions[key] = false;
        return false;
      }

      final user = await _query({
        '@type': 'getUser',
        'user_id': userId,
      }, clientId);
      final phoneNumber = user.str('phone_number');
      final countryMatches = _filter.matchesUser(
        phoneNumber: phoneNumber,
        countryCode: accountCountryCode,
      );
      if (!countryMatches) {
        _decisions[key] = false;
        return false;
      }

      final common = await _commonGroupFacts(userId, clientId);
      final content = message.obj('content');
      final isPlainTextWithoutLinks = _isPlainTextWithoutLinks(content);
      final hasNonDefaultAvatar = user.obj('profile_photo') != null;
      final exempt = _filter.shouldExempt(
        hasCommonPrivateGroup: common.hasPrivateGroup,
        commonGroupCount: common.count,
        isPlainTextWithoutLinks: isPlainTextWithoutLinks,
        hasNonDefaultAvatar: hasNonDefaultAvatar,
      );
      if (exempt) {
        _decisions[key] = false;
        return false;
      }

      _decisions[key] = true;
      await _quarantine(chatId, messageId, clientId);
      return true;
    } catch (error, stackTrace) {
      debugPrint('Country chat blocker evaluation failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return _decisions[key] ?? false;
    }
  }

  Future<int?> _peerUserId(Map<String, dynamic>? type, int clientId) async {
    if (type?.type == 'chatTypePrivate') return type?.int64('user_id');
    final secretChatId = type?.int64('secret_chat_id');
    if (secretChatId == null) return null;
    final secret = await _query({
      '@type': 'getSecretChat',
      'secret_chat_id': secretChatId,
    }, clientId);
    return secret.int64('user_id');
  }

  Future<_CommonGroupFacts> _commonGroupFacts(int userId, int clientId) async {
    if (!_filter.exemptCommonPrivateGroup && !_filter.exemptThreeCommonGroups) {
      return const _CommonGroupFacts();
    }
    final result = await _query({
      '@type': 'getGroupsInCommon',
      'user_id': userId,
      'offset_chat_id': 0,
      'limit': 3,
    }, clientId);
    final chatIds = result.int64Array('chat_ids') ?? const <int>[];
    if (!_filter.exemptCommonPrivateGroup || chatIds.isEmpty) {
      return _CommonGroupFacts(count: chatIds.length);
    }
    for (final chatId in chatIds) {
      if (await _isPrivateGroup(chatId, clientId)) {
        return _CommonGroupFacts(count: chatIds.length, hasPrivateGroup: true);
      }
    }
    return _CommonGroupFacts(count: chatIds.length);
  }

  Future<bool> _isPrivateGroup(int chatId, int clientId) async {
    final chat = await _query({
      '@type': 'getChat',
      'chat_id': chatId,
    }, clientId);
    final type = chat.obj('type');
    if (type?.type == 'chatTypeBasicGroup') return true;
    if (type?.type != 'chatTypeSupergroup') return false;
    final supergroupId = type?.int64('supergroup_id');
    if (supergroupId == null) return false;
    final supergroup = await _query({
      '@type': 'getSupergroup',
      'supergroup_id': supergroupId,
    }, clientId);
    if (supergroup.boolean('is_channel') ?? false) return false;
    final usernames = supergroup.obj('usernames');
    final active =
        (usernames?['active_usernames'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(growable: false);
    return active.isEmpty;
  }

  bool _isPlainTextWithoutLinks(Map<String, dynamic>? content) {
    if (content?.type != 'messageText') return false;
    final formatted = content?.obj('text');
    final text = formatted?.str('text') ?? '';
    final entities = formatted?.objects('entities') ?? const [];
    const linkedTypes = {
      'textEntityTypeUrl',
      'textEntityTypeTextUrl',
      'textEntityTypeEmailAddress',
      'textEntityTypePhoneNumber',
      'textEntityTypeMention',
      'textEntityTypeMentionName',
      'textEntityTypeHashtag',
      'textEntityTypeCashtag',
      'textEntityTypeBotCommand',
    };
    if (entities.any(
      (entity) => linkedTypes.contains(entity.obj('type')?.type),
    )) {
      return false;
    }
    return !RegExp(
      r'(?:(?:https?|tg)://|(?:www\.)|(?:t|telegram)\.me/)',
      caseSensitive: false,
    ).hasMatch(text);
  }

  Future<void> _quarantine(int chatId, int messageId, int clientId) async {
    await Future.wait([
      _muteForever(chatId, clientId),
      _markRead(chatId, messageId, clientId),
      _includeChatInBlockedFolder(chatId, clientId),
    ]);
  }

  /// Mutates only the mute fields from the freshest chat snapshot. This keeps
  /// sounds, previews, story settings, and mention preferences chosen on
  /// another device instead of replacing the entire settings object with
  /// defaults. Repeating the operation is a no-op once the chat is muted.
  Future<void> _muteForever(int chatId, int clientId) async {
    final chat = await _query({
      '@type': 'getChat',
      'chat_id': chatId,
    }, clientId);
    final current = chat.obj('notification_settings');
    final alreadyMutedForever =
        !(current?.boolean('use_default_mute_for') ?? true) &&
        (current?.integer('mute_for') ?? 0) >= 2000000000;
    if (alreadyMutedForever) return;
    final settings = current == null
        ? inheritedChatNotificationSettings(muteFor: 2147483647)
        : <String, dynamic>{
            ...current,
            '@type': 'chatNotificationSettings',
            'use_default_mute_for': false,
            'mute_for': 2147483647,
          };
    await _query({
      '@type': 'setChatNotificationSettings',
      'chat_id': chatId,
      'notification_settings': settings,
    }, clientId);
  }

  Future<void> _markRead(int chatId, int messageId, int clientId) async {
    try {
      await _query({
        '@type': 'viewMessages',
        'chat_id': chatId,
        'message_ids': [messageId],
        'force_read': true,
      }, clientId);
    } catch (error) {
      debugPrint('Country-blocked message read sync failed: $error');
    }
  }

  Future<void> _includeChatInBlockedFolder(int chatId, int clientId) async {
    var folders = _folderSnapshot(clientId);
    var matches = _matchingFolderInfos(folders);

    // Creating a folder is the only non-idempotent mutation here. Give an
    // update created by another online device a short opportunity to arrive,
    // then re-check before creating our own folder.
    if (matches.isEmpty && _queryOverride == null) {
      folders = await _waitForFolderSnapshotChange(
        clientId,
        folders,
        timeout: Duration(
          milliseconds:
              350 + DateTime.now().microsecondsSinceEpoch.remainder(500),
        ),
      );
      matches = _matchingFolderInfos(folders);
    }

    if (matches.isEmpty) {
      final created = await _query({
        '@type': 'createChatFolder',
        'folder': _folderPayload(const {}, includedChatIds: {chatId}),
      }, clientId);
      final createdId =
          created.integer('id') ?? created.integer('chat_folder_id');

      if (_queryOverride == null) {
        folders = await _waitForFolderSnapshotChange(
          clientId,
          folders,
          timeout: const Duration(milliseconds: 900),
        );
        matches = _matchingFolderInfos(folders);
      }
      if (matches.isEmpty && createdId != null) {
        matches = [
          {'@type': 'chatFolderInfo', 'id': createdId},
        ];
      }
      if (matches.isNotEmpty) {
        await _convergeBlockedFolders(matches, chatId, clientId);
      }
      return;
    }
    await _convergeBlockedFolders(matches, chatId, clientId);
  }

  Map<String, dynamic>? _folderSnapshot(int clientId) {
    final override = _folderSnapshotOverride;
    return override?.call(clientId) ??
        (_queryOverride == null
            ? TdClient.shared.latestChatFoldersUpdateForClient(clientId)
            : null);
  }

  List<Map<String, dynamic>> _matchingFolderInfos(
    Map<String, dynamic>? folders,
  ) {
    final infos =
        folders?.objects('chat_folders') ??
        folders?.objects('chat_folder_infos') ??
        const <Map<String, dynamic>>[];
    return infos
        .where((candidate) => _folderName(candidate) == folderTitle)
        .where(
          (candidate) =>
              candidate.integer('id') != null ||
              candidate.integer('chat_folder_id') != null,
        )
        .toList(growable: false);
  }

  Future<Map<String, dynamic>?> _waitForFolderSnapshotChange(
    int clientId,
    Map<String, dynamic>? previous, {
    required Duration timeout,
  }) async {
    final client = TdClient.shared;
    final previousSignature = _folderSnapshotSignature(previous);
    final current = client.latestChatFoldersUpdateForClient(clientId);
    if (_folderSnapshotSignature(current) != previousSignature) return current;
    try {
      return await client
          .subscribeAll()
          .firstWhere(
            (update) =>
                update.type == 'updateChatFolders' &&
                update.integer('@client_id') == clientId &&
                _folderSnapshotSignature(update) != previousSignature,
          )
          .timeout(timeout);
    } on TimeoutException {
      return client.latestChatFoldersUpdateForClient(clientId);
    }
  }

  String _folderSnapshotSignature(Map<String, dynamic>? folders) {
    final infos =
        folders?.objects('chat_folders') ??
        folders?.objects('chat_folder_infos') ??
        const <Map<String, dynamic>>[];
    return infos
        .map(
          (info) =>
              '${info.integer('id') ?? info.integer('chat_folder_id')}:'
              '${_folderName(info)}',
        )
        .join('|');
  }

  Future<void> _convergeBlockedFolders(
    List<Map<String, dynamic>> infos,
    int chatId,
    int clientId,
  ) async {
    final ids =
        infos
            .map((info) => info.integer('id') ?? info.integer('chat_folder_id'))
            .whereType<int>()
            .toSet()
            .toList()
          ..sort();
    if (ids.isEmpty) return;

    final canonicalId = ids.first;
    final mergedIncluded = <int>{chatId};
    for (final id in ids) {
      try {
        final folder = await _query({
          '@type': 'getChatFolder',
          'chat_folder_id': id,
        }, clientId);
        mergedIncluded.addAll(
          folder.int64Array('included_chat_ids') ?? const <int>[],
        );
        mergedIncluded.addAll(
          folder.int64Array('pinned_chat_ids') ?? const <int>[],
        );
      } catch (error) {
        debugPrint('Country blocker could not read folder $id: $error');
      }
    }

    // Re-read and verify more than once. editChatFolder replaces a folder, so
    // this merge loop converges if another online device adds a different chat
    // at the same time instead of letting the last writer drop its membership.
    for (var attempt = 0; attempt < 3; attempt++) {
      final current = await _query({
        '@type': 'getChatFolder',
        'chat_folder_id': canonicalId,
      }, clientId);
      final currentIncluded =
          (current.int64Array('included_chat_ids') ?? const <int>[]).toSet();
      mergedIncluded.addAll(currentIncluded);
      if (!currentIncluded.containsAll(mergedIncluded)) {
        await _query({
          '@type': 'editChatFolder',
          'chat_folder_id': canonicalId,
          'folder': _folderPayload(current, includedChatIds: mergedIncluded),
        }, clientId);
      }
      if (_queryOverride == null) {
        await Future<void>.delayed(
          Duration(milliseconds: 90 + chatId.abs().remainder(120)),
        );
      }
    }

    // A simultaneous first block on two devices can create two same-named
    // folders. Merge all membership into the stable lowest id, then remove the
    // redundant folders. Deleting a folder with an empty leave list never
    // leaves or deletes its chats.
    for (final duplicateId in ids.skip(1)) {
      try {
        await _query({
          '@type': 'deleteChatFolder',
          'chat_folder_id': duplicateId,
          'leave_chat_ids': const <int>[],
        }, clientId);
      } catch (error) {
        // Another online device may already have removed this duplicate.
        if (kDebugMode) {
          debugPrint(
            'Country blocker duplicate folder already reconciled: $error',
          );
        }
      }
    }
  }

  Map<String, dynamic> _folderPayload(
    Map<String, dynamic> folder, {
    required Set<int> includedChatIds,
  }) {
    final existingName = folder.obj('name');
    return {
      '@type': 'chatFolder',
      'name': {
        '@type': 'chatFolderName',
        'text': {
          '@type': 'formattedText',
          'text': folderTitle,
          'entities':
              existingName?.obj('text')?.objects('entities') ?? const [],
        },
        'animate_custom_emoji':
            existingName?.boolean('animate_custom_emoji') ?? false,
      },
      if (folder.obj('icon') != null) 'icon': folder.obj('icon'),
      'color_id': folder.integer('color_id') ?? -1,
      'is_shareable': false,
      'pinned_chat_ids': folder.int64Array('pinned_chat_ids') ?? const <int>[],
      'included_chat_ids': includedChatIds.toList()..sort(),
      'excluded_chat_ids':
          folder.int64Array('excluded_chat_ids') ?? const <int>[],
      'exclude_muted': false,
      'exclude_read': false,
      'exclude_archived': false,
      'include_contacts': false,
      'include_non_contacts': false,
      'include_bots': false,
      'include_groups': false,
      'include_channels': false,
    };
  }

  String _folderName(Map<String, dynamic> folder) =>
      folder.obj('name')?.obj('text')?.str('text') ??
      folder.str('title') ??
      folder.str('name') ??
      '';

  Future<Map<String, dynamic>> _query(
    Map<String, dynamic> request,
    int clientId,
  ) {
    final override = _queryOverride;
    if (override != null) return override(request, clientId);
    final client = TdClient.shared;
    return clientId == client.activeClientId
        ? client.query(request)
        : client.queryTo(request, clientId);
  }
}

class _CommonGroupFacts {
  const _CommonGroupFacts({this.count = 0, this.hasPrivateGroup = false});

  final int count;
  final bool hasPrivateGroup;
}
