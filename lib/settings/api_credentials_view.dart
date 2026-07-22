//
//  api_credentials_view.dart
//
//  Custom Telegram client identity. API credentials are opt-in; the TDLib
//  user-agent fields can be overridden independently. Saved values take effect
//  on the next authorization bootstrap.
//

import 'dart:io';

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
  final _deviceModel = TextEditingController();
  final _systemVersion = TextEditingController();
  final _applicationVersion = TextEditingController();
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
    _deviceModel.dispose();
    _systemVersion.dispose();
    _applicationVersion.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await ApiCredentialsConfig.load();
    if (!mounted) return;
    if (config.apiId > 0) _apiId.text = '${config.apiId}';
    _apiHash.text = config.apiHash;
    _deviceModel.text = config.deviceModel;
    _systemVersion.text = config.systemVersion;
    _applicationVersion.text = config.applicationVersion;
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
        deviceModel: _deviceModel.text.trim(),
        systemVersion: _systemVersion.text.trim(),
        applicationVersion: _applicationVersion.text.trim(),
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
                          fieldKey: const ValueKey('telegramApiIdField'),
                          number: true,
                          enabled: _enabled,
                        ),
                        const InsetDivider(leadingInset: 16),
                        _field(
                          _apiHash,
                          'api_hash',
                          '0123456789abcdef',
                          fieldKey: const ValueKey('telegramApiHashField'),
                          enabled: _enabled,
                        ),
                      ]),
                      const SizedBox(height: 14),
                      _sectionTitle(
                        AppStrings.t(AppStringKeys.apiCredentialsUserAgent),
                      ),
                      _card([
                        _field(
                          _deviceModel,
                          'device_model',
                          Platform.isIOS ? 'iPhone' : 'Android',
                          fieldKey: const ValueKey('tdlibDeviceModelField'),
                        ),
                        const InsetDivider(leadingInset: 16),
                        _field(
                          _systemVersion,
                          'system_version',
                          _systemVersionHint,
                          fieldKey: const ValueKey('tdlibSystemVersionField'),
                        ),
                        const InsetDivider(leadingInset: 16),
                        _field(
                          _applicationVersion,
                          'app_version',
                          '1.0',
                          fieldKey: const ValueKey(
                            'tdlibApplicationVersionField',
                          ),
                        ),
                      ]),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Text(
                          AppStrings.t(AppStringKeys.apiCredentialsDescription),
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

  Widget _sectionTitle(String title) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: TextStyle(
            color: c.textTertiary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  String get _systemVersionHint {
    try {
      final value = Platform.operatingSystemVersion.trim();
      return value.isEmpty ? Platform.operatingSystem : value;
    } catch (_) {
      return Platform.operatingSystem;
    }
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
            AppSwitch(
              value: _enabled,
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
    Key? fieldKey,
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
              width: 128,
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
                key: fieldKey,
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
