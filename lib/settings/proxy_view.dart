//
//  proxy_view.dart
//
//  代理 — connection proxy settings backed by TDLib (getProxies / addProxy /
//  enableProxy / disableProxy / removeProxy / testProxy). A "不使用代理" row plus
//  the list of configured proxies (tap to enable; the active one carries a
//  brand checkmark; every row carries its own availability chip), a 测试全部
//  action that probes each saved proxy, a 删除不可用的代理 action once a probe
//  has failed, and an 添加代理 row that opens a full-page custom editor.
//  SOCKS5 / HTTP / MTProto, plus Shadowsocks / Trojan / VLESS / VMess where
//  the bundled engine runs (AppProxyService). No Material dialogs.
//
//  Reached from the sidebar AND from the login screen's own 代理 shortcut, so
//  the client behind it may still be opening its database (a fresh add-account
//  slot): until the first getProxies answers, the page keeps its waiting state
//  and re-reads on the client's first pushed update instead of rendering an
//  empty list that would read as "nothing saved".
//
//  A saved proxy list lives in the TDLib client — for a slot that has not
//  signed in yet, that client answers getProxies from its own database as soon
//  as setTdlibParameters ran, so the login screen's page reads exactly what the
//  sidebar page reads. Only the 连接状态 half of the chip needs a link; a
//  not-yet-connected client reports no state, which is why the status
//  controller reports an unknown connection state rather than a failure.
//

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_confirm_dialog.dart';
import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/settings_selection_row.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../theme/app_theme.dart';
import 'app_proxy_service.dart';
import 'leaf_proxy_profile.dart';
import 'proxy_config.dart';
import 'proxy_status.dart';

/// The concrete TDLib client a proxy page's rows belong to.
///
/// Proxy ids are account-scoped: id 42 in one account is a different row from
/// id 42 in another. A page that outlives an account switch — the confirmation
/// dialog is the long await — must keep every read and every removal on the
/// account whose rows the user is looking at.
abstract interface class ProxyViewOwner {
  int get clientId;

  /// Query bound to [clientId]. It never resolves the foreground account.
  Future<Map<String, dynamic>> query(Map<String, dynamic> request);

  /// False once the user switched accounts, this slot's client was replaced or
  /// closed, or shutdown started.
  bool get isCurrent;

  /// Applies the locally saved proxy config to this owner's client, never to
  /// whichever account happens to be in the foreground.
  Future<void> applySavedProxy();

  /// Applies [config] to this owner's client, never to the foreground account.
  Future<void> applyProxyConfig(ProxyConfig config);
}

/// Supplies the owner a proxy page runs against.
abstract interface class ProxyViewAccounts {
  static const ProxyViewAccounts defaultAccounts = TdProxyViewAccounts();

  /// The registry the pinned owners come from.
  TdClient get registry;

  /// Null when nothing can be pinned: nothing logged in, shutdown already
  /// running, or a client replaced between the reads.
  ProxyViewOwner? pinActiveOwner();

  /// Foreground account changes, so a page pinned to the old account re-reads
  /// instead of keeping another account's rows on screen.
  Stream<int> get activeSlotChanges;
}

final class _TdProxyViewOwner implements ProxyViewOwner {
  _TdProxyViewOwner(this._client, this._slot, this._clientId);

  final TdClient _client;
  final int _slot;
  final int _clientId;

  @override
  int get clientId => _clientId;

  @override
  Future<Map<String, dynamic>> query(Map<String, dynamic> request) =>
      AppProxyService.shared.viewQuery(
        request: request,
        queryNative: (value) => _client.queryTo(value, _clientId),
        applyConfig: applyProxyConfig,
      );

  @override
  bool get isCurrent =>
      !_client.isShuttingDown &&
      _client.clientId(_slot) == _clientId &&
      _client.activeClientId == _clientId;

  @override
  Future<void> applySavedProxy() => _client.applySavedProxyToClient(_clientId);

  @override
  Future<void> applyProxyConfig(ProxyConfig config) =>
      _client.applyProxyConfigToClient(config, _clientId);
}

/// Production registry: pins the foreground account's concrete client the way
/// the switcher reads each account's identity, without retaining anything.
///
/// Tests pass a private [TdClient.forTesting] registry so the same pinning and
/// query path runs against synthetic bindings.
final class TdProxyViewAccounts implements ProxyViewAccounts {
  const TdProxyViewAccounts([this._client]);

  final TdClient? _client;

  @override
  TdClient get registry => _client ?? TdClient.shared;

  @override
  ProxyViewOwner? pinActiveOwner() {
    final client = registry;
    if (client.isShuttingDown) return null;
    final slot = client.activeSlot;
    final clientId = client.activeClientId;
    if (clientId == 0) return null;
    // A session swap or a QR reset can replace the slot's client between those
    // two reads; pinning that would page an account nobody looked at.
    if (client.clientId(slot) != clientId) return null;
    return _TdProxyViewOwner(client, slot, clientId);
  }

  @override
  Stream<int> get activeSlotChanges => registry.subscribeActiveSlotChanges();
}

class ProxyView extends StatefulWidget {
  const ProxyView({
    super.key,
    this.accounts = ProxyViewAccounts.defaultAccounts,
  });

  final ProxyViewAccounts accounts;

  @override
  State<ProxyView> createState() => _ProxyViewState();
}

class _ProxyViewState extends State<ProxyView> {
  StreamSubscription<Map<String, dynamic>>? _clientWakeSub;
  StreamSubscription<int>? _slotSub;
  List<Map<String, dynamic>> _proxies = [];
  bool _loading = true;

