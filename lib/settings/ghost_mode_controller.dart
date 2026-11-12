//
//  ghost_mode_controller.dart
//
//  Ghost mode (anti-recall style stealth). Guards the app behind the compile-time
//  `allowTelegramTosViolations` flag: when the flag is absent or false the
//  controller stays permanently disabled, every query method returns the
//  "never block" answer, and nothing else in the app changes. Preferences are
//  persisted in SharedPreferences so they survive restarts of self-built
//  binaries.
//
//  Semantics: a global switch plus a
//  per-chat three-state exception — `default` follows the global switch,
//  `forceBlock` always intercepts, `forceAllow` never intercepts.
//

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/build_flags.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';

/// Per-chat exception state. [defaultState] follows the global switch.
enum GhostChatException {
  defaultState(0),
  forceBlock(1),
  forceAllow(2);

  const GhostChatException(this.storedValue);

  final int storedValue;

  static GhostChatException fromStoredValue(int value) =>
      GhostChatException.values.firstWhere(
        (entry) => entry.storedValue == value,
        orElse: () => GhostChatException.defaultState,
      );
}

/// Decision for one interception dimension in one chat, already resolved
/// against the global switch and the chat's exception state.
enum GhostInterceptDecision {
  block,
  allow;

  bool get isBlock => this == GhostInterceptDecision.block;
}

class GhostModeController extends ChangeNotifier {
  GhostModeController._();

  static final GhostModeController shared = GhostModeController._();

  /// Compile-time availability. False outside opted-in self-built binaries;
  /// every UI entry and every interception path consults this first.
  static bool get isAvailable => allowTelegramTosViolations;

  static const _globalEnabledKey = 'ghost_mode.enabled';
  static const _blockReadReceiptsKey = 'ghost_mode.blockReadReceipts';
  static const _blockStoryReadsKey = 'ghost_mode.blockStoryReads';
  static const _blockTypingKey = 'ghost_mode.blockTyping';
  static const _hideOnlineKey = 'ghost_mode.hideOnline';
  static const _showSidebarEntryKey = 'ghost_mode.showSidebarEntry';
  static const _chatExceptionKeyPrefix = 'ghost_mode.chat.';

  // Dimensions default to blocking while ghost mode is on; toggling only a
  // dimension off therefore needs a first tap, not a first tap and a second.
  static const _defaultBlockReadReceipts = true;
  static const _defaultBlockStoryReads = true;
  static const _defaultBlockTyping = true;
  static const _defaultHideOnline = true;
  static const _defaultShowSidebarEntry = true;

  SharedPreferences? _prefs;
  StreamSubscription<Map<String, dynamic>>? _authSub;

  bool _globalEnabled = false;
  bool _blockReadReceipts = _defaultBlockReadReceipts;
  bool _blockStoryReads = _defaultBlockStoryReads;
  bool _blockTyping = _defaultBlockTyping;
  bool _hideOnline = _defaultHideOnline;
  bool _showSidebarEntry = _defaultShowSidebarEntry;
  final Map<int, GhostChatException> _chatExceptions = {};

  bool get globalEnabled => _globalEnabled && isAvailable;
  bool get blockReadReceipts => _blockReadReceipts;
  bool get blockStoryReads => _blockStoryReads;
  bool get blockTyping => _blockTyping;
  bool get hideOnline => _hideOnline;

  /// Whether the drawer sidebar and the desktop rail carry the ghost-mode
  /// shortcut at all. Pure placement: flipping it never touches
  /// interception, which keeps working with the entry hidden.
  bool get showSidebarEntry => _showSidebarEntry;

  Map<int, GhostChatException> get chatExceptions =>
      Map<int, GhostChatException>.unmodifiable(_chatExceptions);

  GhostChatException exceptionFor(int chatId) =>
      _chatExceptions[chatId] ?? GhostChatException.defaultState;

