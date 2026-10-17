//
//  proxy_view.dart
//
//  代理 — connection proxy settings backed by TDLib (getProxies / addProxy /
//  enableProxy / disableProxy / removeProxy / testProxy). A "不使用代理" row plus
//  the list of configured proxies (tap to enable; the active one carries a
//  brand checkmark; every row carries its own availability chip), a 测试全部
//  action that probes each saved proxy, a 删除不可用的代理 action once a probe
//  has failed, and an 添加代理 row that opens a full-page custom editor.
//  SOCKS5 / HTTP / MTProto. No Material dialogs.
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

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/confirm_dialog.dart';
import '../components/settings_selection_row.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../theme/app_theme.dart';
import 'proxy_config.dart';
import 'proxy_status.dart';

class ProxyView extends StatefulWidget {
  const ProxyView({super.key});

  @override
  State<ProxyView> createState() => _ProxyViewState();
}

class _ProxyViewState extends State<ProxyView> {
  final TdClient _client = TdClient.shared;
  StreamSubscription<Map<String, dynamic>>? _clientWakeSub;
  List<Map<String, dynamic>> _proxies = [];
  bool _loading = true;

  /// False until a getProxies read actually answered. The list lives inside
  /// the TDLib client, and a client still opening its database — the fresh
  /// slot behind the login screen's add-account flow — cannot answer yet:
  /// TDLib 1.8.67 queues a pre-parameters read with no reply at all, so
  /// "no answer" must never render as "no proxy".
  bool _clientReady = false;
  int _loadGeneration = 0;

  /// The last probe verdict per proxy id, keyed by the TDLib proxy id. Only a
  /// probe or a live link state ever writes here; removing a proxy drops its
  /// entry with it.
  final Map<int, ProxyCheckResult> _checks = {};

  /// One counter per proxy id, bumped every time a fresh probe starts, so an
  /// answer that belongs to a probe the user has since re-run is discarded.
  final Map<int, int> _checkGeneration = {};

  /// The reduced verdict of the testProxy currently in flight per proxy id.
  /// Two taps, or a tap racing 测试全部, share this one request instead of
  /// issuing a second testProxy for the same proxy.
  final Map<int, Future<ProxyCheckResult>> _pendingChecks = {};

  /// What the probe itself is told to wait, and how long the page waits past
  /// that before it gives up on a client that stopped answering.
  static const Duration _probeTimeout = Duration(seconds: 5);
  static const Duration _probeAnswerGrace = Duration(seconds: 2);

  int _nextCheckGeneration(int id) =>
      _checkGeneration[id] = (_checkGeneration[id] ?? 0) + 1;

  @override
  void initState() {
    super.initState();
    // The chips read the shared status for an enabled proxy that has not been
    // probed yet, so this surface keeps that meter tracking too — the same
    // call the sidebar shortcut makes, and idempotent.
    ProxyStatusController.shared.ensureTracking();
    _load();
    _listenForClientWake();
  }

  @override
  void dispose() {
    unawaited(_clientWakeSub?.cancel());
    super.dispose();
  }

