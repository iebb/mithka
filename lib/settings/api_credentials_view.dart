//
//  api_credentials_view.dart
//
//  Opt-in custom Telegram client API credentials. Disabled by default; when
//  enabled and valid, TDLib uses the user's api_id/api_hash instead of the
//  bundled app credentials on the next authorization bootstrap.
//

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'api_credentials_config.dart';

class ApiCredentialsView extends StatefulWidget {
  const ApiCredentialsView({super.key, this.onSaved});

  final VoidCallback? onSaved;

  @override
  State<ApiCredentialsView> createState() => _ApiCredentialsViewState();
}

class _ApiCredentialsViewState extends State<ApiCredentialsView> {
  final _apiId = TextEditingController();
  final _apiHash = TextEditingController();
  bool _enabled = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
    _apiId.addListener(() => setState(() {}));
    _apiHash.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _apiId.dispose();
    _apiHash.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await ApiCredentialsConfig.load();
    if (!mounted) return;
    if (config.apiId > 0) _apiId.text = '${config.apiId}';
    _apiHash.text = config.apiHash;
    setState(() {
      _enabled = config.enabled;
      _loading = false;
    });
  }

  bool get _valid {
    if (!_enabled) return true;
    final apiId = int.tryParse(_apiId.text.trim()) ?? 0;
    return apiId > 0 && _apiHash.text.trim().isNotEmpty;
  }

  Future<void> _save() async {
    if (!_valid || _saving) return;
    setState(() => _saving = true);
    await ApiCredentialsConfig.save(
      ApiCredentialsConfig(
        configured: true,
        enabled: _enabled,
        apiId: int.tryParse(_apiId.text.trim()) ?? 0,
        apiHash: _apiHash.text.trim(),
      ),
    );
    widget.onSaved?.call();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStringKeys.apiCredentialsTitle,
            onBack: () => Navigator.of(context).pop(),
            trailing: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _valid && !_saving ? _save : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  AppStrings.t(AppStringKeys.accentColorPickerSave),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _valid && !_saving
                        ? AppTheme.brand
                        : AppTheme.brand.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
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
                      _card([_switchRow()]),
                      const SizedBox(height: 14),
                      _card([
                        _field(
                          _apiId,
                          'api_id',
                          '123456',
                          number: true,
                          enabled: _enabled,
                        ),
                        const InsetDivider(leadingInset: 16),
                        _field(
                          _apiHash,
                          'api_hash',
                          '0123456789abcdef',
                          enabled: _enabled,
                        ),
                      ]),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Text(
                          '默认关闭。开启后需要填写你自己的 Telegram 客户端 API，保存后在下次启动或重新登录时生效；未填写完整时不会启用加速。',
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

  Widget _switchRow() {
    final c = context.colors;
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                AppStrings.t(AppStringKeys.apiCredentialsCustomClientApi),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, color: c.textPrimary),
              ),
            ),
            CupertinoSwitch(
              value: _enabled,
              activeTrackColor: AppTheme.brand,
              onChanged: (value) => setState(() => _enabled = value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String hint, {
    bool number = false,
    bool enabled = true,
  }) {
    final c = context.colors;
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            SizedBox(
              width: 76,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  color: enabled ? c.textPrimary : c.textTertiary,
                ),
              ),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
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
