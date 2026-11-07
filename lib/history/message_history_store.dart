//
//  message_history_store.dart
//
//  AyuGram-style local message history: every incoming message is mirrored
//  into a small on-device store so messages the counterpart deletes or edits
//  stay readable afterwards. Nothing here talks to Telegram — the mirror is
//  written from TDLib updates the account already received, and the kept
//  copies never leave this device.
//
//  Every record is owned by the account that received it: TDLib stamps each
//  update with '@client_id', the store resolves that to the account's user id
//  (getMe, cached) and keys entries, pending edit dates and exclusions by it.
//  Two accounts that see the same chat/message ids therefore keep two
//  separate records, and the viewer only ever shows the active account's.
//
//  The whole feature is a Telegram API Terms section 1.4 exception, so every
//  entry point — the TDLib subscription, the persisted file, the preference
//  keys, the settings row and the viewer route — is guarded by the
//  compile-time [allowTelegramTosViolations] constant. With the flag omitted
//  or false, no update is subscribed, no file or preference is read or
//  written, and every method is a no-op, so pre-existing saved state can
//  never take effect either.
//

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/build_flags.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import 'message_history_models.dart';
import 'message_media_snapshot.dart';

export 'message_history_models.dart';

/// Resolves a TDLib client id to the owning account's user id. Production
/// asks the client itself (getMe) and caches; tests inject the mapping.
abstract class TosAccountUserIdResolver {
  Future<int?> resolve(int clientId);

  /// getMe through the exact client that produced the update. A client that
  /// is gone (slot removed, shutting down) resolves to null, and updates
  /// from it are dropped rather than misattributed.
  static final TosAccountUserIdResolver production = _TdClientUserIdResolver();
}

class _TdClientUserIdResolver implements TosAccountUserIdResolver {
  final Map<int, int> _cache = {};

  @override
  Future<int?> resolve(int clientId) async {
    final cached = _cache[clientId];
    if (cached != null) return cached;
    try {
      final me = await TdClient.shared.queryTo({'@type': 'getMe'}, clientId);
      final userId = me.int64('id');
      if (userId == null) return null;
      _cache[clientId] = userId;
      return userId;
    } catch (_) {
      return null;
    }
  }
}

/// Owns the mirrored message history: records TDLib updates, keeps the
/// entries in memory and persists a bounded batch to one JSON file.
class MessageHistoryStore extends ChangeNotifier {
  MessageHistoryStore._();

  static final MessageHistoryStore shared = MessageHistoryStore._();

  @visibleForTesting
  factory MessageHistoryStore.forTesting() = MessageHistoryStore._;

  static const _prefsKeyPrefix = 'messageHistory.excludedChats.v2.';
  static const _fileName = 'message-history.json';
  static const _tmpSuffix = '.tmp';

  /// Bounded on purpose: the mirror is a safety net for recent surprises,
  /// not an archival copy of the account.
  static const maxEntries = 5000;
  static const persistBatch = 400;

  static const observedUpdateTypes = [
    'updateNewMessage',
    'updateMessageEdited',
    'updateMessageContent',
    'updateDeleteMessages',
    // A chat whose counterpart deleted their account (or the chat) stops
    // being openable; kept entries then render in the ghost style.
    'updateChat',
  ];

  final Map<String, MessageHistoryEntry> _byKey = {};

  /// Excluded chats per owning account; the read/write APIs operate on the
  /// active account's set.
  final Map<int, Set<int>> _excludedChatsByAccount = {};

  /// (account, chat) scopes whose chat TDLib reported gone (deleted account /
  /// unresolvable chat). Kept entries of a dead chat render in the ghost
  /// style; not persisted — TDLib re-reports the state on the next sync.
  final Set<String> _deadChats = {};

  /// Pending updateMessageEdited dates, keyed per account. An edit or
  /// deletion observed on one account can never touch another account's
  /// entry even when the chat/message ids are identical.
  final Map<String, int> _pendingEditDates = {};

  /// Identity resolution state per TDLib client. While a lookup is in
  /// flight every arrival of that client shares it; a known identity stays
  /// memoized for later events, a failed one is dropped so the next
  /// arrival starts a fresh attempt instead of caching the failure.
  final Map<int, Future<int?>> _identityFutures = {};

  /// Per-CLIENT arrival chains: an update joins its client's chain before
  /// identity resolution, so a client's records apply in TDLib arrival
  /// order no matter how long its getMe takes. Different clients stay
  /// parallel.
  final Map<int, Future<void>> _clientWorkers = {};

  /// Generation of the store's contents. Only the explicitly GLOBAL
  /// operations bump it — [clearAll] and [dispose] — and an async
  /// continuation captures it when its update ARRIVES (or its load starts)
  /// and re-checks before writing, so work queued before one of those can
  /// never resurrect the wiped state. Scoped invalidations (removing one
  /// account, clearing one chat) must not cancel unrelated accounts' and
  /// chats' pending work, so they stamp the scope instead — see
  /// [_scopeEpoch].
  int _generation = 0;

  /// Monotonic epoch of SCOPED invalidations: [removeAccount] and
  /// [clearChat] stamp the scope with its value instead of touching the
  /// global generation, so pending updates, loads and active-account
  /// continuations of every other owner keep running.
  int _scopeEpoch = 0;