  /// False until a getProxies read actually answered. The list lives inside
  /// the TDLib client, and a client still opening its database — the fresh
  /// slot behind the login screen's add-account flow — cannot answer yet:
  /// TDLib 1.8.67 queues a pre-parameters read with no reply at all, so
  /// "no answer" must never render as "no proxy".
  bool _clientReady = false;
  int _loadGeneration = 0;

  /// The account whose rows are on screen. Every read and every mutation for
  /// this page runs against it, never against whichever account is foreground
  /// when the request finally leaves.
  ProxyViewOwner? _owner;

  /// Bumped whenever the page stops owning the rows it pinned, so answers and
  /// confirmation batches started under a previous owner are discarded even if
  /// the same account later returns to the foreground.
  int _ownerGeneration = 0;

  /// The last probe verdict per proxy id, keyed by the TDLib proxy id. Only a
  /// probe or a live link state ever writes here; removing a proxy drops its
  /// entry with it. Cleared when the page adopts another account, because ids
  /// are only unique inside one account.
  final Map<int, ProxyCheckResult> _checks = {};

  /// One counter per proxy id, bumped every time a fresh probe starts, so an
  /// answer that belongs to a probe the user has since re-run is discarded.
  final Map<int, int> _checkGeneration = {};

  /// The reduced verdict of the testProxy currently in flight per (client,
  /// proxy id). Two taps, or a tap racing 测试全部, share this one request
  /// instead of issuing a second testProxy for the same proxy; the client id
  /// keeps another account's id 42 from joining this account's probe.
  final Map<(int, int), Future<ProxyCheckResult>> _pendingChecks = {};

  /// What the probe itself is told to wait, and how long the page waits past
  /// that before it gives up on a client that stopped answering.
  static const Duration _probeTimeout = Duration(seconds: 5);
  static const Duration _probeAnswerGrace = Duration(seconds: 2);

  int _nextCheckGeneration(int id) =>
      _checkGeneration[id] = (_checkGeneration[id] ?? 0) + 1;

  /// Whether [owner] still owns this page and the answer captured under
  /// [ownerGeneration] still describes what the user is looking at.
  bool _isOwnerCurrent(ProxyViewOwner owner, int ownerGeneration) =>
      mounted && ownerGeneration == _ownerGeneration && owner.isCurrent;

  @override
  void initState() {
    super.initState();
    // The chips read the shared status for an enabled proxy that has not been
    // probed yet, so this surface keeps that meter tracking too — the same
    // call the sidebar shortcut makes, and idempotent.
    ProxyStatusController.shared.ensureTracking();
    _load();
    _listenForClientWake();
    _slotSub = widget.accounts.activeSlotChanges.listen(
      (_) => _onForegroundChanged(),
    );
  }

  @override
  void dispose() {
    unawaited(_clientWakeSub?.cancel());
    unawaited(_slotSub?.cancel());
    super.dispose();
  }

  /// The foreground account changed. Drop the old owner's verdicts and any
  /// confirmation batch that was captured against it before re-reading the
  /// account now on screen.
  void _onForegroundChanged() {
    if (!mounted) return;
    setState(() {
      _owner = null;
      _ownerGeneration++;
      _checks.clear();
      _checkGeneration.clear();
      _pendingChecks.clear();
    });
    unawaited(_load());
  }

  /// Re-reads on the first pushed authorization/connection state while the
  /// page is still waiting on its read. The parameters bootstrap runs before
  /// these updates fan out, so the re-read lands past TDLib's queue and gets
  /// answered once the database is open. Event-driven: nothing polls.
  void _listenForClientWake() {
    _clientWakeSub = widget.accounts.registry
        .updatesOfAny(const [
          'updateAuthorizationState',
          'updateConnectionState',
        ])
        .listen((_) => unawaited(_load()));
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final owner = widget.accounts.pinActiveOwner();
    if (owner == null) {
      // No client to pin yet (the login screen before parameters). Keep the
      // waiting state; the wake listener re-reads when the client reports in.
      if (mounted && _clientReady) setState(() => _loading = false);
      return;
    }
    // Every mutation on this page lands here, and the sidebar shortcut reads
    // the same list: tell it the ground moved instead of leaving it to notice
    // on the next reconnect.
    ProxyStatusController.shared.proxiesChanged();
    try {
      final res = await owner.query({'@type': 'getProxies'});
      // A read answered for an account the page no longer owns — or one a
      // newer read has superseded — must not paint over the foreground list.
      if (!mounted || generation != _loadGeneration || !owner.isCurrent) {
        return;
      }
      final list = res.objects('proxies') ?? const <Map<String, dynamic>>[];
      final liveIds = {for (final proxy in list) proxy.integer('id') ?? 0};
      setState(() {
        if (_owner?.clientId != owner.clientId) {
          // Proxy ids are account-scoped, so a verdict from the previous
          // account must never label this account's identically numbered row.
          _owner = owner;
          _ownerGeneration++;
          _checks.clear();
          _checkGeneration.clear();
          _pendingChecks.clear();
        } else {
          _owner = owner;
        }
        _proxies = list;
        _clientReady = true;
        _loading = false;
        // A proxy that is gone must not leave a verdict behind for an id
        // TDLib may hand to a different proxy later.
        _checks.removeWhere((id, _) => !liveIds.contains(id));
        _checkGeneration.removeWhere((id, _) => !liveIds.contains(id));
      });
      // The client answers: nothing can still be pending behind the wake
      // listener, so it stops loading the page on every pushed state.
      await _clientWakeSub?.cancel();
      _clientWakeSub = null;
    } catch (_) {
      // A client that has not answered yet must keep its waiting state: the
      // wake listener re-reads the moment the client reports in, and showing
      // "no proxies" here would be a lie about a list nobody has read.
      if (mounted && _clientReady) setState(() => _loading = false);
    }
  }

