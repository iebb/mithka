//
//  proxy_view.dart
//
//  代理 — connection proxy settings backed by TDLib (getProxies / addProxy /
//  enableProxy / disableProxy / removeProxy). A "不使用代理" row plus the list of
//  configured proxies (tap to enable; the active one carries a brand checkmark),
//  and an 添加代理 row that opens a full-page custom editor. SOCKS5 / HTTP /
//  MTProto. No Material dialogs.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/confirm_dialog.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../theme/app_theme.dart';
import 'proxy_config.dart';

class ProxyView extends StatefulWidget {
  const ProxyView({super.key});

  @override
  State<ProxyView> createState() => _ProxyViewState();
}

class _ProxyViewState extends State<ProxyView> {
  final TdClient _client = TdClient.shared;
  List<Map<String, dynamic>> _proxies = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _client.query({'@type': 'getProxies'});
      final list = res.objects('proxies') ?? const <Map<String, dynamic>>[];
      if (mounted) {
        setState(() {
          _proxies = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _anyEnabled => _proxies.any((p) => p.boolean('is_enabled') ?? false);

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
    try {
      await _client.query({'@type': 'removeProxy', 'proxy_id': id});
      if (wasEnabled) {
        await ProxyConfig.disable();
        unawaited(_client.applySavedProxyToActive());
      }
    } catch (_) {}
    unawaited(_load());
  }

  Future<void> _add() async {
    final added = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const ProxyEditView()));
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
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.proxyTitle),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
                    children: [
                      _card([_noneRow()]),
                      if (_proxies.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _card([
                          for (var i = 0; i < _proxies.length; i++) ...[
                            if (i > 0) const InsetDivider(leadingInset: 16),
                            _proxyRow(_proxies[i]),
                          ],
                        ]),
                      ],
                      const SizedBox(height: 14),
                      _card([_addRow()]),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Text(
                          AppStrings.t(AppStringKeys.proxyDescription),
                          style: TextStyle(
                            fontSize: 13,
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _card(List<Widget> children) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _noneRow() {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _anyEnabled ? _disable : null,
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                AppStrings.t(AppStringKeys.proxyDisabled),
                style: TextStyle(fontSize: 16, color: c.textPrimary),
              ),
              const Spacer(),
              if (!_anyEnabled)
                AppIcon(HeroAppIcons.check, size: 18, color: AppTheme.brand),
            ],
          ),
        ),
      ),
    );
  }

  Widget _proxyRow(Map<String, dynamic> proxy) {
    final c = context.colors;
    final details = ProxyConfig.tdProxyDetails(proxy);
    final id = proxy.integer('id') ?? 0;
    final enabled = proxy.boolean('is_enabled') ?? false;
    final server = details.str('server') ?? '';
    final port = details.integer('port') ?? 0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? null : () => _enable(proxy),
      child: SizedBox(
        height: 60,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$server:$port',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, color: c.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _typeLabel(proxy),
                      style: TextStyle(fontSize: 12, color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              if (enabled) ...[
                AppIcon(HeroAppIcons.check, size: 18, color: AppTheme.brand),
                const SizedBox(width: 12),
              ],
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _remove(id),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: AppIcon(
                    HeroAppIcons.circleMinus,
                    size: 20,
                    color: AppTheme.tagRed.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addRow() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _add,
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              AppIcon(HeroAppIcons.plus, size: 18, color: AppTheme.brand),
              const SizedBox(width: 10),
              Text(
                AppStrings.t(AppStringKeys.proxyAddProxy),
                style: TextStyle(fontSize: 16, color: AppTheme.brand),
              ),
            ],
          ),
        ),
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
    if (widget.allowOfflineSave) {
      await ProxyConfig.save(config);
      unawaited(TdClient.shared.applySavedProxyToActive());
      if (mounted) Navigator.of(context).pop(true);
      return;
    }
    try {
      await TdClient.shared.applyProxyConfig(config);
      await ProxyConfig.save(config);
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
    final c = context.colors;
    final mtproto = _type == 'mtproto';
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.proxyAddProxy),
            onBack: () => Navigator.of(context).pop(),
            trailing: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _save,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
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
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 14),
              children: [
                _segments(),
                const SizedBox(height: 14),
                _card([
                  _field(
                    _server,
                    AppStrings.t(AppStringKeys.proxyServer),
                    AppStrings.t(AppStringKeys.proxyHostOrIp),
                  ),
                  const InsetDivider(leadingInset: 16),
                  _field(
                    _port,
                    AppStrings.t(AppStringKeys.proxyPort),
                    '0-65535',
                    number: true,
                  ),
                ]),
                const SizedBox(height: 14),
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
                    const InsetDivider(leadingInset: 16),
                    _field(
                      _password,
                      AppStrings.t(AppStringKeys.proxyPassword),
                      AppStrings.t(AppStringKeys.proxyOptional),
                      secure: true,
                    ),
                  ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _segments() {
    final c = context.colors;
    const types = [
      ('socks5', 'SOCKS5'),
      ('http', 'HTTP'),
      ('mtproto', 'MTProto'),
    ];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.searchFill,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          for (final t in types)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _type = t.$1),
                child: Container(
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _type == t.$1 ? c.card : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    t.$2,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: _type == t.$1
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: _type == t.$1 ? c.textPrimary : c.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _card(List<Widget> children) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
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
