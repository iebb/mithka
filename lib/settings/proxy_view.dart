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
    return SettingsPageScaffold(
      title: AppStrings.t(AppStringKeys.proxyTitle),
      onBack: () => Navigator.of(context).pop(),
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

  Widget _proxyRow(Map<String, dynamic> proxy) {
    final details = ProxyConfig.tdProxyDetails(proxy);
    final id = proxy.integer('id') ?? 0;
    final enabled = proxy.boolean('is_enabled') ?? false;
    final server = details.str('server') ?? '';
    final port = details.integer('port') ?? 0;
    return SettingsRow(
      title: '$server:$port',
      subtitle: _typeLabel(proxy),
      showChevron: false,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (enabled) ...[
            AppIcon(HeroAppIcons.check, size: 18, color: AppTheme.brand),
            const SizedBox(width: AppSpacing.lg),
          ],
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
    final mtproto = _type == 'mtproto';
    return SettingsPageScaffold(
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