  bool get _anyEnabled => _proxies.any((p) => p.boolean('is_enabled') ?? false);

  /// Only a probe's own verdict counts as unavailable here. A live link that
  /// merely cannot be reached right now is not evidence a proxy is dead, and
  /// this is what gates the destructive bulk delete.
  bool _probeFailed(Map<String, dynamic> proxy) =>
      _checks[proxy.integer('id') ?? 0]?.status == ProxyCheckStatus.unavailable;

  int get _unavailableCount => _proxies.where(_probeFailed).length;

  int get _probingCount => _checks.values
      .where((check) => check.status == ProxyCheckStatus.testing)
      .length;

  Future<void> _enable(Map<String, dynamic> proxy) async {
    final owner = _owner;
    if (owner == null || !owner.isCurrent) return;
    final ownerGeneration = _ownerGeneration;
    final id = proxy.integer('id') ?? 0;
    try {
      await owner.query({'@type': 'enableProxy', 'proxy_id': id});
      if (_isOwnerCurrent(owner, ownerGeneration)) {
        await ProxyConfig.save(ProxyConfig.fromTdProxy(proxy));
        await owner.applySavedProxy();
      }
    } catch (_) {}
    unawaited(_load());
  }

  Future<void> _disable() async {
    final owner = _owner;
    if (owner == null || !owner.isCurrent) return;
    final ownerGeneration = _ownerGeneration;
    try {
      await owner.query({'@type': 'disableProxy'});
    } catch (_) {}
    if (_isOwnerCurrent(owner, ownerGeneration)) {
      try {
        await ProxyConfig.disable();
      } catch (_) {}
      try {
        await owner.applySavedProxy();
      } catch (_) {}
    }
    unawaited(_load());
  }

  Future<void> _remove(int id) async {
    final owner = _owner;
    if (owner == null || !owner.isCurrent) return;
    final ownerGeneration = _ownerGeneration;
    final removed = _proxies.firstWhere(
      (proxy) => proxy.integer('id') == id,
      orElse: () => const <String, dynamic>{},
    );
    final wasEnabled = removed.boolean('is_enabled') ?? false;
    final ok = await showAppConfirmDialog(
      context,
      title: AppStringKeys.proxyDeleteProxy,
      confirmText: AppStringKeys.chatDelete,
      destructive: true,
    );
    // The dialog is the long await: an account switch while it was open means
    // the row the user confirmed belongs to an account this page no longer
    // owns, so the removal is dropped rather than applied to its replacement.
    if (!ok || !_isOwnerCurrent(owner, ownerGeneration)) return;
    setState(() => _checks.remove(id));
    var removedNow = false;
    try {
      await owner.query({'@type': 'removeProxy', 'proxy_id': id});
      removedNow = true;
    } catch (_) {}
    if (removedNow && wasEnabled && _isOwnerCurrent(owner, ownerGeneration)) {
      try {
        await ProxyConfig.disable();
      } catch (_) {}
      if (_isOwnerCurrent(owner, ownerGeneration)) {
        try {
          await owner.applySavedProxy();
        } catch (_) {}
      }
    }
    unawaited(_load());
  }

  /// Removes every proxy whose last probe failed. The button only exists while
  /// at least one row reads as unavailable, so this never runs empty.
  Future<void> _removeUnavailable() async {
    final owner = _owner;
    if (owner == null || !owner.isCurrent) return;
    final ownerGeneration = _ownerGeneration;
    final doomed = [
      for (final proxy in _proxies)
        if (_probeFailed(proxy)) proxy,
    ];
    if (doomed.isEmpty) return;
    // Capture the exact batch the user is confirming. Proxy ids are only
    // meaningful inside [owner], so the batch stays pinned to that account
    // through the dialog and through every removal in the loop.
    final doomedIds = {for (final proxy in doomed) proxy.integer('id') ?? 0};
    final enabledIds = {
      for (final proxy in doomed)
        if (proxy.boolean('is_enabled') ?? false) proxy.integer('id') ?? 0,
    };
    final ok = await showAppConfirmDialog(
      context,
      title: AppStringKeys.proxyDeleteUnavailable,
      message: AppStringKeys.proxyDeleteUnavailableMessage,
      confirmText: AppStringKeys.chatDelete,
      destructive: true,
    );
    // A switch while the dialog was open drops the whole batch: ids from the
    // old account name unrelated rows in the new one.
    if (!ok || !_isOwnerCurrent(owner, ownerGeneration)) return;
    setState(() {
      for (final id in doomedIds) {
        _checks.remove(id);
      }
    });
    var removedEnabled = false;
    for (final id in doomedIds) {
      // Another account taking the foreground abandons whatever is left of
      // this batch instead of aiming it at the new account's rows.
      if (!_isOwnerCurrent(owner, ownerGeneration)) break;
      try {
        await owner.query({'@type': 'removeProxy', 'proxy_id': id});
        if (enabledIds.contains(id)) removedEnabled = true;
      } catch (_) {
        // One failed removal must not abandon the rest of the batch.
      }
    }
    // The saved config and its re-apply belong to the account whose enabled
    // row was actually removed, never to the account now in the foreground.
    if (removedEnabled && _isOwnerCurrent(owner, ownerGeneration)) {
      try {
        await ProxyConfig.disable();
      } catch (_) {}
      if (_isOwnerCurrent(owner, ownerGeneration)) {
        try {
          await owner.applySavedProxy();
        } catch (_) {}
      }
    }
    unawaited(_load());
  }