  /// Scope epoch at which each account was removed. A queued update that
  /// ARRIVED before its account was removed (`removedAt > arrival`) is
  /// dropped after the identity resolves, so pending work can never
  /// resurrect removed history; later arrivals record again (the slot may
  /// have re-registered), as they always did.
  final Map<int, int> _removedAccountAt = {};

  /// Scope epoch at which each (account, chat) was cleared, keyed
  /// `'$accountUserId:$chatId'`. A queued update for that chat that arrived
  /// before the clear is dropped after the identity resolves — a chat the
  /// user cleared must not be recreated by updates already in flight.
  /// Later arrivals record again. [includeChat] deliberately does not
  /// remove a stamp: re-including an excluded chat is not an un-clear, and
  /// the clear's protection must survive it.
  final Map<String, int> _clearedChatAt = {};

  /// Scope epoch the PERSISTED mirror file last reflected. Loads compare
  /// each disk row's scope stamp against this (not the live epoch): rows of
  /// a scope invalidated after the last persist are stale on disk and are
  /// dropped, while once the writer has rewritten the file the same load
  /// rule lets every surviving row — including later rows of a
  /// re-registered account — apply freely. The stamps are never deleted, so
  /// a queued update resolving long after the invalidation is still
  /// classified correctly.
  int _persistedScopeEpoch = 0;
  int _clearedAllAt = 0;

  /// Resolved user id of the active client, kept in sync with
  /// [TosAccountUserIdResolver] results; null while unresolved.
  int? _activeAccountUserId;
  int? _activeAccountUserIdSource;

  /// Injected per-account id mapping (tests); defaults to getMe per client.
  @visibleForTesting
  TosAccountUserIdResolver? accountUserIdResolver;

  /// The active TDLib client id (tests); defaults to the shared client.
  @visibleForTesting
  int Function()? activeClientIdProvider;

  /// The active-slot change stream (tests); defaults to the shared client.
  @visibleForTesting
  Stream<int> Function()? activeSlotChangeSource;

  SharedPreferences? _prefs;
  bool _loaded = false;
  bool _observing = false;
  StreamSubscription<Map<String, dynamic>>? _tdSub;
  StreamSubscription<int>? _activeSlotSub;
  Timer? _persistTimer;
  bool _persisting = false;
  bool _dirtyWhilePersisting = false;
  bool _disposed = false;

  /// Directory holding the mirror file. Resolved lazily; tests inject one.
  Directory? fileDir;

  /// Holds the file-commit boundary in persistence cancellation tests.
  @visibleForTesting
  Future<void> Function()? beforePersistRenameForTesting;

  TosAccountUserIdResolver get _resolver =>
      accountUserIdResolver ?? TosAccountUserIdResolver.production;

  int? get _currentClientId {
    final provider = activeClientIdProvider;
    if (provider != null) {
      final clientId = provider();
      return clientId == 0 ? null : clientId;
    }
    final clientId = TdClient.shared.activeClientId;
    return clientId == 0 ? null : clientId;
  }

  /// User id of the active account once resolved; null before that.
  int? get activeAccountUserId => _activeAccountUserId;

  /// Every kept copy of the ACTIVE account, oldest first — the order the
  /// mirror saw the messages. Bounded by [maxEntries]; the viewer reverses
  /// for display. Records of other accounts are never surfaced here.
  List<MessageHistoryEntry> get entries => List.unmodifiable(
    _byKey.values.where((entry) => entry.accountUserId == _activeAccountUserId),
  );

  /// Newest first, one chat of the active account, excluded chats are hidden.
  List<MessageHistoryEntry> entriesFor(int chatId) => isChatExcluded(chatId)
      ? const []
      : List.unmodifiable(
          _byKey.values.where(
            (entry) =>
                entry.accountUserId == _activeAccountUserId &&
                entry.chatId == chatId,
          ),
        );

  /// Looks up an entry of the ACTIVE account.
  MessageHistoryEntry? entry(int chatId, int messageId) =>
      _activeAccountUserId == null
      ? null
      : _byKey['$_activeAccountUserId:$chatId:$messageId'];

  int get entryCount => _byKey.length;

  bool isChatExcluded(int chatId) =>
      _activeAccountUserId != null &&
      (_excludedChatsByAccount[_activeAccountUserId]?.contains(chatId) ??
          false);

  Set<int> get excludedChats => Set.unmodifiable(
    _excludedChatsByAccount[_activeAccountUserId] ?? const {},
  );

  // ---------------------------------------------------------------------------
  // Bootstrap (guarded — with the flag off nothing below may run)
  // ---------------------------------------------------------------------------

