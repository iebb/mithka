//
//  proxy_status.dart
//
//  Live proxy status behind the sidebar's 代理 shortcut: is a proxy saved, is
//  it enabled, and is traffic actually flowing through it.
//
//  TDLib pushes no proxy update — an enabled proxy only ever shows up in a
//  `getProxies` answer — so the snapshot is assembled from two sources. The
//  list is re-read whenever it could have moved: a mutation anywhere in the
//  app, an account switch, or a pushed `updateConnectionState`, because
//  enabling or disabling a proxy always reconnects and that push is then also
//  the "the list moved" signal. Whether the proxy really carries traffic comes
//  from that same pushed state: `connectionStateConnectingToProxy` is the only
//  place TDLib says so.
//

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';

/// What a proxy indicator paints.
///
/// [connecting], [connected] and [unreachable] describe an enabled proxy and
/// mirror the three states Telegram's own clients show for one; [none] and
/// [off] are the two "nothing is flowing" cases a shortcut entry still has to
/// answer, since it is visible before any proxy exists.
enum ProxyIndicator {
  /// No proxy has been added on this account.
  none,

  /// Proxies are saved but none is enabled.
  off,

  /// The enabled proxy is being reached.
  connecting,

  /// The enabled proxy is carrying traffic.
  connected,

  /// A proxy is enabled but there is no network to reach it with.
  unreachable,
}

/// Reduces a `getProxies` reading plus the last pushed TDLib connection state
/// to an indicator. Pure, so the whole matrix is testable without a client.
ProxyIndicator proxyIndicatorFor({
  required bool configured,
  required bool enabled,
  required String? connectionState,
}) {
  if (!configured) return ProxyIndicator.none;
  if (!enabled) return ProxyIndicator.off;
  return switch (connectionState) {
    'connectionStateWaitingForNetwork' => ProxyIndicator.unreachable,
    // Past `connectingToProxy` the tunnel exists: TDLib is talking to Telegram
    // through it (`connecting`), catching up (`updating`) or idle (`ready`).
    'connectionStateConnecting' ||
    'connectionStateUpdating' ||
    'connectionStateReady' => ProxyIndicator.connected,
    // Still handshaking with the proxy server, or no state read yet.
    _ => ProxyIndicator.connecting,
  };
}

/// One reading of the account's proxy list, reduced to what an indicator shows.
@immutable
class ProxyStatusSnapshot {
  const ProxyStatusSnapshot({
    required this.indicator,
    this.server = '',
    this.port = 0,
    this.savedCount = 0,
  });

  /// Nothing has been read yet, so nothing is claimed.
  static const unknown = ProxyStatusSnapshot(indicator: ProxyIndicator.none);

  final ProxyIndicator indicator;

  /// Host and port of the enabled proxy; empty while none is enabled.
  final String server;
  final int port;

  /// How many proxies are saved, enabled or not.
  final int savedCount;

  /// Whether a proxy is switched on, whatever its link is doing.
  bool get isEnabled =>
      indicator == ProxyIndicator.connecting ||
      indicator == ProxyIndicator.connected ||
      indicator == ProxyIndicator.unreachable;

  /// `host:port` of the enabled proxy, for a label that has to name it.
  String get address => server.isEmpty ? '' : '$server:$port';

  @override
  bool operator ==(Object other) =>
      other is ProxyStatusSnapshot &&
      other.indicator == indicator &&
      other.server == server &&
      other.port == port &&
      other.savedCount == savedCount;

  @override
  int get hashCode => Object.hash(indicator, server, port, savedCount);
}

/// One saved proxy, reduced to what a status indicator may hold.
///
/// `addedProxy` embeds a `proxy` whose `type` carries the SOCKS/HTTP username
/// and password or the MTProto secret, so the raw answer is never retained:
/// this is the whole representation that survives a reading.
@immutable
class ProxyReading {
  const ProxyReading({
    required this.isEnabled,
    this.server = '',
    this.port = 0,
  });

  /// Whether TDLib currently routes this account through it.
  final bool isEnabled;

  /// Host and port, the only proxy identity an indicator displays.
  final String server;
  final int port;

  @override
  String toString() => 'ProxyReading($server:$port enabled: $isEnabled)';
}