  /// Probes one saved proxy. The answer to `testProxy` is the probe's own
  /// verdict — TDLib completes it only after the socks/HTTP/MTProto handshake
  /// with the datacenter behind the proxy finished, or the request's own
  /// timeout expired — so the elapsed round trip is the latency reported.
  Future<void> _testProxy(Map<String, dynamic> proxy) async {
    final owner = _owner;
    if (owner == null || !owner.isCurrent) return;
    final ownerGeneration = _ownerGeneration;
    final id = proxy.integer('id') ?? 0;
    // A row that is already being probed keeps the attempt it started with:
    // one testProxy per proxy id, however often the row is tapped.
    final inFlight = _checks[id]?.status == ProxyCheckStatus.testing;
    if (!inFlight) {
      final generation = _nextCheckGeneration(id);
      setState(
        () => _checks[id] = const ProxyCheckResult(ProxyCheckStatus.testing),
      );
      final outcome = await _probe(proxy, owner);
      if (!_isCurrentCheck(id, generation, owner, ownerGeneration)) return;
      setState(() => _checks[id] = outcome);
      return;
    }
    // A test-all pressed while a row's own tap is still waiting joins it
    // rather than issuing a second testProxy for the same proxy.
    final pending = _pendingChecks[(owner.clientId, id)];
    if (pending == null) return;
    final outcome = await pending;
    if (!_isCurrentCheck(id, null, owner, ownerGeneration) ||
        _checks[id]?.status != ProxyCheckStatus.testing) {
      return;
    }
    setState(() => _checks[id] = outcome);
  }

  /// One `testProxy` round trip, reduced to a verdict. The request carries the
  /// saved proxy's own type (SOCKS5 / HTTP credentials, MTProto secret) and the
  /// probe's own timeout; TDLib answers `ok` once the handshake with the
  /// datacenter behind the proxy finished, or a 400 whose message names the
  /// failure ('Timeout expired', 'Connection refused', ...).
  Future<ProxyCheckResult> _probe(
    Map<String, dynamic> proxy,
    ProxyViewOwner owner,
  ) {
    final id = proxy.integer('id') ?? 0;
    final proxyDetails = ProxyConfig.tdProxyDetails(proxy);
    final stopwatch = Stopwatch()..start();
    final reduced = owner
        .query({
          '@type': 'testProxy',
          'proxy': proxyDetails,
          'dc_id': kProxyTestDcId,
          'timeout': _probeTimeout.inSeconds.toDouble(),
        })
        // The answer normally arrives on its own: the request is asynchronous
        // and this only bounds a client that stops reading altogether.
        .timeout(_probeTimeout + _probeAnswerGrace)
        .then<ProxyCheckResult>(
          (_) => ProxyCheckResult(
            ProxyCheckStatus.available,
            latency: stopwatch.elapsed,
          ),
          onError: (Object error) => ProxyCheckResult(
            ProxyCheckStatus.unavailable,
            error: _probeErrorMessage(error),
          ),
        );
    final key = (owner.clientId, id);
    _pendingChecks[key] = reduced;
    return reduced.whenComplete(() => _pendingChecks.remove(key));
  }

  /// The message TDLib gave for a failed probe, so the chip says why. A 400 is
  /// TDLib's own failure; anything else is the client losing the request.
  static String _probeErrorMessage(Object error) {
    if (error is TdError) {
      final message = error.message.trim();
      if (message.isNotEmpty) return message;
    }
    if (error is TimeoutException) {
      return AppStrings.t(AppStringKeys.proxyCheckTimeout);
    }
    return AppStrings.t(AppStringKeys.proxyCheckFailed);
  }

  /// Probes every saved proxy; each row keeps its own request and its own
  /// verdict, and the page stays interactive while they land.
  void _testAll() {
    for (final proxy in List<Map<String, dynamic>>.of(_proxies)) {
      unawaited(_testProxy(proxy));
    }
  }

  /// Whether an answer still describes the row it was asked for: the same id,
  /// the same probe attempt (when one is given), and the same still-owned
  /// client. A reconnect or account switch mid-probe must not paint its answer.
  bool _isCurrentCheck(
    int id,
    int? generation,
    ProxyViewOwner owner,
    int ownerGeneration,
  ) =>
      _isOwnerCurrent(owner, ownerGeneration) &&
      (generation == null || generation == _checkGeneration[id]) &&
      _proxies.any((proxy) => proxy.integer('id') == id);

  ProxyCheckResult _stateFor(Map<String, dynamic> proxy) {
    final id = proxy.integer('id') ?? 0;
    final check = _checks[id];
    if (check != null) return check;
    // TDLib routes at most one proxy at a time. An enabled proxy starts out
    // showing what the live link says — the pushed connection state is the
    // only place TDLib reports traffic really flowing through it — and probing
    // it replaces that with the measured verdict.
    //
    // A client with no link at all (the login screen's not-yet-signed-in slot)
    // reads as unknown, never as a failure: no state was read, so nothing is
    // claimed about the proxy.
    if (proxy.boolean('is_enabled') ?? false) {
      return switch (ProxyStatusController.shared.snapshot.indicator) {
        ProxyIndicator.connected => const ProxyCheckResult(
          ProxyCheckStatus.available,
        ),
        ProxyIndicator.unreachable => const ProxyCheckResult(
          ProxyCheckStatus.unavailable,
        ),
        ProxyIndicator.connecting => const ProxyCheckResult(
          ProxyCheckStatus.testing,
        ),
        _ => const ProxyCheckResult(ProxyCheckStatus.unknown),
      };
    }
    return const ProxyCheckResult(ProxyCheckStatus.unknown);
  }