  /// Reads the per-account exclusions of every account seen so far. Called
  /// from the app bootstrap with the shared prefs; a no-op unless the
  /// feature is compiled in. The pre-account v1 exclusion key is not
  /// migrated: an exclusion written before account identity existed cannot
  /// be attributed to an account without guessing.
  void initialize(SharedPreferences prefs) {
    if (!allowTelegramTosViolations) return;
    _prefs = prefs;
    _excludedChatsByAccount.clear();
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_prefsKeyPrefix)) continue;
      final suffix = key.substring(_prefsKeyPrefix.length);
      final accountUserId = int.tryParse(suffix);
      if (accountUserId == null) continue;
      final raw = prefs.getStringList(key) ?? const <String>[];
      final excluded = raw.map(int.tryParse).whereType<int>().toSet();
      _excludedChatsByAccount[accountUserId] = excluded;
    }
    notifyListeners();
  }

  /// Subscribes the mirror to the TDLib updates it needs. Called once from
  /// the app bootstrap after [initialize].
  void startObserving() {
    if (!allowTelegramTosViolations) return;
    if (_observing) return;
    _observing = true;
    _tdSub = _openUpdates(observedUpdateTypes).listen(_onTdUpdate);
    _activeSlotSub = _openActiveSlotChanges().listen((_) {
      _refreshActiveAccount();
    });
    _refreshActiveAccount();
  }

  /// The typed update stream the mirror subscribes to. Tests replace this to
  /// drive updates without a TDLib client.
  @visibleForTesting
  Stream<Map<String, dynamic>> Function(Iterable<String> types)? updateSource;

  Stream<Map<String, dynamic>> _openUpdates(Iterable<String> types) {
    final source = updateSource;
    if (source != null) return source(types);
    return TdClient.shared.updatesOfAny(types);
  }

  Stream<int> _openActiveSlotChanges() {
    final source = activeSlotChangeSource;
    if (source != null) return source();
    return TdClient.shared.subscribeActiveSlotChanges();
  }

  /// Re-resolves the active account's user id when the active client
  /// changes; the viewer and the exclusion APIs read the cached result.
  /// EVERY terminal state notifies: the switch itself (the account context
  /// changed, so the viewer must re-read immediately, dropping the previous
  /// account's rows), success (rows appear) and failure (empty is the
  /// terminal state, so the stale rows must leave the screen there too).
  void _refreshActiveAccount() {
    final clientId = _currentClientId;
    if (clientId == null) {
      final hadContext =
          _activeAccountUserId != null || _activeAccountUserIdSource != null;
      _activeAccountUserId = null;
      _activeAccountUserIdSource = null;
      if (hadContext) notifyListeners();
      return;
    }
    if (_activeAccountUserIdSource == clientId &&
        _activeAccountUserId != null) {
      return;
    }
    _activeAccountUserIdSource = clientId;
    _activeAccountUserId = null;
    notifyListeners();
    final generation = _generation;
    unawaited(
      // A test (or a falling-back production) resolver may complete with an
      // error; the failure is a terminal state of the resolution, so it is
      // flattened to null here and notified like every other outcome.
      _resolveAccountUserId(
        clientId,
      ).then<int?>((userId) => userId, onError: (Object _) => null).then((
        userId,
      ) {
        if (_disposed || _generation != generation) return;
        // A newer active client may have taken over while this one resolved.
        if (_currentClientId != clientId || userId == null) {
          notifyListeners();
          return;
        }
        _activeAccountUserId = userId;
        notifyListeners();
      }),
    );
  }

  Future<int?> _resolveAccountUserId(int clientId) =>
      _resolver.resolve(clientId);

  @visibleForTesting
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _tdSub?.cancel();
    _tdSub = null;
    _activeSlotSub?.cancel();
    _activeSlotSub = null;
    _observing = false;
    _persistTimer?.cancel();
    _persistTimer = null;
    super.dispose();
  }

  /// Seeds the active account's identity for tests; stands in for what
  /// [_refreshActiveAccount] resolves from TDLib in production.
  @visibleForTesting
  void debugSetActiveAccount(int accountUserId) {
    if (!allowTelegramTosViolations) return;
    _activeAccountUserId = accountUserId;
    _activeAccountUserIdSource = null;
    notifyListeners();
  }

  /// Seeds in-memory copies for tests; never touches persistence. Guarded
  /// like every mutator: with the flag off the store stays empty no matter
  /// what reaches it.
  @visibleForTesting
  void debugSeed(List<MessageHistoryEntry> seeded) {
    if (!allowTelegramTosViolations) return;
    for (final entry in seeded) {
      _byKey[entry.key] = entry;
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Recording
  // ---------------------------------------------------------------------------

  void _onTdUpdate(Map<String, dynamic> update) {
    if (!allowTelegramTosViolations) return;
    // Every TDLib update is stamped with the client that received it
    // (updatesOfAny(allAccounts:true) documents this); resolving that to an
    // account user id is what keeps two accounts with identical chat/message
    // ids in two records. Updates without a client id are dropped: there is
    // no way to attribute them, and guessing the active account would
    // misattribute history whenever the active account changes.
    final clientId = update.integer('@client_id');
    if (clientId == null || clientId == 0) return;
    unawaited(_handleUpdateForClient(clientId, update));
  }

  /// Handles one update for [clientId]. The update joins its client's chain
  /// BEFORE identity resolution, so a client's records apply in TDLib
  /// arrival order even when a lookup is slow or stuck; different clients
  /// resolve and record concurrently. BOTH epochs are captured at ARRIVAL
  /// so invalidations that land while the update is queued or resolving
  /// can drop it before it writes.
  Future<void> _handleUpdateForClient(
    int clientId,
    Map<String, dynamic> update,
  ) async {
    final arrivalGeneration = _generation;
    final arrivalScopeEpoch = _scopeEpoch;
    final previous = _clientWorkers[clientId] ?? Future<void>.value();
    final worker = previous
        .catchError((_) {})
        .then(
          (_) => _processUpdateForClient(
            clientId,
            update,
            arrivalGeneration,
            arrivalScopeEpoch,
          ),
        );
    _clientWorkers[clientId] = worker;
    try {
      await worker;
    } finally {
      if (identical(_clientWorkers[clientId], worker)) {
        unawaited(_clientWorkers.remove(clientId));
      }
    }
  }

  /// The chain job of one update: wait for the client's identity (memoized
  /// per client), then record in arrival order. A failed resolution drops
  /// this client's queued events for this attempt — unattributable updates
  /// are never guessed — and the next arrival starts a fresh attempt. An
  /// invalidation that landed after the update arrived drops the write:
  /// pending work can never resurrect cleared or removed history. The drop
  /// check is SCOPED — only the removed account's or cleared chat's own
  /// queued updates are dropped; every other account's and chat's pending
  /// work records as usual. Only the global generation (clearAll, dispose)
  /// cancels across all scopes.
  Future<void> _processUpdateForClient(
    int clientId,
    Map<String, dynamic> update,
    int arrivalGeneration,
    int arrivalScopeEpoch,
  ) async {
    final userId = await _identityOf(clientId);
    if (userId == null) return; // unattributable — never guess
    final removedAt = _removedAccountAt[userId];
    if (removedAt != null && removedAt > arrivalScopeEpoch) {
      return; // its account was removed after the update arrived
    }
    final chatId = _updateChatId(update);
    if (chatId != null) {
      final clearedAt = _clearedChatAt['$userId:$chatId'];
      if (clearedAt != null && clearedAt > arrivalScopeEpoch) {
        return; // its chat was cleared after the update arrived
      }
    }
    if (_disposed || _generation != arrivalGeneration) return;
    unawaited(_recordUpdate(userId, update));
    // New evidence about the ACTIVE client's identity: when the active
    // resolution already failed (or was dropped), a successful resolution
    // here reconciles the active account instead of leaving the viewer
    // empty until the next slot switch.
    if (clientId == _activeAccountUserIdSource &&
        _activeAccountUserId == null) {
      _activeAccountUserId = userId;
      notifyListeners();
    }
  }

  /// The chat id an update targets, when the update payload carries one
  /// (all four observed update types do). Null for an update whose payload
  /// is missing or malformed — there is then no chat scope to check.
  static int? _updateChatId(Map<String, dynamic> update) {
    switch (update.type) {
      case 'updateNewMessage':
        return update.obj('message')?.int64('chat_id');
      case 'updateMessageEdited':
      case 'updateMessageContent':
      case 'updateDeleteMessages':
        return update.int64('chat_id');
      case 'updateChat':
        return update.obj('chat')?.int64('id');
    }
    return null;
  }

  /// Identity resolution memoized per client: concurrent events share the
  /// in-flight lookup, and a KNOWN identity stays cached for the client's
  /// following events. A failed or unresolved lookup (exception, null) is
  /// dropped from the memo so the next arrival starts a fresh attempt
  /// instead of caching the failure; a global wipe (clearAll) or disposal
  /// forgets in-flight attempts too. SCOPED invalidations (removing one
  /// account, clearing one chat) touch neither the memo nor in-flight
  /// lookups — a client's identity does not change when an unrelated
  /// account is removed — the scope filter runs per resolved account in
  /// [_processUpdateForClient].
  Future<int?> _identityOf(int clientId) {
    final inFlight = _identityFutures[clientId];
    if (inFlight != null) return inFlight;
    final generation = _generation;
    // The lookup starts synchronously (no extra event-loop hop): the chain
    // job of a just-arrived update must complete within the same drain, the
    // way the per-account worker did before arrival-order queueing existed.
    Future<int?> settle(Future<int?> lookup) => lookup.then<int?>((userId) {
      final invalidated = _disposed || _generation != generation;
      final resolved = invalidated ? null : userId;
      if (resolved == null) _identityFutures.remove(clientId);
      return resolved;
    });
    Future<int?> attempt;
    try {
      attempt = settle(_resolver.resolve(clientId)).catchError((Object _) {
        // Resolution failed: forget the attempt so a later event retries.
        _identityFutures.remove(clientId);
        return null;
      });
    } catch (_) {
      // A resolver that throws synchronously (instead of returning a failed
      // future) resolves to nothing; the next arrival starts a new attempt.
      return Future<int?>.value();
    }
    _identityFutures[clientId] = attempt;
    return attempt;
  }

  Future<void> _recordUpdate(int accountUserId, Map<String, dynamic> update) {
    switch (update.type) {
      case 'updateNewMessage':
        _recordIncomingMessage(accountUserId, update.obj('message'));
      case 'updateMessageEdited':
        _rememberEditDate(accountUserId, update);
      case 'updateMessageContent':
        _recordContentUpdate(accountUserId, update);
      case 'updateDeleteMessages':
        _recordDeletedMessages(accountUserId, update);
      case 'updateChat':
        _recordChatLiveness(accountUserId, update);
    }
    return Future<void>.value();
  }

  /// Mirrors one incoming message. Also runs for messages that come back
  /// (cache eviction refetch, album resend): those refresh the copy but keep
  /// the recorded history, and a message deleted earlier becomes active
  /// again because it exists again.
  void recordIncomingMessage(Map<String, dynamic>? message) =>
      _recordIncomingMessage(_activeAccountUserId, message);

  void _recordIncomingMessage(
    int? accountUserId,
    Map<String, dynamic>? message,
  ) {
    if (!allowTelegramTosViolations) return;
    if (accountUserId == null || message == null) return;
    final chatId = message.int64('chat_id');
    // The message object carries its own id in `id` (message_id is the field
    // name on the update wrappers, not on message).
    final messageId = message.integer('id');
    if (chatId == null || messageId == null) return;
    // The mirror keeps what the counterpart could take away: only incoming
    // messages. The account's own outgoing ones stay Telegram's business.
    // Saved Messages (chat id == own user id) is incoming from itself and is
    // still kept, mirroring AyuGram's treatment of the self dialog.
    final isOutgoing = message.boolean('is_outgoing') ?? false;
    final isSelfChat = chatId == accountUserId;
    if (isOutgoing && !isSelfChat) return;
    if (_excludedChatsByAccount[accountUserId]?.contains(chatId) ?? false) {
      return;
    }

    final key = '$accountUserId:$chatId:$messageId';
    final existing = _byKey[key];
    if (existing != null) {
      final refreshed = existing.copyWith(
        text: _messageText(message.obj('content')) ?? existing.text,
        kindKey: _messageKindKey(message.obj('content')) ?? '',
        senderId: _senderId(message) ?? existing.senderId,
        state: MessageHistoryState.active,
        deletedAt: 0,
      );
      if (refreshed == existing) return;
      _byKey[key] = refreshed;
      notifyListeners();
      _schedulePersist();
      _snapshotMediaOf(accountUserId, chatId, messageId, message);
      return;
    }

    final date = message.integer('date') ?? 0;
    final content = message.obj('content');
    _byKey[key] = MessageHistoryEntry(
      accountUserId: accountUserId,
      chatId: chatId,
      messageId: messageId,
      senderId: _senderId(message) ?? 0,
      date: date,
      text: _messageText(content) ?? '',
      kindKey: _messageKindKey(content) ?? '',
      state: MessageHistoryState.active,
      deletedAt: 0,
      events: const [],
    );
    _trim();
    notifyListeners();
    _schedulePersist();
    _snapshotMediaOf(accountUserId, chatId, messageId, message);
  }

  /// Copies a mirrored message's media file into the mirror's attachment
  /// directory when it is already fully on disk, then records the path. A
  /// later snapshot (delete-time copy) only fills an empty path — the first
  /// copy wins so a snapshot is never taken for content the mirror did not
  /// see arrive.
  void _snapshotMediaOf(
    int accountUserId,
    int chatId,
    int messageId,
    Map<String, dynamic> message,
  ) {
    final file = _contentSnapshotFile(message.obj('content'));
    if (file == null) return;
    final key = '$accountUserId:$chatId:$messageId';
    final generation = _generation;
    unawaited(
      _media()
          .snapshot(
            file,
            accountUserId: accountUserId,
            chatId: chatId,
            messageId: messageId,
          )
          .then((path) {
            if (path == null) return;
            // The copy raced a global wipe or disposal: the store's state
            // moved on, so the late path is dropped instead of resurrecting
            // the entry (and notifyListeners on a disposed store).
            if (_disposed || _generation != generation) return;
            final existing = _byKey[key];
            if (existing == null || existing.mediaPath.isNotEmpty) return;
            _byKey[key] = existing.copyWith(mediaPath: path);
            notifyListeners();
            _schedulePersist();
          }),
    );
  }

  /// The file object worth snapshotting for a content payload: the biggest
  /// photo size for photos, the document for documents / audio / voice /
  /// video, null for everything else (stickers animate from server data and
  /// cached copies rarely survive, exactly like AyuGram's scope).
  static Map<String, dynamic>? _contentSnapshotFile(
    Map<String, dynamic>? content,
  ) {
    if (content == null) return null;
    switch (content.type) {
      case 'messagePhoto':
        final photo = content.obj('photo');
        final sizes = photo?.objects('sizes');
        if (sizes == null || sizes.isEmpty) return null;
        Map<String, dynamic>? best;
        var bestArea = -1;
        for (final size in sizes) {
          final candidate = size.obj('photo');
          if (candidate == null) continue;
          final area =
              (size.integer('width') ?? 0) * (size.integer('height') ?? 0);
          if (area > bestArea) {
            bestArea = area;
            best = candidate;
          }
        }
        return best;
      case 'messageAudio':
        // messageAudio wraps the file in audio.audio.
        return content.obj('audio')?.obj('audio');
      case 'messageVoiceNote':
        // messageVoiceNote wraps the file in voice_note.voice.
        return content.obj('voice_note')?.obj('voice');
      case 'messageVideo':
      case 'messageAnimation':
      case 'messageDocument':
        return content.obj('animation') ??
            content.obj('video') ??
            content.obj('document');
    }
    return null;
  }

  MessageMediaSnapshotter _media() =>
      mediaSnapshotter ?? MessageMediaSnapshotter.shared;

  /// The snapshotter the viewer should resolve preview paths against —
  /// the injected one in tests, the shared one in production.
  MessageMediaSnapshotter get mediaSnapshotterForView => _media();

  /// The injected snapshotter (tests); defaults to the shared one.
  @visibleForTesting
  MessageMediaSnapshotter? mediaSnapshotter;

  /// updateChat: remembers per (account, chat) whether the chat is still
  /// openable. A chat the counterpart destroyed (deleted account, gone
  /// secret chat, or a chat that no longer resolves) marks its kept entries
  /// with `hasLiveChat false`, the AyuGram AyuDeleted semantics.
  void _recordChatLiveness(int accountUserId, Map<String, dynamic> update) {
    final chat = update.obj('chat');
    if (chat == null) return;
    final chatId = chat.int64('id');
    if (chatId == null) return;
    final gone = switch (chat.obj('type')?.type) {
      'chatTypeUnknown' => true,
      _ => false,
    };
    if (gone == _deadChats.contains('$accountUserId:$chatId')) return;
    if (gone) {
      _deadChats.add('$accountUserId:$chatId');
    } else {
      _deadChats.remove('$accountUserId:$chatId');
    }
    var changed = false;
    for (final entry in _byKey.values.toList(growable: false)) {
      if (entry.accountUserId != accountUserId || entry.chatId != chatId) {
        continue;
      }
      _byKey[entry.key] = entry.copyWith(hasLiveChat: !gone);
      changed = true;
    }
    if (changed) {
      notifyListeners();
      _schedulePersist();
    }
  }

  /// updateMessageEdited carries the edit time but not the content; the new
  /// content arrives in a following updateMessageContent. Only that pair —
  /// not TDLib's own content generations (dice rolls, live locations) —
  /// produces an edit event. Pending dates are owned by the account whose
  /// client observed the edit.
  void _rememberEditDate(int accountUserId, Map<String, dynamic> update) {
    final chatId = update.int64('chat_id');
    final messageId = update.integer('message_id');
    if (chatId == null || messageId == null) return;
    _pendingEditDates['$accountUserId:$chatId:$messageId'] =
        update.integer('edit_date') ?? 0;
  }

  void _recordContentUpdate(int accountUserId, Map<String, dynamic> update) {
    final chatId = update.int64('chat_id');
    final messageId = update.integer('message_id');
    if (chatId == null || messageId == null) return;
    final key = '$accountUserId:$chatId:$messageId';
    final editDate = _pendingEditDates.remove(key);
    if (editDate == null) return;

    // Re-read after the await in [_handleUpdateForClient]: the mirror may
    // have loaded or changed since the update was received.
    final existing = _byKey[key];
    if (existing == null || existing.state == MessageHistoryState.deleted) {
      return;
    }
    final content = update.obj('new_content');
    final newText = _messageText(content) ?? '';
    final newKind = _messageKindKey(content) ?? '';
    if (newText == existing.text && newKind == existing.kindKey) return;

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final event = MessageHistoryEvent(
      at: now,
      oldText: existing.text,
      newText: newText,
      editDate: editDate,
    );
    _byKey[key] = existing.copyWith(
      text: newText,
      kindKey: newKind,
      events: [...existing.events, event],
    );
    notifyListeners();
    _schedulePersist();
  }

  /// updateDeleteMessages marks known, still-active entries as deleted.
  /// TDLib sends it for permanent deletions and for messages that merely
  /// became inaccessible or were cache-evicted (`is_permanent: false`,
  /// `from_cache: true`); both belong in the mirror — the mirror's job is
  /// precisely to keep what the chat no longer shows. A message that really
  /// comes back re-activates through [recordIncomingMessage]. Deletions only
  /// ever touch the observing account's copy.
  void _recordDeletedMessages(int accountUserId, Map<String, dynamic> update) {
    final chatId = update.int64('chat_id');
    if (chatId == null) return;
    final ids = update.int64Array('message_ids') ?? const <int>[];
    if (ids.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    var changed = false;
    for (final messageId in ids) {
      final key = '$accountUserId:$chatId:$messageId';
      final existing = _byKey[key];
      if (existing == null) continue;
      if (existing.state == MessageHistoryState.deleted) continue;
      _byKey[key] = existing.copyWith(
        state: MessageHistoryState.deleted,
        deletedAt: now,
      );
      changed = true;
    }
    if (!changed) return;
    notifyListeners();
    _schedulePersist();
  }

  // ---------------------------------------------------------------------------
  // Exclusions, clearing
  // ---------------------------------------------------------------------------

  /// Stops the ACTIVE account from recording [chatId] and drops its kept
  /// copies of that chat — an excluded chat must have no mirror at all, not
  /// just a paused one. Other accounts' copies of the same chat are kept.
  void excludeChat(int chatId) {
    if (!allowTelegramTosViolations) return;
    final accountUserId = _activeAccountUserId;
    if (accountUserId == null) return;
    final excluded = _excludedChatsByAccount.putIfAbsent(
      accountUserId,
      () => <int>{},
    );
    if (!excluded.add(chatId)) return;
    _clearedChatAt['$accountUserId:$chatId'] = ++_scopeEpoch;
    _pendingEditDates.removeWhere(
      (key, _) => key.startsWith('$accountUserId:$chatId:'),
    );
    _byKey.removeWhere(
      (key, entry) =>
          entry.accountUserId == accountUserId && entry.chatId == chatId,
    );
    _media().deleteScope(accountUserId, chatId);
    _persistExcludedChats(accountUserId);
    notifyListeners();
    _schedulePersist();
  }

  void includeChat(int chatId) {
    if (!allowTelegramTosViolations) return;
    final accountUserId = _activeAccountUserId;
    if (accountUserId == null) return;
    final excluded = _excludedChatsByAccount[accountUserId];
    if (excluded == null || !excluded.remove(chatId)) return;
    _persistExcludedChats(accountUserId);
    notifyListeners();
  }

  /// Removes the active account's kept copies of [chatId]; returns how many
  /// went away. Scope-stamps (account, chat) so an in-flight load cannot
  /// re-add the cleared rows from the mirror file afterwards, and queued
  /// updates for that chat that arrived before the clear are dropped after
  /// their identity resolves — without cancelling any other chat's or
  /// account's pending work.
  int clearChat(int chatId) {
    if (!allowTelegramTosViolations) return 0;
    final accountUserId = _activeAccountUserId;
    if (accountUserId == null) return 0;
    final keys = [
      for (final entry in _byKey.values)
        if (entry.accountUserId == accountUserId && entry.chatId == chatId)
          entry.key,
    ];
    for (final key in keys) {
      _byKey.remove(key);
    }
    _pendingEditDates.removeWhere(
      (key, _) => key.startsWith('$accountUserId:$chatId:'),
    );
    _clearedChatAt['$accountUserId:$chatId'] = ++_scopeEpoch;
    _media().deleteScope(accountUserId, chatId);
    notifyListeners();
    _schedulePersist();
    return keys.length;
  }

  /// Removes every kept copy of every account; returns how many went away.
  /// Deliberately global: "clear everything" must not leave invisible
  /// mirrors behind. Bumps the generation AND the scope epoch so pending
  /// queued updates and an in-flight load cannot resurrect any of it.
  int clearAll() {
    if (!allowTelegramTosViolations) return 0;
    final removed = _byKey.length;
    _byKey.clear();
    _pendingEditDates.clear();
    _generation++;
    _clearedAllAt = ++_scopeEpoch;
    _media().deleteAll();
    notifyListeners();
    _schedulePersist();
    return removed;
  }

  /// Forgets an account entirely: its kept copies, its pending edit dates
  /// and its exclusion preference. Called when a slot is logged out or
  /// removed; account identity is known there, so nothing is guessed.
  /// Instead of the store-wide generation bump, the removal is SCOPE-stamped
  /// with the scope epoch: queued updates of THIS account that arrived
  /// before the removal are dropped once their identity resolves (pending
  /// work can never recreate history after logout/removal), while every
  /// other account's queued updates, loads and resolution continuations
  /// keep running untouched.
  void removeAccount(int accountUserId) {
    if (!allowTelegramTosViolations) return;
    var changed = false;
    final keys = [
      for (final entry in _byKey.values)
        if (entry.accountUserId == accountUserId) entry.key,
    ];
    for (final key in keys) {
      _byKey.remove(key);
    }
    if (keys.isNotEmpty) changed = true;
    _pendingEditDates.removeWhere(
      (key, _) => key.startsWith('$accountUserId:'),
    );
    _media().deleteAccount(accountUserId);
    if (_excludedChatsByAccount.remove(accountUserId) != null) changed = true;
    unawaited(_prefs?.remove('$_prefsKeyPrefix$accountUserId'));
    _removedAccountAt[accountUserId] = ++_scopeEpoch;
    if (_activeAccountUserId == accountUserId) {
      _activeAccountUserId = null;
      _activeAccountUserIdSource = null;
    }
    notifyListeners();
    if (changed) {
      _schedulePersist();
    }
  }

  /// Removes one kept entry (viewer row delete); also drops its snapshot.
  void deleteEntry(MessageHistoryEntry entry) {
    if (!allowTelegramTosViolations) return;
    if (_byKey.remove(entry.key) == null) return;
    if (entry.mediaPath.isNotEmpty) {
      _media().deleteFile(entry.mediaPath);
    }
    notifyListeners();
    _schedulePersist();
  }

  void _persistExcludedChats(int accountUserId) {
    _prefs?.setStringList('$_prefsKeyPrefix$accountUserId', [
      for (final chatId
          in _excludedChatsByAccount[accountUserId] ?? const <int>{})
        '$chatId',
    ]);
  }

  // ---------------------------------------------------------------------------
  // Persistence — one JSON file for every account, batched, written
  // atomically via rename. Keys are account-scoped, so accounts share the
  // file without ever overwriting each other.
  // ---------------------------------------------------------------------------

  Future<void> ensureLoaded() async {
    if (!allowTelegramTosViolations) return;
    if (_loaded || _disposed) return;
    _loaded = true;
    final generation = _generation;
    try {
      final dir = fileDir ?? await getApplicationSupportDirectory();
      final file = File('${dir.path}/$_fileName');
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      // The generation re-check drops the load when the store was wiped
      // (clearAll) or disposed while the file was being read: a fresh
      // on-disk batch must never resurrect the invalidated state. A SCOPED
      // invalidation (one account removed, one chat cleared) cancels only
      // its own disk rows below — every other account's and chat's rows
      // still load. Rows are judged against the scope epoch the FILE
      // reflects: a row whose scope was invalidated after the last persist
      // is stale on disk and is dropped even when the invalidation happened
      // before this load started.
      if (_disposed || _generation != generation) return;
      if (_clearedAllAt > _persistedScopeEpoch) return;
      if (decoded is! Map) return;
      final raw = decoded['entries'];
      if (raw is! List) return;
      for (final json in raw) {
        final entry = MessageHistoryEntry.fromJson(json);
        if (entry == null) continue;
        final removedAt = _removedAccountAt[entry.accountUserId];
        if (removedAt != null && removedAt > _persistedScopeEpoch) continue;
        final clearedAt =
            _clearedChatAt['${entry.accountUserId}:${entry.chatId}'];
        if (clearedAt != null && clearedAt > _persistedScopeEpoch) continue;
        _byKey.putIfAbsent(entry.key, () => entry);
      }
      _trim();
    } catch (_) {
      // A corrupt mirror must never break the app; start over on next write.
    }
    if (_disposed || _generation != generation) return;
    notifyListeners();
  }

  void _schedulePersist() {
    if (!allowTelegramTosViolations) return;
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 800), () {
      unawaited(_persistNow());
    });
  }

  Future<void> _persistNow() async {
    if (!allowTelegramTosViolations || _disposed) return;
    if (_persisting) {
      _dirtyWhilePersisting = true;
      return;
    }
    _persisting = true;
    try {
      final dir = fileDir ?? await getApplicationSupportDirectory();
      final tmp = File('${dir.path}/$_fileName$_tmpSuffix');
      final batchScopeEpoch = _scopeEpoch;
      final batch = {
        'version': 2,
        'entries': [
          for (final entry in _byKey.values.skip(
            (_byKey.length - persistBatch).clamp(0, maxEntries),
          ))
            entry.toJson(),
        ],
      };
      await tmp.writeAsString(jsonEncode(batch), flush: true);
      final beforeRename = beforePersistRenameForTesting;
      if (beforeRename != null) await beforeRename();
      await tmp.rename('${dir.path}/$_fileName');
      // The file now reflects this exact invalidation state: loads may
      // trust every row in it again.
      _persistedScopeEpoch = batchScopeEpoch;
    } catch (_) {
      return;
    } finally {
      _persisting = false;
    }
    if (_dirtyWhilePersisting) {
      _dirtyWhilePersisting = false;
      _schedulePersist();
    }
  }

  @visibleForTesting
  Future<void> persistNowForTesting() => _persistNow();

  void _trim() {
    while (_byKey.length > maxEntries) {
      _byKey.remove(_byKey.keys.first);
    }
  }

  // ---------------------------------------------------------------------------
  // Message field extraction
  // ---------------------------------------------------------------------------

  int? _senderId(Map<String, dynamic> message) {
    final sender = message.obj('sender_id');
    if (sender == null) return null;
    switch (sender.type) {
      case 'messageSenderUser':
        return sender.int64('user_id');
      case 'messageSenderChat':
        return sender.int64('chat_id');
    }
    return null;
  }

  /// Plain text of a [formattedText] object.
  static String? _formattedText(Map<String, dynamic>? formatted) =>
      formatted?.str('text');

  /// The message's text, or its caption for captioned media.
  static String? _messageText(Map<String, dynamic>? content) {
    if (content == null) return null;
    switch (content.type) {
      case 'messageText':
        return _formattedText(content.obj('text'));
      case 'messagePhoto':
      case 'messageVideo':
      case 'messageAnimation':
      case 'messageAudio':
      case 'messageDocument':
      case 'messageVoiceNote':
        return _formattedText(content.obj('caption')) ?? '';
    }
    return null;
  }

  /// Maps a TDLib content type onto the [AppStringKeys] suffix of a localized
  /// kind label; null for plain text. Stored as the bare suffix so the key
  /// names stay in one place (the viewer).
  static String? _messageKindKey(Map<String, dynamic>? content) {
    if (content == null) return null;
    switch (content.type) {
      case 'messagePhoto':
      case 'messageExpiredPhoto':
        return 'historyKindPhoto';
      case 'messageVideo':
      case 'messageExpiredVideo':
        return 'historyKindVideo';
      case 'messageVideoNote':
      case 'messageExpiredVideoNote':
        return 'historyKindVideoNote';
      case 'messageVoiceNote':
        return 'historyKindVoice';
      case 'messageAnimation':
        return 'historyKindAnimation';
      case 'messageSticker':
        return 'historyKindSticker';
      case 'messageDocument':
        return 'historyKindDocument';
      case 'messageAudio':
        return 'historyKindAudio';
      case 'messagePoll':
        return 'historyKindPoll';
      case 'messageLocation':
      case 'messageLiveLocation':
        return 'historyKindLocation';
      case 'messageContact':
        return 'historyKindContact';
      case 'messageDice':
        return 'historyKindDice';
    }
    return null;
  }
}
