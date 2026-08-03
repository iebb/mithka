//
//  telegram_mini_app_recents.dart
//
//  Stores the user's recently opened Telegram Mini Apps. Only the original bot
//  launch URL is persisted; TDLib-authenticated Web App URLs are never stored.
//

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';

/// Stable Telegram account identity captured before a Mini App launch begins.
///
/// Slots can be reused and the active account can change while TDLib resolves a
/// signed Web App URL, so launch metadata must remain tied to all three values.
@immutable
class TelegramMiniAppAccountScope {
  const TelegramMiniAppAccountScope({
    required this.slot,
    required this.clientId,
    required this.userId,
  });

  final int slot;
  final int clientId;
  final int userId;

  bool matches({
    required int currentSlot,
    required int currentClientId,
    required int? currentUserId,
  }) =>
      currentSlot == slot &&
      currentClientId == clientId &&
      currentUserId == userId;
}

class TelegramMiniAppRecent {
  const TelegramMiniAppRecent({
    required this.title,
    this.botTitle = '',
    required this.url,
    required this.botUserId,
    required this.chatId,
    required this.updatedAt,
    this.keyboardButtonText,
    this.mainWebApp = false,
    this.startParameter = '',
    this.webAppShortName = '',
    this.allowWriteAccess = false,
    this.photo,
  });

  final String title;
  final String botTitle;
  final String url;
  final int botUserId;
  final int chatId;
  final int updatedAt;
  final String? keyboardButtonText;
  final bool mainWebApp;
  final String startParameter;
  final String webAppShortName;
  final bool allowWriteAccess;
  final TdFileRef? photo;

  String get launchTitle => _localizedMiniAppFallback(title);

  String get displayTitle {
    final candidate = botTitle.trim().isEmpty ? title : botTitle.trim();
    return _localizedMiniAppFallback(candidate);
  }

  static String _localizedMiniAppFallback(String value) {
    final clean = value.trim();
    // Migrate the presentation of legacy recents that persisted the previous
    // English fallback. New records keep an empty semantic value so changing
    // the app language can update the fallback immediately.
    return clean.isEmpty || clean == 'Mini App'
        ? AppStrings.t(AppStringKeys.miniAppName)
        : clean;
  }