  /// Re-reads on the first pushed authorization/connection state while the
  /// page is still waiting on its read. The parameters bootstrap runs before
  /// these updates fan out, so the re-read lands past TDLib's queue and gets
  /// answered once the database is open. Event-driven: nothing polls.
  void _listenForClientWake() {
    _clientWakeSub = _client
        .updatesOfAny(const [
          'updateAuthorizationState',
          'updateConnectionState',
        ])
        .listen((_) => unawaited(_load()));
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final clientId = _client.activeClientId;
    final slot = _client.activeSlot;
    // Every mutation on this page lands here, and the sidebar shortcut reads
    // the same list: tell it the ground moved instead of leaving it to notice
    // on the next reconnect.
    ProxyStatusController.shared.proxiesChanged();
    try {
      final res = await _client.query({'@type': 'getProxies'});
      if (!mounted ||
          generation != _loadGeneration ||
          clientId != _client.activeClientId ||
          slot != _client.activeSlot) {
        return;
      }
      final list = res.objects('proxies') ?? const <Map<String, dynamic>>[];
      if (mounted) {
        final liveIds = {for (final proxy in list) proxy.integer('id') ?? 0};
        setState(() {
          _proxies = list;
          _clientReady = true;
          _loading = false;
          // A proxy that is gone must not leave a verdict behind for an id
          // TDLib may hand to a different proxy later.
          _checks.removeWhere((id, _) => !liveIds.contains(id));
          _checkGeneration.removeWhere((id, _) => !liveIds.contains(id));
        });
      }
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
    final id = proxy.integer('id') ?? 0;
    try {
      await _client.query({'@type': 'enableProxy', 'proxy_id': id});
      await ProxyConfig.save(ProxyConfig.fromTdProxy(proxy));
      unawaited(_client.applySavedProxyToActive());
    } catch (_) {}
    unawaited(_load());
  }

  Future<void> _disable() async {
    try {
      await _client.query({'@type': 'disableProxy'});
    } catch (_) {}
    await ProxyConfig.disable();
    unawaited(_client.applySavedProxyToActive());
    unawaited(_load());
  }

  Future<void> _remove(int id) async {
    final ok = await confirmDialog(
      context,
      title: AppStrings.t(AppStringKeys.proxyDeleteProxy),
      confirmText: AppStrings.t(AppStringKeys.chatDelete),
      destructive: true,
    );
    if (!ok) return;
    final removed = _proxies.firstWhere(
      (proxy) => proxy.integer('id') == id,
      orElse: () => const <String, dynamic>{},
    );
    final wasEnabled = removed.boolean('is_enabled') ?? false;
    setState(() => _checks.remove(id));
    try {
      await _client.query({'@type': 'removeProxy', 'proxy_id': id});
      if (wasEnabled) {
        await ProxyConfig.disable();
        unawaited(_client.applySavedProxyToActive());
      }
    } catch (_) {}
    unawaited(_load());
  }

  /// Removes every proxy whose last probe failed. The button only exists while
  /// at least one row reads as unavailable, so this never runs empty.
  Future<void> _removeUnavailable() async {
    final doomed = [
      for (final proxy in _proxies)
        if (_probeFailed(proxy)) proxy,
    ];
    if (doomed.isEmpty) return;
    final ok = await confirmDialog(
      context,
      title: AppStrings.t(AppStringKeys.proxyDeleteUnavailable),
      message: AppStrings.t(AppStringKeys.proxyDeleteUnavailableMessage),
      confirmText: AppStrings.t(AppStringKeys.chatDelete),
      destructive: true,
    );
    if (!ok) return;
    final enabledIds = {
      for (final proxy in doomed)
        if (proxy.boolean('is_enabled') ?? false) proxy.integer('id') ?? 0,
    };
    final doomedIds = {for (final proxy in doomed) proxy.integer('id') ?? 0};
    setState(() {
      for (final id in doomedIds) {
        _checks.remove(id);
      }
    });
    var removedEnabled = false;
    for (final id in doomedIds) {
      try {
        await _client.query({'@type': 'removeProxy', 'proxy_id': id});
        if (enabledIds.contains(id)) removedEnabled = true;
      } catch (_) {
        // One failed removal must not abandon the rest of the batch.
      }
    }
    if (removedEnabled) {
      await ProxyConfig.disable();
      unawaited(_client.applySavedProxyToActive());
    }
    unawaited(_load());
  }

  /// Probes one saved proxy. The answer to `testProxy` is the probe's own
  /// verdict — TDLib completes it only after the socks/HTTP/MTProto handshake
  /// with the datacenter behind the proxy finished, or the request's own
  /// timeout expired — so the elapsed round trip is the latency reported.
  Future<void> _testProxy(Map<String, dynamic> proxy) async {
    final id = proxy.integer('id') ?? 0;
    // A row that is already being probed keeps the attempt it started with:
    // one testProxy per proxy id, however often the row is tapped.
    final inFlight = _checks[id]?.status == ProxyCheckStatus.testing;
    if (!inFlight) {
      final generation = _nextCheckGeneration(id);
      final clientId = _client.activeClientId;
      setState(
        () => _checks[id] = const ProxyCheckResult(ProxyCheckStatus.testing),
      );
      final outcome = await _probe(proxy, clientId);
      if (!_isCurrentCheck(id, generation, clientId)) return;
      setState(() => _checks[id] = outcome);
      return;
    }
    // A test-all pressed while a row's own tap is still waiting joins it
    // rather than issuing a second testProxy for the same proxy.
    final pending = _pendingChecks[id];
    if (pending == null) return;
    final outcome = await pending;
    if (!mounted || _checks[id]?.status != ProxyCheckStatus.testing) return;
    setState(() => _checks[id] = outcome);
  }

  /// One `testProxy` round trip, reduced to a verdict. The request carries the
  /// saved proxy's own type (SOCKS5 / HTTP credentials, MTProto secret) and the
  /// probe's own timeout; TDLib answers `ok` once the handshake with the
  /// datacenter behind the proxy finished, or a 400 whose message names the
  /// failure ('Timeout expired', 'Connection refused', ...).
  Future<ProxyCheckResult> _probe(Map<String, dynamic> proxy, int clientId) {
    final id = proxy.integer('id') ?? 0;
    final proxyDetails = ProxyConfig.tdProxyDetails(proxy);
    final stopwatch = Stopwatch()..start();
    final reduced = _client
        .queryTo({
          '@type': 'testProxy',
          'proxy': proxyDetails,
          'dc_id': kProxyTestDcId,
          'timeout': _probeTimeout.inSeconds.toDouble(),
        }, clientId)
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
    _pendingChecks[id] = reduced;
    return reduced.whenComplete(() => _pendingChecks.remove(id));
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
  /// the same probe attempt, and the same still-active client. A reconnect
  /// that replaced the client mid-probe must not paint its answer.
  bool _isCurrentCheck(int id, int generation, int clientId) =>
      mounted &&
      generation == _checkGeneration[id] &&
      _proxies.any((proxy) => proxy.integer('id') == id) &&
      !_client.isShuttingDown &&
      clientId == _client.activeClientId;

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
    return switch (details.obj('type')?.type) {
      'proxyTypeSocks5' => 'SOCKS5',
      'proxyTypeHttp' => 'HTTP',
      'proxyTypeMtproto' => 'MTProto',
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

    final config = ProxyConfig.fromTelegramUrl(result);
    if (config == null) {
      if (mounted) {
        showToast(context, AppStrings.t(AppStringKeys.proxyAddFailed));
      }
      return;
    }

    try {
      await TdClient.shared.applyProxyConfig(config);
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
  String _type = 'socks5'; // socks5 | http | mtproto
  final _server = TextEditingController();
  final _port = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _secret = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final ctl in [_server, _port, _username, _password, _secret]) {
      ctl.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final ctl in [_server, _port, _username, _password, _secret]) {
      ctl.dispose();
    }
    super.dispose();
  }

  bool get _valid {
    final server = _server.text.trim();
    final port = int.tryParse(_port.text.trim()) ?? 0;
    if (server.isEmpty || port <= 0) return false;
    if (_type == 'mtproto') return _secret.text.trim().isNotEmpty;
    return true;
  }

  ProxyConfig get _config => ProxyConfig(
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
    final config = _config;
    try {
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
          if (mtproto)
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

  Widget _typeSelector() {
    const types = [
      ('socks5', 'SOCKS5'),
      ('http', 'HTTP'),
      ('mtproto', 'MTProto'),
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
