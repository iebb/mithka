//
//  blocked_user_service.dart
//
//  Account-scoped snapshots of Telegram blocked senders. Each load stays
//  pinned to the account that initiated it and is published atomically, so a
//  failed refresh cannot replace a known-good block list with an empty one.
//

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';

typedef BlockedUserQueryForSlot =
    Future<Map<String, dynamic>> Function(
      Map<String, dynamic> request,
      int accountSlot,
    );

class BlockedUserService extends ChangeNotifier {
  BlockedUserService._({
    BlockedUserQueryForSlot? queryForSlot,
    int Function()? activeSlot,
    Stream<int>? activeSlotChanges,
    Stream<Map<String, dynamic>>? allUpdates,
    int? Function(int clientId)? slotForClient,
  }) : _queryForSlot = queryForSlot ?? TdClient.shared.queryForSlot,
       _activeSlot = activeSlot ?? (() => TdClient.shared.activeSlot),
       _activeSlotChanges =
           activeSlotChanges ?? TdClient.shared.subscribeActiveSlotChanges(),
       _allUpdates = allUpdates ?? TdClient.shared.subscribeAll(),
       _slotForClient = slotForClient ?? TdClient.shared.slotForClient;

  @visibleForTesting
  factory BlockedUserService.forTesting({
    required BlockedUserQueryForSlot queryForSlot,
    required int Function() activeSlot,
    Stream<int> activeSlotChanges = const Stream<int>.empty(),
    Stream<Map<String, dynamic>> allUpdates =
        const Stream<Map<String, dynamic>>.empty(),
    int? Function(int clientId)? slotForClient,
  }) => BlockedUserService._(
    queryForSlot: queryForSlot,
    activeSlot: activeSlot,
    activeSlotChanges: activeSlotChanges,
    allUpdates: allUpdates,
    slotForClient: slotForClient ?? (_) => null,
  );

  static final BlockedUserService shared = BlockedUserService._();

  final BlockedUserQueryForSlot _queryForSlot;
  final int Function() _activeSlot;
  final Stream<int> _activeSlotChanges;
  final Stream<Map<String, dynamic>> _allUpdates;
  final int? Function(int clientId) _slotForClient;
  final Map<int, Set<int>> _blockedUserIdsBySlot = {};
  final Set<int> _loadedSlots = {};
  final Map<int, bool> _enabledBySlot = {};
  final Map<int, Set<int>> _locallyBlockedBySlot = {};
  final Map<int, Future<void>> _loadsBySlot = {};

  StreamSubscription<int>? _slotSub;
  StreamSubscription<Map<String, dynamic>>? _authSub;
  bool _started = false;

  /// Whether the active account hides messages from its blocked users.
  bool get enabled => _enabledBySlot[_activeSlot()] ?? false;
  set enabled(bool value) {
    final slot = _activeSlot();
    if ((_enabledBySlot[slot] ?? false) == value) return;
    _enabledBySlot[slot] = value;
    notifyListeners();
  }

  bool get isLoaded => _loadedSlots.contains(_activeSlot());

  bool isBlocked(int senderId) =>
      _blockedUserIdsBySlot[_activeSlot()]?.contains(senderId) ?? false;

  void _ensureStarted() {
    if (_started) return;
    _started = true;
    _slotSub = _activeSlotChanges.listen((slot) {
      notifyListeners();
      unawaited(loadBlockedUsers(accountSlot: slot));
    });
    _authSub = _allUpdates.listen((update) {
      if (update.type != 'updateAuthorizationState') return;
      final clientId = update.integer('@client_id');
      final slot = clientId == null ? null : _slotForClient(clientId);
      if (slot == null) return;
      final state = update.obj('authorization_state')?.type;
      if (state == 'authorizationStateReady') {
        unawaited(loadBlockedUsers(accountSlot: slot));
      } else if (state == 'authorizationStateClosed') {
        _blockedUserIdsBySlot.remove(slot);
        _loadedSlots.remove(slot);
        _enabledBySlot.remove(slot);
        _locallyBlockedBySlot.remove(slot);
        if (slot == _activeSlot()) notifyListeners();
      }
    });
  }

  Future<void> loadBlockedUsers({int? accountSlot}) {
    _ensureStarted();
    final slot = accountSlot ?? _activeSlot();
    final existing = _loadsBySlot[slot];
    if (existing != null) return existing;
    late final Future<void> operation;
    operation = _loadBlockedUsers(slot).whenComplete(() {
      if (identical(_loadsBySlot[slot], operation)) {
        _loadsBySlot.remove(slot);
      }
    });
    _loadsBySlot[slot] = operation;
    return operation;
  }

  Future<void> _loadBlockedUsers(int accountSlot) async {
    final next = <int>{};
    try {
      var offset = 0;
      const limit = 200;
      while (true) {
        final result = await _queryForSlot({
          '@type': 'getBlockedMessageSenders',
          'block_list': {'@type': 'blockListMain'},
          'offset': offset,
          'limit': limit,
        }, accountSlot);
        final senders = result['senders'] as List<dynamic>?;
        if (senders == null || senders.isEmpty) break;
        for (final sender in senders) {
          if (sender is! Map<String, dynamic>) continue;
          final senderData =
              sender['sender'] as Map<String, dynamic>? ?? sender;
          if (senderData['@type'] != 'messageSenderUser') continue;
          final userId = senderData['user_id'];
          if (userId is int) next.add(userId);
        }
        if (senders.length < limit) break;
        offset += limit;
      }
    } catch (_) {
      // Keep the previous known-good snapshot. In particular, never publish an
      // empty list merely because an account is offline during a refresh.
      return;
    }

    next.addAll(_locallyBlockedBySlot[accountSlot] ?? const <int>{});
    _blockedUserIdsBySlot[accountSlot] = Set<int>.unmodifiable(next);
    _locallyBlockedBySlot.remove(accountSlot);
    _loadedSlots.add(accountSlot);
    if (accountSlot == _activeSlot()) notifyListeners();
  }

  Future<void> blockUser(int userId) async {
    if (userId <= 0) return;
    _ensureStarted();
    final slot = _activeSlot();
    if (_blockedUserIdsBySlot[slot]?.contains(userId) ?? false) return;
    await _queryForSlot({
      '@type': 'setMessageSenderBlockList',
      'sender_id': {'@type': 'messageSenderUser', 'user_id': userId},
      'block_list': {'@type': 'blockListMain'},
    }, slot);
    final next = <int>{...?_blockedUserIdsBySlot[slot], userId};
    _locallyBlockedBySlot.putIfAbsent(slot, () => <int>{}).add(userId);
    _blockedUserIdsBySlot[slot] = Set<int>.unmodifiable(next);
    if (slot == _activeSlot()) notifyListeners();
    if (!_loadedSlots.contains(slot)) {
      await loadBlockedUsers(accountSlot: slot);
    }
  }

  @override
  void dispose() {
    unawaited(_slotSub?.cancel());
    unawaited(_authSub?.cancel());
    super.dispose();
  }
}