  Future<void> _add() async {
    // While the client is still opening (login flow), the editor must save
    // offline first — a live addProxy would sit in the same pre-parameters
    // queue as the page's own initial read. The saved config is applied to
    // the client as soon as its parameters land.
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProxyEditView(allowOfflineSave: !_clientReady),
      ),
    );
    if (added == true) unawaited(_load());
  }

  static String _typeLabel(Map<String, dynamic> proxy) {
    final details = ProxyConfig.tdProxyDetails(proxy);
    final type = details.obj('type');
    return switch (type?.type) {
      'proxyTypeSocks5' => 'SOCKS5',
      'proxyTypeHttp' => 'HTTP',
      'proxyTypeMtproto' => 'MTProto',
      'mithkaLeafProxy' =>
        type?.str('label') ?? AppStrings.t(AppStringKeys.proxyTitle),
      _ => AppStrings.t(AppStringKeys.proxyTitle),
    };
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: AppStrings.t(AppStringKeys.proxyTitle),
      onBack: () => Navigator.of(context).pop(),
      trailing: _proxies.isEmpty
          ? null
          : SettingsHeaderAction(
              key: const ValueKey('proxy-test-all'),
              label: AppStringKeys.proxyTestAll,
              // The label becomes the spinner while any probe is in flight, so
              // a second 测试全部 cannot stack on the first.
              working: _probingCount > 0,
              onTap: _testAll,
            ),
      child: _loading
          ? const Center(child: AppActivityIndicator(size: 24))
          : SettingsListView(
              children: [
                _card([_noneRow()], key: const ValueKey('proxy-disabled-card')),
                const SizedBox(height: AppSpacing.lg),
                if (_proxies.isNotEmpty) ...[
                  _card([
                    for (final proxy in _proxies) _proxyRow(proxy),
                  ], key: const ValueKey('proxy-configured-card')),
                  const SizedBox(height: AppSpacing.lg),
                ],
                _card([
                  if (_unavailableCount > 0) _removeUnavailableRow(),
                  _addRow(),
                  _addFromLinkRow(),
                ], key: const ValueKey('proxy-actions-card')),
                SettingsNote(
                  text: AppStrings.t(AppStringKeys.proxyDescription),
                ),
              ],
            ),
    );
  }

  Widget _card(List<Widget> children, {Key? key}) {
    return SettingsCard.rows(
      key: key,
      rows: children,
      dividerInset: AppMetric.settingsTextDividerInset,
    );
  }

  Widget _noneRow() {
    return SettingsRow(
      title: AppStrings.t(AppStringKeys.proxyDisabled),
      showChevron: false,
      trailing: !_anyEnabled
          ? AppIcon(HeroAppIcons.check, size: 18, color: AppTheme.brand)
          : null,
      onTap: _anyEnabled ? _disable : null,
    );
  }

  /// The row's second line: its type, plus the failure behind an unavailable
  /// verdict so the chip can stay short without hiding the reason.
  String _rowSubtitle(Map<String, dynamic> proxy, ProxyCheckResult check) {
    final type = _typeLabel(proxy);
    final error = check.error;
    if (check.status != ProxyCheckStatus.unavailable || error == null) {
      return type;
    }
    return '$type · $error';
  }

  Widget _proxyRow(Map<String, dynamic> proxy) {
    final details = ProxyConfig.tdProxyDetails(proxy);
    final id = proxy.integer('id') ?? 0;
    final enabled = proxy.boolean('is_enabled') ?? false;
    final server = details.str('server') ?? '';
    final port = details.integer('port') ?? 0;
    final check = _stateFor(proxy);
    return SettingsRow(
      title: '$server:$port',
      subtitle: _rowSubtitle(proxy, check),
      showChevron: false,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (enabled) ...[
            AppIcon(HeroAppIcons.check, size: 18, color: AppTheme.brand),
            const SizedBox(width: AppSpacing.lg),
          ],
          _ProxyCheckChip(result: check),
          const SizedBox(width: AppSpacing.lg),
          AppInteractiveSurface(
            key: ValueKey('proxy-remove-$id'),
            semanticLabel: AppStringKeys.chatInfoRemove.l10n(context),
            onTap: () => _remove(id),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: AppIcon(
                HeroAppIcons.circleMinus,
                size: AppIconSize.xl,
                color: AppTheme.tagRed.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
      onTap: enabled ? null : () => _enable(proxy),
    );
  }

  /// Destructive bulk action, present only while a probe verdict marks at
  /// least one row unavailable — so it can never be pressed with nothing to do.
  Widget _removeUnavailableRow() {
    return SettingsRow(
      key: const ValueKey('proxy-delete-unavailable'),
      title: AppStrings.t(AppStringKeys.proxyDeleteUnavailable),
      leading: SettingsLeadingIcon(
        icon: HeroAppIcons.trash,
        color: AppTheme.tagRed,
      ),
      titleColor: AppTheme.tagRed,
      showChevron: false,
      onTap: _removeUnavailable,
    );
  }

  Widget _addRow() {
    return SettingsRow(
      title: AppStrings.t(AppStringKeys.proxyAddProxy),
      leading: const SettingsLeadingIcon(icon: HeroAppIcons.plus),
      titleColor: AppTheme.brand,
      showChevron: false,
      onTap: _add,
    );
  }

  Future<void> _addFromLink() async {
    final owner = _owner;
    if (owner == null || !owner.isCurrent) return;
    final ownerGeneration = _ownerGeneration;
    final ctrl = TextEditingController();
    final result = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return CupertinoAlertDialog(
              title: Text(AppStrings.t(AppStringKeys.proxyAddFromLinkTitle)),
              content: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: CupertinoTextField(
                  controller: ctrl,
                  autofocus: true,
                  placeholder: AppStrings.t(AppStringKeys.proxyAddFromLinkHint),
                  onChanged: (_) => setDialogState(() {}),
                  clearButtonMode: OverlayVisibilityMode.editing,
                ),
              ),
              actions: [
                CupertinoDialogAction(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(AppStrings.t(AppStringKeys.countryPickerCancel)),
                ),
                CupertinoDialogAction(
                  isDefaultAction: true,
                  onPressed: ctrl.text.trim().isNotEmpty
                      ? () => Navigator.of(ctx).pop(ctrl.text.trim())
                      : null,
                  child: Text(AppStrings.t(AppStringKeys.proxyAddProxy)),
                ),
              ],
            );
          },
        );
      },
    );
    ctrl.dispose();
    if (result == null || result.isEmpty) return;
    if (!_isOwnerCurrent(owner, ownerGeneration)) return;

    final parsed = ProxyConfig.fromTelegramUrl(result);
    if (parsed == null) {
      if (mounted) {
        showToast(context, AppStrings.t(AppStringKeys.proxyAddFailed));
      }
      return;
    }

    try {
      final config = await ProxyConfig.withSavedIdentity(parsed);
      if (!_isOwnerCurrent(owner, ownerGeneration)) return;
      await owner.applyProxyConfig(config);
      await ProxyConfig.save(config);
      unawaited(_load());
    } catch (_) {
      if (mounted) {
        showToast(context, AppStrings.t(AppStringKeys.proxyAddFailed));
      }
    }
  }

  Widget _addFromLinkRow() {
    return SettingsRow(
      title: AppStrings.t(AppStringKeys.proxyAddFromLink),
      leading: const SettingsLeadingIcon(icon: HeroAppIcons.link),
      titleColor: AppTheme.brand,
      showChevron: false,
      onTap: _addFromLink,
    );
  }
}