/// Reduces a `getProxies` answer to [ProxyReading]s, dropping every credential
/// on the way. Null means the read failed, which callers must not mistake for
/// an account without proxies.
List<ProxyReading>? proxyReadingsFrom(Map<String, dynamic>? response) {
  final raw = response?.objects('proxies');
  if (raw == null) return null;
  return [
    for (final entry in raw)
      ProxyReading(
        isEnabled: entry.boolean('is_enabled') ?? false,
        server: entry.obj('proxy')?.str('server') ?? '',
        port: entry.obj('proxy')?.integer('port') ?? 0,
      ),
  ];
}

/// Reads one TDLib answer on behalf of a specific account slot.
typedef ProxyStatusQueryForSlot =
    Future<Map<String, dynamic>> Function(
      Map<String, dynamic> request,
      int accountSlot,
    );

/// Process-wide proxy status, so the sidebar shortcut and the 代理 page agree
/// without either re-reading TDLib for the other.
///
/// Keeps no copy of the proxy list beyond the last reading, and that reading is
/// reduced to [ProxyReading] before it is stored: TDLib owns the list and
/// `ProxyConfig` owns the saved credentials, so this is a meter, not a second
/// store that could outlive the account it describes — and never a place where
/// a SOCKS/HTTP password or an MTProto secret sits in memory for the process
/// lifetime.
class ProxyStatusController extends ChangeNotifier {
  ProxyStatusController._({
    ProxyStatusQueryForSlot? queryForSlot,
    int Function()? activeSlot,
    Stream<int>? activeSlotChanges,
    Stream<Map<String, dynamic>>? connectionUpdates,
    Stream<Map<String, dynamic>>? authorizationUpdates,
  }) : _queryForSlot = queryForSlot ?? TdClient.shared.queryForSlot,
       _activeSlotOf = activeSlot ?? (() => TdClient.shared.activeSlot),
       _activeSlotChanges =
           activeSlotChanges ?? TdClient.shared.subscribeActiveSlotChanges(),
       _connectionUpdates =
           connectionUpdates ??
           TdClient.shared.updatesOf('updateConnectionState'),
       _authorizationUpdates =
           authorizationUpdates ??
           TdClient.shared.updatesOf('updateAuthorizationState');

  /// A controller a test drives itself, so an account switch — including one
  /// that lands while a reading is still in flight — can be set up without the
  /// TDLib singleton, which only ever proxies one slot.
  @visibleForTesting
  factory ProxyStatusController.forTesting({
    required ProxyStatusQueryForSlot queryForSlot,
    required int Function() activeSlot,
    Stream<int> activeSlotChanges = const Stream<int>.empty(),
    Stream<Map<String, dynamic>> connectionUpdates =
        const Stream<Map<String, dynamic>>.empty(),
    Stream<Map<String, dynamic>> authorizationUpdates =
        const Stream<Map<String, dynamic>>.empty(),
  }) => ProxyStatusController._(
    queryForSlot: queryForSlot,
    activeSlot: activeSlot,
    activeSlotChanges: activeSlotChanges,
    connectionUpdates: connectionUpdates,
    authorizationUpdates: authorizationUpdates,
  );

  static final ProxyStatusController shared = ProxyStatusController._();

  final ProxyStatusQueryForSlot _queryForSlot;
  final int Function() _activeSlotOf;
  final Stream<int> _activeSlotChanges;
  final Stream<Map<String, dynamic>> _connectionUpdates;
  final Stream<Map<String, dynamic>> _authorizationUpdates;

  ProxyStatusSnapshot _snapshot = ProxyStatusSnapshot.unknown;
  ProxyStatusSnapshot get snapshot => _snapshot;

  List<ProxyReading> _proxies = const [];
  String? _connectionState;
  int _generation = 0;
  bool _tracking = false;
  bool _disposed = false;
  StreamSubscription<Map<String, dynamic>>? _connectionSub;
  StreamSubscription<Map<String, dynamic>>? _authorizationSub;
  StreamSubscription<int>? _slotSub;

  /// Follows the active account. Idempotent, so every surface showing the
  /// indicator calls it from initState without coordinating.
  void ensureTracking() {
    if (_tracking || _disposed) return;
    _tracking = true;
    _connectionSub = _connectionUpdates.listen(_onConnectionUpdate);
    _authorizationSub = _authorizationUpdates.listen(_onAuthorizationUpdate);
    _slotSub = _activeSlotChanges.listen(_onActiveSlotChanged);
    unawaited(refresh());
  }

