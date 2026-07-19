import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'ai_settings_controller.dart';

class AiSettingsView extends StatefulWidget {
  const AiSettingsView({super.key});

  @override
  State<AiSettingsView> createState() => _AiSettingsViewState();
}

class _AiSettingsViewState extends State<AiSettingsView> {
  final _endpoint = TextEditingController();
  final _model = TextEditingController();
  final _apiKey = TextEditingController();
  bool _didLoadValues = false;
  bool _didRefreshPccCapabilities = false;
  bool _saving = false;
  bool _obscureApiKey = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = context.watch<AiSettingsController>();
    if (settings.initialized && !_didRefreshPccCapabilities) {
      _didRefreshPccCapabilities = true;
      unawaited(settings.refreshPccCapabilities());
    }
    if (!_didLoadValues && settings.initialized) {
      _endpoint.text = settings.endpoint;
      _model.text = settings.model;
      _apiKey.text = settings.apiKey;
      _didLoadValues = true;
    }
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _model.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final settings = context.watch<AiSettingsController>();
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStringKeys.aiSettingsTitle.l10n(context),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: !settings.initialized
                ? const Center(child: AppActivityIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.xl,
                      AppSpacing.lg,
                      AppSpacing.section,
                    ),
                    children: [
                      SettingsCard(
                        children: [
                          SettingsSwitchRow(
                            title: AppStringKeys.aiUnreadSummary.l10n(context),
                            value: settings.enabled,
                            leading: const SettingsIconTile(
                              icon: HeroAppIcons.wandMagicSparkles,
                              backgroundColor: Color(0xFF7467F0),
                            ),
                            onChanged: (value) =>
                                unawaited(settings.setEnabled(value)),
                          ),
                        ],
                      ),
                      _note(
                        context,
                        AppStringKeys.aiUnreadSummaryDescription.l10n(context),
                      ),
                      const SizedBox(height: AppSpacing.section),
                      _sectionTitle(
                        context,
                        AppStringKeys.aiProcessingMode.l10n(context),
                      ),
                      SettingsCard(
                        children: [
                          SettingsRow(
                            title: AppStringKeys.aiProcessingMode.l10n(context),
                            value: _providerLabel(context, settings.provider),
                            leading: const SettingsIconTile(
                              icon: HeroAppIcons.networkWired,
                              backgroundColor: Color(0xFF3478F6),
                            ),
                            onTap: () => _showProviderPicker(settings),
                          ),
                          const InsetDivider(leadingInset: 56),
                          SettingsRow(
                            title: AppStringKeys.aiOutputLanguage.l10n(context),
                            value: AppStringKeys.aiOutputSameLanguage.l10n(
                              context,
                            ),
                            leading: const SettingsIconTile(
                              icon: HeroAppIcons.language,
                              backgroundColor: Color(0xFF16A085),
                            ),
                            showChevron: false,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.section),
                      if (settings.provider == AiProviderMode.applePcc)
                        _pccConfiguration(context, settings)
                      else
                        _serverConfiguration(context),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _pccConfiguration(
    BuildContext context,
    AiSettingsController settings,
  ) {
    final capabilities = settings.pccCapabilities;
    final available =
        capabilities?.available == true &&
        capabilities?.quotaLimitReached != true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsCard(
          children: [
            SettingsRow(
              title: AppStringKeys.aiProviderApplePcc.l10n(context),
              value:
                  (available
                          ? AppStringKeys.aiPccAvailable
                          : AppStringKeys.aiPccUnavailable)
                      .l10n(context),
              leading: SettingsIconTile(
                icon: available
                    ? HeroAppIcons.cloudArrowDown
                    : HeroAppIcons.triangleExclamation,
                backgroundColor: available
                    ? const Color(0xFF20A45B)
                    : const Color(0xFFE39A20),
              ),
              showChevron: false,
            ),
          ],
        ),
        _note(
          context,
          available
              ? AppStringKeys.aiPccPrivacy.l10n(context)
              : AppStringKeys.aiPccUnavailableDescription.l10n(context),
        ),
      ],
    );
  }

  Widget _serverConfiguration(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _inputField(
          context,
          controller: _endpoint,
          icon: HeroAppIcons.networkWired,
          label: AppStringKeys.aiServerEndpoint.l10n(context),
          hint: AppStringKeys.aiServerEndpointHint.l10n(context),
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: AppSpacing.sm),
        _inputField(
          context,
          controller: _model,
          icon: HeroAppIcons.wandMagicSparkles,
          label: AppStringKeys.aiServerModel.l10n(context),
          hint: AppStringKeys.aiServerModelHint.l10n(context),
        ),
        const SizedBox(height: AppSpacing.sm),
        _inputField(
          context,
          controller: _apiKey,
          icon: HeroAppIcons.key,
          label: AppStringKeys.aiServerApiKey.l10n(context),
          hint: AppStringKeys.aiServerApiKeyOptional.l10n(context),
          obscureText: _obscureApiKey,
          trailing: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _obscureApiKey = !_obscureApiKey),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: AppIcon(
                _obscureApiKey ? HeroAppIcons.eye : HeroAppIcons.eyeSlash,
                size: 19,
                color: context.colors.textSecondary,
              ),
            ),
          ),
        ),
        _note(context, AppStringKeys.aiServerPrivacy.l10n(context)),
        const SizedBox(height: AppSpacing.lg),
        _actionButton(
          context,
          label: AppStringKeys.aiSave.l10n(context),
          saving: _saving,
          onTap: _saveServerConfiguration,
        ),
      ],
    );
  }

  Widget _inputField(
    BuildContext context, {
    required TextEditingController controller,
    required AppIconData icon,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? trailing,
  }) {
    final c = context.colors;
    return Semantics(
      textField: true,
      label: label,
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: c.divider, width: 0.5),
        ),
        child: Row(
          children: [
            AppIcon(icon, size: 19, color: c.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTextStyle.caption(c.textTertiary)),
                  const SizedBox(height: 3),
                  TextField(
                    controller: controller,
                    obscureText: obscureText,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: keyboardType,
                    style: AppTextStyle.body(c.textPrimary),
                    cursorColor: AppTheme.brand,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isCollapsed: true,
                      hintText: hint,
                      hintStyle: AppTextStyle.body(c.textTertiary),
                    ),
                  ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }

  Widget _actionButton(
    BuildContext context, {
    required String label,
    required bool saving,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      enabled: !saving,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: saving ? null : onTap,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 140),
          opacity: saving ? 0.55 : 1,
          child: Container(
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.brand,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: saving
                ? const AppActivityIndicator(size: 20, color: Color(0xFFFFFFFF))
                : Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveServerConfiguration() async {
    if (_saving) return;
    setState(() => _saving = true);
    final settings = context.read<AiSettingsController>();
    try {
      await settings.setEndpoint(_endpoint.text);
      await settings.setModel(_model.text);
      await settings.setApiKey(_apiKey.text);
      if (mounted) showToast(context, AppStringKeys.aiSaved.l10n(context));
    } on FormatException {
      if (mounted) {
        showToast(context, AppStringKeys.aiInvalidEndpoint.l10n(context));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showProviderPicker(AiSettingsController settings) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final c = sheetContext.colors;
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(14),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _providerOption(
                  sheetContext,
                  settings: settings,
                  provider: AiProviderMode.applePcc,
                  icon: HeroAppIcons.cloudArrowDown,
                ),
                const InsetDivider(leadingInset: 56),
                _providerOption(
                  sheetContext,
                  settings: settings,
                  provider: AiProviderMode.openAiCompatible,
                  icon: HeroAppIcons.networkWired,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _providerOption(
    BuildContext context, {
    required AiSettingsController settings,
    required AiProviderMode provider,
    required AppIconData icon,
  }) {
    final c = context.colors;
    final selected = settings.provider == provider;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        await settings.setProvider(provider);
        if (context.mounted) Navigator.of(context).pop();
      },
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              SettingsIconTile(
                icon: icon,
                backgroundColor: provider == AiProviderMode.applePcc
                    ? const Color(0xFF7467F0)
                    : const Color(0xFF3478F6),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _providerLabel(context, provider),
                  style: AppTextStyle.body(c.textPrimary),
                ),
              ),
              if (selected)
                AppIcon(HeroAppIcons.check, size: 18, color: AppTheme.brand),
            ],
          ),
        ),
      ),
    );
  }

  String _providerLabel(BuildContext context, AiProviderMode provider) =>
      switch (provider) {
        AiProviderMode.applePcc => AppStringKeys.aiProviderApplePcc.l10n(
          context,
        ),
        AiProviderMode.openAiCompatible =>
          AppStringKeys.aiProviderOpenAiCompatible.l10n(context),
      };

  Widget _sectionTitle(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.sm),
    child: Text(
      title,
      style: AppTextStyle.caption(context.colors.textTertiary),
    ),
  );

  Widget _note(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, AppSpacing.sm, 4, 0),
    child: Text(
      text,
      style: AppTextStyle.footnote(context.colors.textSecondary),
    ),
  );
}