/// One proxy row's availability pill: a colored dot or spinner plus the
/// verdict, painting the values [ProxyCheckStatus] describes. Every state has
/// its own key so a test can pin which one a row renders.
class _ProxyCheckChip extends StatelessWidget {
  const _ProxyCheckChip({required this.result});

  final ProxyCheckResult result;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (Color color, Widget marker, String label) = switch (result.status) {
      ProxyCheckStatus.unknown => (
        c.textTertiary,
        AppIcon(
          HeroAppIcons.circleInfo,
          size: AppIconSize.sm,
          color: c.textTertiary,
        ),
        AppStrings.t(AppStringKeys.proxyCheckUnknown),
      ),
      ProxyCheckStatus.testing => (
        AppTheme.brand,
        AppActivityIndicator(size: 12, color: AppTheme.brand),
        AppStrings.t(AppStringKeys.proxyCheckTesting),
      ),
      ProxyCheckStatus.available => (
        AppTheme.onlineDot,
        AppIcon(
          HeroAppIcons.check,
          size: AppIconSize.sm,
          color: AppTheme.onlineDot,
        ),
        result.latency == null
            ? AppStrings.t(AppStringKeys.proxyCheckAvailable)
            : AppStrings.t(AppStringKeys.proxyCheckLatency, {
                'value1': result.latency!.inMilliseconds,
              }),
      ),
      ProxyCheckStatus.unavailable => (
        AppTheme.tagRed,
        AppIcon(
          HeroAppIcons.triangleExclamation,
          size: AppIconSize.sm,
          color: AppTheme.tagRed,
        ),
        AppStrings.t(AppStringKeys.proxyCheckUnavailable),
      ),
    };
    return Container(
      key: ValueKey('proxy-check-${result.status.name}'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          marker,
          const SizedBox(width: AppSpacing.xs + 1),
          Text(
            label,
            style: AppTextStyle.caption(color, weight: AppTextWeight.medium),
          ),
        ],
      ),
    );
  }
}

/// Full-page custom add-proxy editor — type segments + borderless fields.
class ProxyEditView extends StatefulWidget {
  const ProxyEditView({super.key, this.allowOfflineSave = false});

  final bool allowOfflineSave;

  @override
  State<ProxyEditView> createState() => _ProxyEditViewState();
}

class _ProxyEditViewState extends State<ProxyEditView> {
  /// socks5 | http | mtproto, or one of [LeafProxyProfile.protocols].
  String _type = 'socks5';
  final _server = TextEditingController();
  final _port = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _secret = TextEditingController();
  final _name = TextEditingController();
  final _uuid = TextEditingController();
  final _serverName = TextEditingController();
  final _webSocketPath = TextEditingController(text: '/');
  final _webSocketHost = TextEditingController();
  String _cipher = LeafProxyProfile.ciphers.first;
  String _security = LeafProxyProfile.vmessSecurities.first;
  bool _tls = false;
  bool _webSocket = false;
  bool _vision = false;
  final int _profileId = LeafProxyProfile.newId();
  bool _saving = false;