  TelegramMiniAppRecent withBotIdentity({String? botTitle, TdFileRef? photo}) {
    return TelegramMiniAppRecent(
      title: title,
      botTitle: botTitle?.trim().isNotEmpty == true
          ? botTitle!.trim()
          : this.botTitle,
      url: url,
      botUserId: botUserId,
      chatId: chatId,
      updatedAt: updatedAt,
      keyboardButtonText: keyboardButtonText,
      mainWebApp: mainWebApp,
      startParameter: startParameter,
      webAppShortName: webAppShortName,
      allowWriteAccess: allowWriteAccess,
      photo: photo ?? this.photo,
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    if (botTitle.isNotEmpty) 'botTitle': botTitle,
    'url': url,
    'botUserId': botUserId,
    'chatId': chatId,
    'updatedAt': updatedAt,
    if (mainWebApp) 'mainWebApp': true,
    if (startParameter.isNotEmpty) 'startParameter': startParameter,
    if (webAppShortName.isNotEmpty) 'webAppShortName': webAppShortName,
    if (allowWriteAccess) 'allowWriteAccess': true,
    if (photo != null) 'photoFileId': photo!.id,
    if (keyboardButtonText != null && keyboardButtonText!.isNotEmpty)
      'keyboardButtonText': keyboardButtonText,
  };

  static TelegramMiniAppRecent? fromJson(Object? value) {
    if (value is! Map) return null;
    final title = value['title'] as String?;
    final url = value['url'] as String?;
    final botUserId = _asInt(value['botUserId']);
    final chatId = _asInt(value['chatId']);
    final mainWebApp = value['mainWebApp'] == true;
    final shortName = value['webAppShortName'] as String? ?? '';
    if (title == null ||
        url == null ||
        (!mainWebApp && shortName.isEmpty && url.isEmpty) ||
        botUserId == null ||
        chatId == null) {
      return null;
    }
    final photoFileId = _asInt(value['photoFileId']);
    return TelegramMiniAppRecent(
      title: title,
      botTitle: value['botTitle'] as String? ?? '',
      url: url,
      botUserId: botUserId,
      chatId: chatId,
      updatedAt: _asInt(value['updatedAt']) ?? 0,
      keyboardButtonText: value['keyboardButtonText'] as String?,
      mainWebApp: mainWebApp,
      startParameter: value['startParameter'] as String? ?? '',
      webAppShortName: shortName,
      allowWriteAccess: value['allowWriteAccess'] == true,
      photo: photoFileId == null ? null : TdFileRef(id: photoFileId),
    );
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

abstract final class TelegramMiniAppRecents {
  static const _legacyKey = 'telegramMiniAppRecents.v1';
  static const _userKeyPrefix = 'telegramMiniAppRecents.v2.user.';
  static const _slotKeyPrefix = 'telegramMiniAppRecents.v2.slot.';
  static const _limit = 12;
  static final Map<String, Future<void>> _storageGates = {};

  static Future<List<TelegramMiniAppRecent>> load() async {
    final stored = await _loadStored();
    final used = await _discoverUsedWebAppBots();
    final discovered = await _discoverBotMenuApps();
    return _merge(stored, [...discovered, ...used]);
  }

  static Future<List<TelegramMiniAppRecent>> search(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) return load();

    final linkTarget = await _webAppTargetFromQuery(query);
    if (linkTarget == null) {
      final recents = await load();
      final lower = query.toLowerCase();
      return recents
          .where(
            (app) =>
                app.title.toLowerCase().contains(lower) ||
                app.displayTitle.toLowerCase().contains(lower) ||
                app.url.toLowerCase().contains(lower) ||
                app.webAppShortName.toLowerCase().contains(lower),
          )
          .toList();
    }

    return _searchTelegramWebApp(linkTarget);
  }

  static Future<List<TelegramMiniAppRecent>> _loadStored() async {
    final scope = await _activeStorageScope();
    return _loadStoredForScope(scope);
  }

  static Future<_TelegramMiniAppStorageScope> _activeStorageScope() async {
    final slot = TdClient.shared.activeSlot;
    final clientId = TdClient.shared.activeClientId;
    final proxyUserId = TdClient.shared.proxyAccountUserId;
    if (proxyUserId != null && proxyUserId > 0) {
      return _TelegramMiniAppStorageScope.user(
        userId: proxyUserId,
        slot: slot,
        clientId: clientId,
      );
    }
    if (!TdClient.shared.hasActiveClient) {
      return _TelegramMiniAppStorageScope.slot(slot: slot, clientId: clientId);
    }
    try {
      final me = await TdClient.shared.query({'@type': 'getMe'});
      final userId = me.int64('id');
      if (userId != null && userId > 0) {
        return _TelegramMiniAppStorageScope.user(
          userId: userId,
          slot: slot,
          clientId: clientId,
        );
      }
    } catch (_) {}
    return _TelegramMiniAppStorageScope.slot(slot: slot, clientId: clientId);
  }

  static Future<List<TelegramMiniAppRecent>> _loadStoredForScope(
    _TelegramMiniAppStorageScope scope,
  ) => _withStorageScopeLock(
    scope.key,
    () => _loadStoredForScopeUnlocked(scope),
  );

  static Future<List<TelegramMiniAppRecent>> _loadStoredForScopeUnlocked(
    _TelegramMiniAppStorageScope scope,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    var recents = _decodeStoredRecents(prefs.getString(scope.key));
    if (scope.userId != null) {
      var migrated = false;
      for (final migrationKey in scope.migrationKeys) {
        final candidate = prefs.getString(migrationKey);
        if (candidate != null && candidate.isNotEmpty) {
          recents = _mergeStoredRecents(
            recents,
            _decodeStoredRecents(candidate),
          );
          migrated = true;
        }
        await prefs.remove(migrationKey);
      }
      // A temporary slot record belongs to this exact TD client lifetime and
      // can be merged once its user identity is known.
      if (migrated) {
        await prefs.setString(
          scope.key,
          jsonEncode(recents.map((item) => item.toJson()).toList()),
        );
      }
    }

    // v1 was global across every Telegram account and therefore has no
    // trustworthy owner. Never assign it to whichever user happens to load
    // first; discard it once an authenticated user scope is available.
    if (scope.userId != null && prefs.containsKey(_legacyKey)) {
      await prefs.remove(_legacyKey);
    }

    return recents;
  }

  static Future<T> _withStorageScopeLock<T>(
    String scopeKey,
    Future<T> Function() action,
  ) async {
    final previous = _storageGates[scopeKey] ?? Future<void>.value();
    final gate = Completer<void>();
    final next = gate.future;
    _storageGates[scopeKey] = next;
    try {
      try {
        await previous;
      } on Object {
        // A failed earlier operation must not permanently block this scope.
      }
      return await action();
    } finally {
      gate.complete();
      if (identical(_storageGates[scopeKey], next)) {
        unawaited(_storageGates.remove(scopeKey));
      }
    }
  }

  static List<TelegramMiniAppRecent> _decodeStoredRecents(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final recents =
          decoded
              .map(TelegramMiniAppRecent.fromJson)
              .whereType<TelegramMiniAppRecent>()
              .toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return recents.take(_limit).toList();
    } catch (_) {
      return const [];
    }
  }

  static List<TelegramMiniAppRecent> _mergeStoredRecents(
    List<TelegramMiniAppRecent> primary,
    List<TelegramMiniAppRecent> migrated,
  ) {
    final latestByBot = <int, TelegramMiniAppRecent>{};
    for (final recent in [...primary, ...migrated]) {
      final current = latestByBot[recent.botUserId];
      if (current == null || recent.updatedAt > current.updatedAt) {
        latestByBot[recent.botUserId] = recent;
      }
    }
    final merged = latestByBot.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return merged.take(_limit).toList();
  }

  static Future<List<TelegramMiniAppRecent>> _discoverBotMenuApps() async {
    try {
      final chats = await TdClient.shared.query({
        '@type': 'getChats',
        'chat_list': {'@type': 'chatListMain'},
        'limit': 80,
      });
      final ids = chats.int64Array('chat_ids') ?? const <int>[];
      final apps = <TelegramMiniAppRecent>[];
      for (final chatId in ids) {
        try {
          final chat = await TdClient.shared.query({
            '@type': 'getChat',
            'chat_id': chatId,
          });
          final type = chat.obj('type');
          if (type?.type != 'chatTypePrivate') continue;
          final userId = type?.int64('user_id');
          if (userId == null) continue;
          final full = await TdClient.shared.query({
            '@type': 'getUserFullInfo',
            'user_id': userId,
          });
          final menu = full.obj('bot_info')?.obj('menu_button');
          if (menu?.type != 'botMenuButton') continue;
          final url = menu?.str('url')?.trim() ?? '';
          if (url.isEmpty) continue;
          final text = menu?.str('text')?.trim() ?? '';
          final botTitle = chat.str('title')?.trim() ?? '';
          apps.add(
            TelegramMiniAppRecent(
              title: text,
              botTitle: botTitle,
              url: url,
              botUserId: userId,
              chatId: chatId,
              updatedAt: 0,
              photo: TDParse.smallPhoto(chat.obj('photo')),
            ),
          );
        } catch (_) {}
      }
      return apps;
    } catch (_) {
      return const [];
    }
  }

  static Future<List<TelegramMiniAppRecent>> _discoverUsedWebAppBots() async {
    try {
      final chats = await TdClient.shared.query({
        '@type': 'getTopChats',
        'category': {'@type': 'topChatCategoryWebAppBots'},
        'limit': _limit,
      });
      final ids = chats.int64Array('chat_ids') ?? const <int>[];
      final apps = <TelegramMiniAppRecent>[];
      for (final chatId in ids) {
        try {
          final chat = await TdClient.shared.query({
            '@type': 'getChat',
            'chat_id': chatId,
          });
          final type = chat.obj('type');
          if (type?.type != 'chatTypePrivate') continue;
          final userId = type?.int64('user_id');
          if (userId == null) continue;
          final title = chat.str('title')?.trim();
          apps.add(
            TelegramMiniAppRecent(
              title: title ?? '',
              botTitle: title ?? '',
              url: '',
              botUserId: userId,
              chatId: chatId,
              updatedAt: 0,
              mainWebApp: true,
              photo: TDParse.smallPhoto(chat.obj('photo')),
            ),
          );
        } catch (_) {}
      }
      return apps;
    } catch (_) {
      return const [];
    }
  }

  static List<TelegramMiniAppRecent> _merge(
    List<TelegramMiniAppRecent> stored,
    List<TelegramMiniAppRecent> discovered,
  ) {
    return mergeTelegramMiniAppRecents(stored, discovered);
  }

  static Future<void> record({
    required String title,
    required String url,
    required int botUserId,
    required int chatId,
    String? keyboardButtonText,
    bool mainWebApp = false,
    String startParameter = '',
    String webAppShortName = '',
    bool allowWriteAccess = false,
    TdFileRef? photo,
    TelegramMiniAppAccountScope? account,
  }) async {
    final cleanTitle = title.trim();
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty && !mainWebApp && webAppShortName.isEmpty) return;

    var botTitle = '';
    var botPhoto = photo;
    final scope = account == null
        ? await _activeStorageScope()
        : _TelegramMiniAppStorageScope.user(
            userId: account.userId,
            slot: account.slot,
            clientId: account.clientId,
          );
    if (account != null && !await _accountStillOwnsClient(account)) return;
    try {
      final request = {'@type': 'getChat', 'chat_id': chatId};
      final chat = account == null
          ? await TdClient.shared.query(request)
          : await TdClient.shared.queryTo(request, account.clientId);
      botTitle = chat.str('title')?.trim() ?? '';
      botPhoto = TDParse.smallPhoto(chat.obj('photo')) ?? botPhoto;
    } catch (_) {}

    await _storeRecentForScope(
      scope,
      TelegramMiniAppRecent(
        title: cleanTitle,
        botTitle: botTitle,
        url: cleanUrl,
        botUserId: botUserId,
        chatId: chatId,
        keyboardButtonText: keyboardButtonText,
        mainWebApp: mainWebApp,
        startParameter: startParameter,
        webAppShortName: webAppShortName,
        allowWriteAccess: allowWriteAccess,
        photo: botPhoto,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
      stillOwned: account == null
          ? null
          : () => _accountStillOwnsClient(account),
    );
  }

  static Future<void> _storeRecentForScope(
    _TelegramMiniAppStorageScope scope,
    TelegramMiniAppRecent recent, {
    Future<bool> Function()? stillOwned,
    Future<void> Function()? onLockAcquiredForTesting,
  }) => _withStorageScopeLock(scope.key, () async {
    if (stillOwned != null && !await stillOwned()) return;
    await onLockAcquiredForTesting?.call();
    if (stillOwned != null && !await stillOwned()) return;

    final current = await _loadStoredForScopeUnlocked(scope);
    final next = <TelegramMiniAppRecent>[
      recent,
      for (final item in current)
        if (item.botUserId != recent.botUserId) item,
    ].take(_limit).toList();

    final prefs = await SharedPreferences.getInstance();
    // Keep this check inside the serialized section and immediately before
    // SharedPreferences updates its in-memory cache.
    if (stillOwned != null && !await stillOwned()) return;
    await prefs.setString(
      scope.key,
      jsonEncode(next.map((item) => item.toJson()).toList()),
    );
  });

  static Future<bool> _accountStillOwnsClient(
    TelegramMiniAppAccountScope account,
  ) async {
    if (TdClient.shared.clientId(account.slot) != account.clientId) {
      return false;
    }
    try {
      final me = await TdClient.shared.queryTo({
        '@type': 'getMe',
      }, account.clientId);
      return TdClient.shared.clientId(account.slot) == account.clientId &&
          me.int64('id') == account.userId;
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  static String storageKeyForTesting({
    required int slot,
    required int clientId,
    int? userId,
  }) => _TelegramMiniAppStorageScope(
    slot: slot,
    clientId: clientId,
    userId: userId,
  ).key;

  @visibleForTesting
  static Future<List<TelegramMiniAppRecent>> loadStoredForTesting({
    required int slot,
    required int clientId,
    int? userId,
  }) => _loadStoredForScope(
    _TelegramMiniAppStorageScope(
      slot: slot,
      clientId: clientId,
      userId: userId,
    ),
  );

  @visibleForTesting
  static Future<void> recordStoredForTesting({
    required int slot,
    required int clientId,
    required int userId,
    required TelegramMiniAppRecent recent,
    Future<void> Function()? onLockAcquired,
  }) => _storeRecentForScope(
    _TelegramMiniAppStorageScope.user(
      userId: userId,
      slot: slot,
      clientId: clientId,
    ),
    recent,
    onLockAcquiredForTesting: onLockAcquired,
  );

  static Future<List<TelegramMiniAppRecent>> _searchTelegramWebApp(
    _WebAppTarget target,
  ) async {
    try {
      final chat = await TdClient.shared.query({
        '@type': 'searchPublicChat',
        'username': target.botUsername,
      });
      final chatId = chat.int64('id') ?? 0;
      final type = chat.obj('type');
      if (type?.type != 'chatTypePrivate') return const [];
      final botUserId = type?.int64('user_id');
      if (botUserId == null) return const [];
      final chatTitle = chat.str('title')?.trim();
      final chatPhoto = TDParse.smallPhoto(chat.obj('photo'));
      if (target.mainWebApp) {
        return [
          TelegramMiniAppRecent(
            title: chatTitle == null || chatTitle.isEmpty
                ? target.botUsername
                : chatTitle,
            botTitle: chatTitle == null || chatTitle.isEmpty
                ? target.botUsername
                : chatTitle,
            url: '',
            botUserId: botUserId,
            chatId: chatId,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
            mainWebApp: true,
            startParameter: target.startParameter,
            photo: chatPhoto,
          ),
        ];
      }

      final found = await TdClient.shared.query({
        '@type': 'searchWebApp',
        'bot_user_id': botUserId,
        'web_app_short_name': target.webAppShortName,
      });
      final webApp = found.obj('web_app');
      if (webApp == null) return const [];
      final title = webApp.str('title')?.trim();
      final shortName = webApp.str('short_name') ?? target.webAppShortName;
      return [
        TelegramMiniAppRecent(
          title: title == null || title.isEmpty ? shortName : title,
          botTitle: chatTitle == null || chatTitle.isEmpty
              ? target.botUsername
              : chatTitle,
          url: 'https://t.me/${target.botUsername}/$shortName',
          botUserId: botUserId,
          chatId: chatId,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          startParameter: target.startParameter,
          webAppShortName: shortName,
          allowWriteAccess: found.boolean('request_write_access') ?? false,
          photo: chatPhoto,
        ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<_WebAppTarget?> _webAppTargetFromQuery(String query) async {
    final normalized = _normalizeTelegramLinkQuery(query);
    if (normalized != null) {
      try {
        final type = await TdClient.shared.query({
          '@type': 'getInternalLinkType',
          'link': normalized,
        });
        switch (type.type) {
          case 'internalLinkTypeWebApp':
            return _WebAppTarget(
              botUsername: type.str('bot_username') ?? '',
              webAppShortName: type.str('web_app_short_name') ?? '',
              startParameter: type.str('start_parameter') ?? '',
            );
          case 'internalLinkTypeMainWebApp':
            return _WebAppTarget(
              botUsername: type.str('bot_username') ?? '',
              startParameter: type.str('start_parameter') ?? '',
              mainWebApp: true,
            );
        }
      } catch (_) {}
    }

    final bare = query
        .replaceFirst(RegExp(r'^@'), '')
        .replaceFirst(RegExp(r'^https?://', caseSensitive: false), '')
        .replaceFirst(
          RegExp(r'^(t\.me|telegram\.me)/', caseSensitive: false),
          '',
        )
        .split('?')
        .first
        .split('#')
        .first;
    final parts = bare.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.length < 2) return null;
    return _WebAppTarget(botUsername: parts[0], webAppShortName: parts[1]);
  }

  static String? _normalizeTelegramLinkQuery(String query) {
    final lower = query.toLowerCase();
    if (lower.startsWith('tg:') ||
        lower.startsWith('https://t.me/') ||
        lower.startsWith('http://t.me/') ||
        lower.startsWith('https://telegram.me/') ||
        lower.startsWith('http://telegram.me/')) {
      return query;
    }
    if (RegExp(r'^[a-zA-Z0-9_]{3,}/[a-zA-Z0-9_]+').hasMatch(query)) {
      return 'https://t.me/$query';
    }
    return null;
  }
}

class _TelegramMiniAppStorageScope {
  const _TelegramMiniAppStorageScope({
    required this.slot,
    required this.clientId,
    required this.userId,
  });

  factory _TelegramMiniAppStorageScope.user({
    required int userId,
    required int slot,
    required int clientId,
  }) => _TelegramMiniAppStorageScope(
    slot: slot,
    clientId: clientId,
    userId: userId,
  );

  factory _TelegramMiniAppStorageScope.slot({
    required int slot,
    required int clientId,
  }) => _TelegramMiniAppStorageScope(
    slot: slot,
    clientId: clientId,
    userId: null,
  );

  final int slot;
  final int clientId;
  final int? userId;

  String get slotKey =>
      '${TelegramMiniAppRecents._slotKeyPrefix}$slot.client.$clientId';
  String get key => userId == null
      ? slotKey
      : '${TelegramMiniAppRecents._userKeyPrefix}$userId';
  List<String> get migrationKeys =>
      userId == null ? const [] : <String>[slotKey];
}

List<TelegramMiniAppRecent> mergeTelegramMiniAppRecents(
  List<TelegramMiniAppRecent> stored,
  List<TelegramMiniAppRecent> discovered, {
  int limit = 12,
}) {
  final merged = <TelegramMiniAppRecent>[];
  final indexByBot = <int, int>{};

  for (final app in stored) {
    if (indexByBot.containsKey(app.botUserId)) continue;
    indexByBot[app.botUserId] = merged.length;
    merged.add(app);
  }
  for (final app in discovered) {
    final index = indexByBot[app.botUserId];
    if (index == null) {
      indexByBot[app.botUserId] = merged.length;
      merged.add(app);
      continue;
    }
    merged[index] = merged[index].withBotIdentity(
      botTitle: app.botTitle.trim().isNotEmpty ? app.botTitle : app.title,
      photo: app.photo,
    );
  }
  return merged.take(limit).toList();
}

class _WebAppTarget {
  const _WebAppTarget({
    required this.botUsername,
    this.webAppShortName = '',
    this.startParameter = '',
    this.mainWebApp = false,
  });

  final String botUsername;
  final String webAppShortName;
  final String startParameter;
  final bool mainWebApp;
}