  /// Loads the persisted state and subscribes to authorization-ready updates.
  /// Safe to call again (the desktop settings reload re-seeds shared stores).
  void initialize(SharedPreferences prefs) {
    if (!isAvailable) return;
    _prefs = prefs;
    _globalEnabled = prefs.getBool(_globalEnabledKey) ?? false;
    _blockReadReceipts =
        prefs.getBool(_blockReadReceiptsKey) ?? _defaultBlockReadReceipts;
    _blockStoryReads =
        prefs.getBool(_blockStoryReadsKey) ?? _defaultBlockStoryReads;
    _blockTyping = prefs.getBool(_blockTypingKey) ?? _defaultBlockTyping;
    _hideOnline = prefs.getBool(_hideOnlineKey) ?? _defaultHideOnline;
    _showSidebarEntry =
        prefs.getBool(_showSidebarEntryKey) ?? _defaultShowSidebarEntry;
    _chatExceptions.clear();
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_chatExceptionKeyPrefix)) continue;
      final chatId = int.tryParse(
        key.substring(_chatExceptionKeyPrefix.length),
      );
      if (chatId == null) continue;
      _chatExceptions[chatId] = GhostChatException.fromStoredValue(
        prefs.getInt(key) ?? 0,
      );
    }
    unawaited(_authSub?.cancel());
    _authSub = null;
    if (!isAvailable) return;
    _authSub = TdClient.shared
        .updatesOf('updateAuthorizationState', allAccounts: true)
        .listen((update) {
          if (update.obj('authorization_state')?.type !=
              'authorizationStateReady') {
            return;
          }
          // Initialization deliberately touches no client: at this point no
          // client's presence has been read, TDLib clients start offline and
          // master sends nothing, so pushing any value here (true above all)
          // would drive presence the user never asked for. Clients that log
          // in afterwards are taken over through the same guarded helper as
          // a toggle, and only while interception is actually active.
          if (!shouldShareOnline()) return;
          final clientId = update.integer('@client_id');
          if (clientId == null) return;
          unawaited(_takeOverClientOnline(clientId));
        });
    // No applyOnlineStatus() here: initialization must stay inert. Persisted
    // enabled state re-arms on the next real transition (toggle or a client
    // becoming ready), where the client's own presence can be read first.
  }

  /// Resolves [chatId] against the global switch and its exception state.
  GhostInterceptDecision decisionFor(
    int chatId,
    bool dimensionEnabled, {
    required bool dimensionOwnsInterception,
  }) {
    if (!globalEnabled || !dimensionEnabled) {
      return GhostInterceptDecision.allow;
    }
    if (dimensionOwnsInterception) {
      // The dimension itself turned interception off (e.g. story playback
      // needs the read marker); only a force-block exception can still
      // intercept that chat.
      return exceptionFor(chatId) == GhostChatException.forceBlock
          ? GhostInterceptDecision.block
          : GhostInterceptDecision.allow;
    }
    return switch (exceptionFor(chatId)) {
      GhostChatException.forceBlock => GhostInterceptDecision.block,
      GhostChatException.forceAllow => GhostInterceptDecision.allow,
      GhostChatException.defaultState => GhostInterceptDecision.block,
    };
  }

  /// Read receipts (viewMessages/force_read): hide that the chat was opened.
  GhostInterceptDecision shouldBlockRead(int chatId) =>
      decisionFor(chatId, _blockReadReceipts, dimensionOwnsInterception: false);

  /// Typing (sendChatAction): hide that the user is composing.
  GhostInterceptDecision shouldBlockTyping(int chatId) =>
      decisionFor(chatId, _blockTyping, dimensionOwnsInterception: false);

  /// Story reads (openStory). Turning the dimension off means the user
  /// wants story seen markers to keep working, so interception then survives
  /// only through a per-chat force-block exception.
  GhostInterceptDecision shouldBlockStories(int chatId) =>
      decisionFor(chatId, true, dimensionOwnsInterception: !_blockStoryReads);

  /// Online status. A global dimension with no per-chat exception: TDLib's
  /// `online` option is per account, not per chat. `true` only while ghost
  /// mode is globally on and the dimension is enabled.
  bool shouldShareOnline() => globalEnabled && _hideOnline;

  Future<void> setGlobalEnabled(bool value) async {
    if (!isAvailable) return;
    if (_globalEnabled == value) return;
    _globalEnabled = value;
    await _prefs?.setBool(_globalEnabledKey, value);
    await _applyOnlineInterception();
    notifyListeners();
  }

  Future<void> setBlockReadReceipts(bool value) async {
    if (!isAvailable) return;
    if (_blockReadReceipts == value) return;
    _blockReadReceipts = value;
    await _prefs?.setBool(_blockReadReceiptsKey, value);
    notifyListeners();
  }

  Future<void> setBlockStoryReads(bool value) async {
    if (!isAvailable) return;
    if (_blockStoryReads == value) return;
    _blockStoryReads = value;
    await _prefs?.setBool(_blockStoryReadsKey, value);
    notifyListeners();
  }

  Future<void> setBlockTyping(bool value) async {
    if (!isAvailable) return;
    if (_blockTyping == value) return;
    _blockTyping = value;
    await _prefs?.setBool(_blockTypingKey, value);
    notifyListeners();
  }

  Future<void> setHideOnline(bool value) async {
    if (!isAvailable) return;
    if (_hideOnline == value) return;
    _hideOnline = value;
    await _prefs?.setBool(_hideOnlineKey, value);
    await _applyOnlineInterception();
    notifyListeners();
  }

  Future<void> setShowSidebarEntry(bool value) async {
    if (!isAvailable) return;
    if (_showSidebarEntry == value) return;
    _showSidebarEntry = value;
    await _prefs?.setBool(_showSidebarEntryKey, value);
    notifyListeners();
  }

  Future<void> setChatException(int chatId, GhostChatException state) async {
    if (!isAvailable) return;
    if (state == GhostChatException.defaultState) {
      if (_chatExceptions.remove(chatId) == null) return;
      await _prefs?.remove('$_chatExceptionKeyPrefix$chatId');
      notifyListeners();
      return;
    }
    if (_chatExceptions[chatId] == state) return;
    _chatExceptions[chatId] = state;
    await _prefs?.setInt('$_chatExceptionKeyPrefix$chatId', state.storedValue);
    notifyListeners();
  }

  /// The presence each client had before ghost mode took its `online`
  /// option over, or `null` when the takeover could not read it. Keyed by
  /// TDLib client id; a missing entry means the client was never taken
  /// over, so releasing it must not send anything either. A `null` value is
  /// an explicitly UNKNOWN capture: the read failed or came back unreadable,
  /// so the controller genuinely does not know that client's requested
  /// presence and release must also send nothing.
  final Map<int, bool?> _preTakeoverOnline = {};

  /// Per-client takeovers whose `getOption` read is still in flight. A
  /// second trigger for the same client awaits the first instead of starting
  /// its own read, so duplicate pending takeovers can never overwrite the
  /// original capture. After the awaited attempt settles, a waiter
  /// revalidates everything before acting on its own: it must not launch a
  /// fresh read while ghost mode is off (its attempt was cancelled), and it
  /// rejoins any newer registered attempt instead of racing it.
  final Map<int, Future<void>> _pendingTakeovers = {};

  /// Upper bound on how many strictly newer attempts a resumed waiter may
  /// join before starting its own read. Joins are bounded so a pathological
  /// enable/disable cycle cannot leave a waiter spinning forever; the bound
  /// is far above any real churn.
  static const _maxTakeoverRejoins = 16;

  /// Applies the current interception state to every registered client:
  /// turning ON reads and records each client's own presence and forces it
  /// offline; turning OFF hands the recorded presence back. Clients never
  /// taken over stay untouched — in particular, disabling ghost mode never
  /// pushes `online=true` out of nowhere.
  Future<void> _applyOnlineInterception() async {
    if (!isAvailable) return;
    final td = TdClient.shared;
    for (final clientId in td.registeredClientIds.toList()) {
      if (shouldShareOnline()) {
        await _takeOverClientOnline(clientId, client: td);
      } else {
        _restoreClientOnline(clientId, client: td);
      }
    }
  }

  /// Forces one client offline while interception is active, after recording
  /// the presence it had, so releasing it later can restore exactly that.
  /// Idempotent: a client already taken over is left as-is, and concurrent
  /// triggers serialize behind the in-flight read instead of racing it.
  Future<void> _takeOverClientOnline(int clientId, {TdClient? client}) async {
    if (_preTakeoverOnline.containsKey(clientId)) return;
    final pending = _pendingTakeovers[clientId];
    if (pending != null) {
      // Serialize: the first takeover either completed the capture (the
      // guard above then turns this trigger into a no-op) or abandoned it
      // through the mid-flight release re-check (this trigger proceeds and
      // reads again). Awaiting first is what keeps a duplicate read from
      // ever overwriting the original capture.
      await pending;
      if (_preTakeoverOnline.containsKey(clientId)) return;
      // The awaited attempt was cancelled mid-flight (a release dropped it
      // while its read was outstanding). Revalidate before acting on its
      // own: no fresh read may start while interception is off — the next
      // enablement starts its own takeover — and any newer registered
      // attempt is rejoined instead of raced. Each iteration only loops
      // after joining a strictly newer attempt, and that join ends back in
      // this loop's rechecks, so the bound below can never truncate a
      // genuinely newer attempt.
      for (var i = 0; i < _maxTakeoverRejoins; i++) {
        if (!shouldShareOnline()) return;
        final newer = _pendingTakeovers[clientId];
        if (newer == null) break;
        await newer;
        if (_preTakeoverOnline.containsKey(clientId)) return;
      }
    }
    final td = client ?? TdClient.shared;
    final inFlight = _runTakeover(clientId, td);
    _pendingTakeovers[clientId] = inFlight;
    try {
      await inFlight;
    } finally {
      if (identical(_pendingTakeovers[clientId], inFlight)) {
        // unawaited only to discard remove()'s return value: the future is
        // already awaited (or abandoned) above.
        unawaited(_pendingTakeovers.remove(clientId));
      }
    }
  }

  /// The read-and-capture half of a takeover. Completing this future is the
  /// moment the capture (or its deliberate absence) is final, so a waiter
  /// can never see a settled takeover whose capture has not landed.
  Future<void> _runTakeover(int clientId, TdClient td) async {
    final attempt = Completer<void>();
    _pendingTakeovers[clientId] = attempt.future;
    try {
      bool? captured;
      try {
        final option = await td.queryTo({
          '@type': 'getOption',
          'name': 'online',
        }, clientId);
        // getOption answers with the optionValueBoolean object itself:
        // {'@type': 'optionValueBoolean', 'value': <bool>}.
        captured = option.boolean('value');
      } catch (_) {
        // A failed read records explicitly UNKNOWN (null), never an assumed
        // value: the controller has not learned the client's requested state
        // and very likely has not even delivered its force-offline through
        // the same transport, so asserting anything on release would drive
        // presence the user never asked for (see _preTakeoverOnline).
        captured = null;
      }
      // A restore may have raced this read (e.g. the global switch flipped
      // while the getOption was in flight); honor the latest state instead of
      // clobbering it with a stale takeover.
      if (!shouldShareOnline()) {
        // unawaited only to discard remove()'s return value: the dropped
        // future belongs to this settling attempt.
        unawaited(_pendingTakeovers.remove(clientId));
        attempt.complete();
        return;
      }
      // A client closed while its read was in flight is gone; recording a
      // capture for it would resurrect bookkeeping nothing can release.
      if (!td.registeredClientIds.contains(clientId)) {
        unawaited(_pendingTakeovers.remove(clientId));
        attempt.complete();
        return;
      }
      _preTakeoverOnline[clientId] = captured;
      unawaited(_pendingTakeovers.remove(clientId));
      applyOnlineStatusToClient(false, clientId, td);
      attempt.complete();
    } catch (error) {
      // The map is cleared before the attempt settles on EVERY path, and an
      // errored attempt surfaces its error to joiners exactly like the
      // directly-awaited future always did.
      unawaited(_pendingTakeovers.remove(clientId));
      attempt.completeError(error);
      rethrow;
    }
  }

  /// Hands one client's `online` option back after a takeover. Sends only
  /// when the client carries a KNOWN capture, so ordinary presence is never
  /// touched, and drops the entry so the next takeover re-reads. An unknown
  /// capture releases silently: sending `true` would manufacture presence
  /// out of a failed read, and sending `false` would pin the client offline
  /// forever — neither is a restore.
  void _restoreClientOnline(int clientId, {required TdClient client}) {
    if (!_preTakeoverOnline.containsKey(clientId)) return;
    final recorded = _preTakeoverOnline.remove(clientId);
    if (recorded == null) return;
    applyOnlineStatusToClient(recorded, clientId, client);
  }

  /// Pushes an explicit `online` value to one client. Public for tests.
  @visibleForTesting
  void applyOnlineStatusToClient(bool online, int clientId, TdClient client) {
    if (!isAvailable) return;
    client.sendTo({
      '@type': 'setOption',
      'name': 'online',
      'value': {'@type': 'optionValueBoolean', 'value': online},
    }, clientId);
  }

  @override
  void dispose() {
    unawaited(_authSub?.cancel());
    _authSub = null;
    super.dispose();
  }
}