  List<TextEditingController> get _controllers => [
    _server,
    _port,
    _username,
    _password,
    _secret,
    _name,
    _uuid,
    _serverName,
    _webSocketPath,
    _webSocketHost,
  ];

  @override
  void initState() {
    super.initState();
    for (final ctl in _controllers) {
      ctl.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final ctl in _controllers) {
      ctl.dispose();
    }
    super.dispose();
  }

  bool get _encrypted => LeafProxyProfile.protocols.contains(_type);

  /// Trojan always runs over TLS; Shadowsocks never does.
  bool get _tlsOn => _type == 'trojan' || (_type != 'ss' && _tls);
  bool get _webSocketOn => _type != 'ss' && _webSocket;
  bool get _visionAvailable => _type == 'vless' && _tlsOn && !_webSocketOn;

  LeafProxyProfile get _profile => LeafProxyProfile(
    id: _profileId,
    protocol: _type,
    server: _server.text.trim(),
    port: int.tryParse(_port.text.trim()) ?? 0,
    name: _name.text.trim(),
    password: _type == 'ss' || _type == 'trojan' ? _password.text.trim() : '',
    uuid: _type == 'vless' || _type == 'vmess' ? _uuid.text.trim() : '',
    cipher: _cipher,
    security: _security,
    tls: _tlsOn,
    serverName: _tlsOn ? _serverName.text.trim() : '',
    webSocket: _webSocketOn,
    webSocketPath: _webSocketPath.text.trim().isEmpty
        ? '/'
        : _webSocketPath.text.trim(),
    webSocketHost: _webSocketOn ? _webSocketHost.text.trim() : '',
    vision: _visionAvailable && _vision,
  );

  bool get _valid {
    if (_encrypted) {
      try {
        _profile.validate();
        return true;
      } on FormatException {
        return false;
      }
    }
    final server = _server.text.trim();
    final port = int.tryParse(_port.text.trim()) ?? 0;
    if (server.isEmpty || port <= 0) return false;
    if (_type == 'mtproto') return _secret.text.trim().isNotEmpty;
    return true;
  }

  ProxyConfig get _config => _encrypted
      ? ProxyConfig.encrypted(_profile)
      : ProxyConfig(
          configured: true,
          enabled: true,
          type: _type,
          server: _server.text.trim(),
          port: int.parse(_port.text.trim()),
          username: _username.text.trim(),
          password: _password.text.trim(),
          secret: _secret.text.trim(),
        );