  /// Re-reads the proxy list of the account that was active when the call
  /// started. Cheap enough to call whenever a surface becomes visible again.
  Future<void> refresh() async {
    if (_disposed) return;
    final generation = ++_generation;
    final slot = _activeSlotOf();
    final results = await Future.wait([
      _queryOrNull({'@type': 'getProxies'}, slot),
      _queryOrNull({'@type': 'getConnectionState'}, slot),
    ]);
    // A newer refresh or an account switch owns the state now. Painting this
    // answer would show one account's proxy on another account's sidebar.
    if (generation != _generation || _activeSlotOf() != slot) return;
    final readings = proxyReadingsFrom(results[0]);
    final connectionState = results[1]?.type;
    // A failed read keeps the last one: claiming "no proxy" because a query
    // timed out would be a lie the indicator cannot take back.
    if (readings == null && connectionState == null) return;
    if (readings != null) _proxies = readings;
    if (connectionState != null) _connectionState = connectionState;
    _recompute();
  }

  /// Called by every path that adds, edits, enables, disables or removes a
  /// proxy, so the indicator does not wait for the reconnect to catch up.
  void proxiesChanged() {
    if (!_tracking) return;
    unawaited(refresh());
  }

  void _onConnectionUpdate(Map<String, dynamic> update) {
    final state = update.obj('state')?.type;
    if (state == null || state == _connectionState) return;
    _connectionState = state;
    _recompute();
    // The list may have moved too — an enable or a disable is what forced this
    // state change in the first place.
    unawaited(refresh());
  }

  void _onActiveSlotChanged(int _) {
    // Proxies belong to one TDLib client. Never carry the previous account's
    // reading across, not even for the frame before the new list lands.
    _drop();
    unawaited(refresh());
  }

  void _onAuthorizationUpdate(Map<String, dynamic> update) {
    final state = update.obj('authorization_state')?.type;
    if (state == null) return;
    if (state == 'authorizationStateClosed') {
      // This slot's client is gone, and its proxy list goes with it. The next
      // account may reuse the very same slot, so nothing may survive here.
      _drop();
      return;
    }
    // A login in progress replaces the account behind the slot; only the new
    // account's own list says whether it has a proxy.
    unawaited(refresh());
  }

  void _drop() {
    _generation++;
    _proxies = const [];
    _connectionState = null;
    _apply(ProxyStatusSnapshot.unknown);
  }

  Future<Map<String, dynamic>?> _queryOrNull(
    Map<String, dynamic> request,
    int slot,
  ) async {
    try {
      return await _queryForSlot(request, slot);
    } catch (_) {
      // No client for the slot yet (still starting, logged out).
      return null;
    }
  }

  void _recompute() {
    ProxyReading? active;
    for (final proxy in _proxies) {
      if (proxy.isEnabled) {
        // TDLib enables at most one proxy at a time.
        active = proxy;
        break;
      }
    }
    _apply(
      ProxyStatusSnapshot(
        indicator: proxyIndicatorFor(
          configured: _proxies.isNotEmpty,
          enabled: active != null,
          connectionState: _connectionState,
        ),
        server: active?.server ?? '',
        port: active?.port ?? 0,
        savedCount: _proxies.length,
      ),
    );
  }

  void _apply(ProxyStatusSnapshot snapshot) {
    if (_disposed || snapshot == _snapshot) return;
    _snapshot = snapshot;
    notifyListeners();
  }

  /// What the last reading retained, as the cache itself holds it. Test-only:
  /// a credential that survived `getProxies` shows up in this value.
  @visibleForTesting
  Object get debugRetainedProxies => List<Object>.of(_proxies);

  /// Drops the reading. Test-only: the singleton outlives a widget test, and
  /// the next one drives a different transport.
  @visibleForTesting
  void debugReset() => _drop();

  /// The shared instance lives as long as the app, so this only runs for a
  /// controller a test built itself.
  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _tracking = false;
    _proxies = const [];
    _connectionState = null;
    _snapshot = ProxyStatusSnapshot.unknown;
    unawaited(_connectionSub?.cancel());
    unawaited(_authorizationSub?.cancel());
    unawaited(_slotSub?.cancel());
    _connectionSub = null;
    _authorizationSub = null;
    _slotSub = null;
    super.dispose();
  }
}