  Future<void> _save() async {
    if (!_valid || _saving) return;
    setState(() => _saving = true);
    try {
      // Saving the same encrypted proxy twice selects the saved one.
      final config = await ProxyConfig.withSavedIdentity(_config);
      if (widget.allowOfflineSave) {
        // The login page can advance to code/password entry immediately. Wait
        // for the proxy to reach the active TDLib client before leaving it.
        await ProxyConfig.save(config);
        await TdClient.shared.applySavedProxyToActive();
      } else {
        await TdClient.shared.applyProxyConfig(config);
        await ProxyConfig.save(config);
      }
      // Opened straight from a settings link this page has no ProxyView above
      // it to report the change, so the sidebar shortcut hears it here.
      ProxyStatusController.shared.proxiesChanged();
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      debugPrint('🌐 [Mithka] add proxy failed: $error');
      if (mounted) {
        setState(() => _saving = false);
        showToast(context, AppStrings.t(AppStringKeys.proxyAddFailed));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mtproto = _type == 'mtproto';
    return SettingsPageScaffold(
      title: AppStrings.t(AppStringKeys.proxyAddProxy),
      onBack: () => Navigator.of(context).pop(),
      trailing: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _save,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: _saving
              ? SizedBox.square(
                  dimension: 20,
                  child: AppActivityIndicator(size: 18, color: AppTheme.brand),
                )
              : Text(
                  AppStrings.t(AppStringKeys.accentColorPickerSave),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _valid
                        ? AppTheme.brand
                        : AppTheme.brand.withValues(alpha: 0.4),
                  ),
                ),
        ),
      ),
      child: SettingsListView(
        children: [
          _typeSelector(),
          const SizedBox(height: AppSpacing.xl),
          _card([
            if (_encrypted)
              _field(
                _name,
                AppStrings.t(AppStringKeys.proxyName),
                AppStrings.t(AppStringKeys.proxyOptional),
              ),
            _field(
              _server,
              AppStrings.t(AppStringKeys.proxyServer),
              AppStrings.t(AppStringKeys.proxyHostOrIp),
            ),
            _field(
              _port,
              AppStrings.t(AppStringKeys.proxyPort),
              '0-65535',
              number: true,
            ),
          ]),
          const SizedBox(height: AppSpacing.xl),
          if (_encrypted)
            ..._encryptedSections()
          else if (mtproto)
            _card([
              _field(
                _secret,
                AppStrings.t(AppStringKeys.proxySecret),
                'secret',
              ),
            ])
          else
            _card([
              _field(
                _username,
                AppStrings.t(AppStringKeys.editProfileUsername),
                AppStrings.t(AppStringKeys.proxyOptional),
              ),
              _field(
                _password,
                AppStrings.t(AppStringKeys.proxyPassword),
                AppStrings.t(AppStringKeys.proxyOptional),
                secure: true,
              ),
            ]),
        ],
      ),
    );
  }

  /// Credentials, then TLS, then the WebSocket transport, in the order the
  /// connection is layered. Each control exists only where its protocol
  /// supports it, so an impossible combination cannot be entered.
  List<Widget> _encryptedSections() {
    final usesPassword = _type == 'ss' || _type == 'trojan';
    return [
      _card([
        if (usesPassword)
          _field(
            _password,
            AppStrings.t(AppStringKeys.proxyPassword),
            AppStrings.t(AppStringKeys.proxyRequired),
            secure: true,
          )
        else
          _field(
            _uuid,
            AppStrings.t(AppStringKeys.proxyUuid),
            AppStrings.t(AppStringKeys.proxyRequired),
          ),
        if (_type == 'ss')
          _choiceRow(
            key: 'proxy-cipher',
            title: AppStrings.t(AppStringKeys.proxyCipher),
            values: LeafProxyProfile.ciphers,
            selected: _cipher,
            onSelected: (value) => setState(() => _cipher = value),
          ),
        if (_type == 'vmess')
          _choiceRow(
            key: 'proxy-security',
            title: AppStrings.t(AppStringKeys.proxySecurity),
            values: LeafProxyProfile.vmessSecurities,
            selected: _security,
            onSelected: (value) => setState(() => _security = value),
          ),
      ]),
      if (_type != 'ss') ...[
        const SizedBox(height: AppSpacing.xl),
        _card([
          if (_type != 'trojan')
            SettingsSwitchRow(
              key: const ValueKey('proxy-tls'),
              title: AppStrings.t(AppStringKeys.proxyTls),
              value: _tls,
              onChanged: (value) => setState(() => _tls = value),
            ),
          if (_tlsOn)
            _field(
              _serverName,
              AppStrings.t(AppStringKeys.proxyServerName),
              AppStrings.t(AppStringKeys.proxyOptional),
            ),
          if (_visionAvailable)
            SettingsSwitchRow(
              key: const ValueKey('proxy-vision'),
              title: AppStrings.t(AppStringKeys.proxyVision),
              value: _vision,
              onChanged: (value) => setState(() => _vision = value),
            ),
        ]),
        const SizedBox(height: AppSpacing.xl),
        _card([
          SettingsSwitchRow(
            key: const ValueKey('proxy-websocket'),
            title: AppStrings.t(AppStringKeys.proxyWebSocket),
            value: _webSocket,
            onChanged: (value) => setState(() => _webSocket = value),
          ),
          if (_webSocketOn) ...[
            _field(
              _webSocketPath,
              AppStrings.t(AppStringKeys.proxyWebSocketPath),
              '/',
            ),
            _field(
              _webSocketHost,
              AppStrings.t(AppStringKeys.proxyWebSocketHost),
              AppStrings.t(AppStringKeys.proxyOptional),
            ),
          ],
        ]),
      ],
      SettingsNote(text: AppStrings.t(AppStringKeys.proxyEncryptedNote)),
    ];
  }

  Widget _choiceRow({
    required String key,
    required String title,
    required List<String> values,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    return SettingsSelectionRow<String>(
      key: ValueKey('$key-selector'),
      title: title,
      value: selected,
      menuTitle: title,
      menuKey: ValueKey('$key-menu'),
      options: [
        for (final value in values)
          SettingsSelectionOption<String>(
            id: '$key-$value',
            value: value,
            label: value,
          ),
      ],
      isSelected: (value) => value == selected,
      onSelected: onSelected,
    );
  }

  Widget _typeSelector() {
    final types = [
      ('socks5', 'SOCKS5'),
      ('http', 'HTTP'),
      ('mtproto', 'MTProto'),
      // Only where the bundled engine runs; elsewhere the editor offers
      // exactly what TDLib supports itself.
      if (ProxyConfig.encryptedProxiesSupported) ...[
        ('ss', 'Shadowsocks'),
        ('trojan', 'Trojan'),
        ('vless', 'VLESS'),
        ('vmess', 'VMess'),
      ],
    ];
    final selectedLabel = types.firstWhere((entry) => entry.$1 == _type).$2;
    return SettingsCard.rows(
      key: const ValueKey('proxy-type-card'),
      rows: [
        SettingsSelectionRow<String>(
          key: const ValueKey('proxy-type-selector'),
          title: AppStrings.t(AppStringKeys.proxyTitle),
          value: selectedLabel,
          menuTitle: AppStrings.t(AppStringKeys.proxyTitle),
          menuKey: const ValueKey('proxy-type-menu'),
          options: [
            for (final type in types)
              SettingsSelectionOption<String>(
                id: 'proxy-type-${type.$1}',
                value: type.$1,
                label: type.$2,
              ),
          ],
          isSelected: (value) => value == _type,
          onSelected: (value) => setState(() => _type = value),
        ),
      ],
    );
  }

  Widget _card(List<Widget> children) {
    return SettingsCard.rows(
      rows: children,
      dividerInset: AppMetric.settingsTextDividerInset,
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String hint, {
    bool number = false,
    bool secure = false,
  }) {
    final c = context.colors;
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              child: Text(
                label,
                style: TextStyle(fontSize: 16, color: c.textPrimary),
              ),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                obscureText: secure,
                keyboardType: number ? TextInputType.number : null,
                inputFormatters: number
                    ? [FilteringTextInputFormatter.digitsOnly]
                    : null,
                autocorrect: false,
                enableSuggestions: false,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 16, color: c.textPrimary),
                cursorColor: AppTheme.brand,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: hint,
                  hintStyle: TextStyle(color: c.textTertiary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
