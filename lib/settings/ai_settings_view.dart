import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'ai_settings_controller.dart';
import 'openai_compatible_models_api.dart';

class AiSettingsView extends StatefulWidget {
  const AiSettingsView({super.key});

  @override
  State<AiSettingsView> createState() => _AiSettingsViewState();
}

class _AiSettingsViewState extends State<AiSettingsView> {
  final _providerName = TextEditingController();
  final _endpoint = TextEditingController();
  final _model = TextEditingController();
  final _apiKey = TextEditingController();
  final _contextWindow = TextEditingController();
  List<OpenAiCompatibleModelInfo> _availableModels = const [];
  String? _editingProfileId;
  bool _contextWindowDetected = false;
  bool _didLoadValues = false;
  bool _didRefreshPccCapabilities = false;
  bool _saving = false;
  bool _refreshingModels = false;
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
      _loadProfile(settings.activeServerProfile, settings.apiKey);
      _didLoadValues = true;
    }
  }

  @override
  void dispose() {
    _providerName.dispose();
    _endpoint.dispose();
    _model.dispose();
    _apiKey.dispose();
    _contextWindow.dispose();
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
                      if (settings.provider == AiProviderMode.openAiCompatible)
                        _serverConfiguration(context, settings),
                      if (settings.provider != AiProviderMode.openAiCompatible)
                        _appleConfiguration(context, settings),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _appleConfiguration(
    BuildContext context,
    AiSettingsController settings,
  ) {
    final capabilities = settings.pccCapabilities;
    final isPcc = settings.provider == AiProviderMode.applePcc;
    final available = isPcc
        ? capabilities?.available == true &&
              capabilities?.quotaLimitReached != true
        : capabilities?.onDeviceAvailable == true;
    final contextSize = isPcc
        ? capabilities?.contextSize
        : capabilities?.onDeviceContextSize;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsCard(
          children: [
            SettingsRow(
              title: _providerLabel(context, settings.provider),
              value:
                  (available
                          ? AppStringKeys.aiPccAvailable
                          : AppStringKeys.aiPccUnavailable)
                      .l10n(context),
              leading: SettingsIconTile(
                icon: available
                    ? (isPcc
                          ? HeroAppIcons.cloudArrowDown
                          : HeroAppIcons.mobileScreenButton)
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
              ? (isPcc
                        ? AppStringKeys.aiPccPrivacy
                        : AppStringKeys.aiOnDevicePrivacy)
                    .l10n(context)
              : (isPcc
                        ? AppStringKeys.aiPccUnavailableDescription
                        : AppStringKeys.aiOnDeviceUnavailableDescription)
                    .l10n(context),
        ),
        if (contextSize != null)
          _note(
            context,
            AppStrings.t(AppStringKeys.aiTokenContext, {
              'value1': contextSize ~/ 1024,
            }),
          ),
      ],
    );
  }

  Widget _serverConfiguration(
    BuildContext context,
    AiSettingsController settings,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(context, AppStringKeys.aiProviders.l10n(context)),
        SettingsCard(
          children: [
            if (settings.serverProfiles.isNotEmpty) ...[
              SettingsRow(
                title: AppStringKeys.aiProviders.l10n(context),
                value:
                    settings.activeServerProfile?.name ??
                    AppStringKeys.aiNoProvider.l10n(context),
                leading: const SettingsIconTile(
                  icon: HeroAppIcons.networkWired,
                  backgroundColor: Color(0xFF3478F6),
                ),
                onTap: () => _showServerProfilePicker(settings),
              ),
              const InsetDivider(leadingInset: 56),
            ],
            SettingsRow(
              title: AppStringKeys.aiAddProvider.l10n(context),
              leading: const SettingsIconTile(
                icon: HeroAppIcons.circlePlus,
                backgroundColor: Color(0xFF20A45B),
              ),
              onTap: _startNewProfile,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.section),
        _inputField(
          context,
          controller: _providerName,
          icon: HeroAppIcons.networkWired,
          label: AppStringKeys.aiProviderName.l10n(context),
          hint: AppStringKeys.aiProviderNameHint.l10n(context),
        ),
        const SizedBox(height: AppSpacing.sm),
        _inputField(
          context,
          controller: _endpoint,
          icon: HeroAppIcons.networkWired,
          label: AppStringKeys.aiServerEndpoint.l10n(context),
          hint: AppStringKeys.aiServerEndpointHint.l10n(context),
          keyboardType: TextInputType.url,
          onChanged: (_) => setState(() {
            _availableModels = const [];
            _contextWindowDetected = false;
          }),
        ),
        const SizedBox(height: AppSpacing.sm),
        _inputField(
          context,
          controller: _apiKey,
          icon: HeroAppIcons.key,
          label: AppStringKeys.aiServerApiKey.l10n(context),
          hint: AppStringKeys.aiServerApiKeyOptional.l10n(context),
          obscureText: _obscureApiKey,
          onChanged: (_) => setState(() => _contextWindowDetected = false),
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
        const SizedBox(height: AppSpacing.sm),
        _inputField(
          context,
          controller: _model,
          icon: HeroAppIcons.wandMagicSparkles,
          label: AppStringKeys.aiServerModel.l10n(context),
          hint: AppStringKeys.aiServerModelHint.l10n(context),
          onChanged: (_) => setState(() => _contextWindowDetected = false),
          trailing: _availableModels.isEmpty
              ? null
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _showModelPicker,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: AppIcon(
                      HeroAppIcons.chevronDown,
                      size: 18,
                      color: context.colors.textSecondary,
                    ),
                  ),
                ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _inputField(
          context,
          controller: _contextWindow,
          icon: HeroAppIcons.clock,
          label: AppStringKeys.aiContextWindow.l10n(context),
          hint: '${AiServerProfile.defaultContextWindowTokens}',
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() => _contextWindowDetected = false),
        ),
        _note(
          context,
          (_contextWindowDetected
                  ? AppStringKeys.aiContextDetected
                  : AppStringKeys.aiContextManual)
              .l10n(context),
        ),
        _note(context, AppStringKeys.aiServerPrivacy.l10n(context)),
        const SizedBox(height: AppSpacing.lg),
        _actionButton(
          context,
          label: AppStringKeys.aiRefreshModels.l10n(context),
          saving: _refreshingModels,
          onTap: _refreshModels,
          backgroundColor: context.colors.card,
          foregroundColor: AppTheme.brand,
          borderColor: AppTheme.brand,
        ),
        const SizedBox(height: AppSpacing.sm),
        _actionButton(
          context,
          label: AppStringKeys.aiSave.l10n(context),
          saving: _saving,
          onTap: _saveServerConfiguration,
        ),
        if (_editingProfileId != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _actionButton(
            context,
            label: AppStringKeys.aiDeleteProvider.l10n(context),
            saving: _saving,
            onTap: _deleteServerConfiguration,
            backgroundColor: const Color(0xFFDC3C3C),
          ),
        ],
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
    ValueChanged<String>? onChanged,
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
                    onChanged: onChanged,
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
    Color? backgroundColor,
    Color? foregroundColor,
    Color? borderColor,
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
              color: backgroundColor ?? AppTheme.brand,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: borderColor == null
                  ? null
                  : Border.all(color: borderColor),
            ),
            child: saving
                ? const AppActivityIndicator(size: 20, color: Color(0xFFFFFFFF))
                : Text(
                    label,
                    style: TextStyle(
                      color: foregroundColor ?? const Color(0xFFFFFFFF),
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
      final contextWindow = int.tryParse(_contextWindow.text.trim());
      if (contextWindow == null) {
        throw const FormatException('A numeric context window is required.');
      }
      final saved = await settings.saveServerProfile(
        id: _editingProfileId,
        name: _providerName.text,
        endpoint: _endpoint.text,
        model: _model.text,
        apiKey: _apiKey.text,
        contextWindowTokens: contextWindow,
        contextWindowDetected: _contextWindowDetected,
        availableModels: _availableModels,
      );
      _editingProfileId = saved.id;
      if (mounted) showToast(context, AppStringKeys.aiSaved.l10n(context));
    } on FormatException {
      if (mounted) {
        showToast(context, AppStringKeys.aiInvalidEndpoint.l10n(context));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _refreshModels() async {
    if (_refreshingModels) return;
    setState(() => _refreshingModels = true);
    try {
      final settings = context.read<AiSettingsController>();
      final models = await settings.discoverModels(
        endpoint: _endpoint.text,
        apiKey: _apiKey.text,
        preferredModel: _model.text,
      );
      if (!mounted) return;
      setState(() {
        _availableModels = models;
        if (_model.text.trim().isEmpty && models.isNotEmpty) {
          _model.text = models.first.id;
        }
        final selected = models.where((item) => item.id == _model.text.trim());
        final contextTokens = selected.isEmpty
            ? null
            : selected.first.contextWindowTokens;
        _contextWindowDetected = contextTokens != null;
        if (contextTokens != null) {
          _contextWindow.text = '$contextTokens';
        }
      });
      showToast(
        context,
        context.l10n.t(AppStringKeys.aiModelsLoaded, {'value1': models.length}),
      );
      if (models.isNotEmpty) await _showModelPicker();
    } on Object {
      if (mounted) {
        showToast(context, AppStringKeys.aiModelsFailed.l10n(context));
      }
    } finally {
      if (mounted) setState(() => _refreshingModels = false);
    }
  }

  Future<void> _deleteServerConfiguration() async {
    final profileId = _editingProfileId;
    if (profileId == null || _saving) return;
    setState(() => _saving = true);
    try {
      final settings = context.read<AiSettingsController>();
      await settings.deleteServerProfile(profileId);
      if (!mounted) return;
      _loadProfile(settings.activeServerProfile, settings.apiKey);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _startNewProfile() {
    setState(() {
      _editingProfileId = null;
      _providerName.clear();
      _endpoint.clear();
      _model.clear();
      _apiKey.clear();
      _contextWindow.text = '${AiServerProfile.defaultContextWindowTokens}';
      _availableModels = const [];
      _contextWindowDetected = false;
    });
  }

  void _loadProfile(AiServerProfile? profile, String apiKey) {
    _editingProfileId = profile?.id;
    _providerName.text = profile?.name ?? '';
    _endpoint.text = profile?.endpoint ?? '';
    _model.text = profile?.model ?? '';
    _apiKey.text = apiKey;
    _contextWindow.text =
        '${profile?.contextWindowTokens ?? AiServerProfile.defaultContextWindowTokens}';
    _availableModels = profile?.availableModels ?? const [];
    _contextWindowDetected = profile?.contextWindowDetected ?? false;
  }

  Future<void> _showServerProfilePicker(AiSettingsController settings) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final c = sheetContext.colors;
        return SafeArea(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.62,
            ),
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(14),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: settings.serverProfiles.length,
              separatorBuilder: (_, _) => const InsetDivider(leadingInset: 56),
              itemBuilder: (_, index) {
                final profile = settings.serverProfiles[index];
                final selected = profile.id == settings.activeServerProfileId;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () async {
                    await settings.selectServerProfile(profile.id);
                    if (!mounted || !sheetContext.mounted) return;
                    setState(() {
                      _loadProfile(
                        profile,
                        settings.apiKeyForServerProfile(profile.id),
                      );
                    });
                    Navigator.of(sheetContext).pop();
                  },
                  child: SizedBox(
                    height: 64,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const SettingsIconTile(
                            icon: HeroAppIcons.networkWired,
                            backgroundColor: Color(0xFF3478F6),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  profile.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyle.body(c.textPrimary),
                                ),
                                Text(
                                  profile.model,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyle.caption(c.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          if (selected)
                            AppIcon(
                              HeroAppIcons.check,
                              size: 18,
                              color: AppTheme.brand,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _showModelPicker() async {
    final models = _availableModels;
    if (models.isEmpty || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final c = sheetContext.colors;
        return SafeArea(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.68,
            ),
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(14),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: models.length,
              separatorBuilder: (_, _) => const InsetDivider(leadingInset: 16),
              itemBuilder: (_, index) {
                final model = models[index];
                final selected = model.id == _model.text.trim();
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _selectModel(model);
                  },
                  child: SizedBox(
                    height: 52,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              model.id,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.body(c.textPrimary),
                            ),
                          ),
                          if (model.contextWindowTokens case final tokens?)
                            Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: Text(
                                '${tokens ~/ 1024}K',
                                style: AppTextStyle.caption(c.textSecondary),
                              ),
                            ),
                          if (selected)
                            AppIcon(
                              HeroAppIcons.check,
                              size: 18,
                              color: AppTheme.brand,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _selectModel(OpenAiCompatibleModelInfo model) async {
    if (!mounted) return;
    setState(() {
      _model.text = model.id;
      final contextTokens = model.contextWindowTokens;
      _contextWindowDetected = contextTokens != null;
      _contextWindow.text =
          '${contextTokens ?? AiServerProfile.defaultContextWindowTokens}';
    });
    if (model.contextWindowTokens != null) return;

    setState(() => _refreshingModels = true);
    try {
      final settings = context.read<AiSettingsController>();
      final detail = await settings.discoverModelDetails(
        endpoint: _endpoint.text,
        apiKey: _apiKey.text,
        model: model.id,
      );
      final contextTokens = detail?.contextWindowTokens;
      if (!mounted || contextTokens == null || _model.text != model.id) return;
      setState(() {
        _contextWindow.text = '$contextTokens';
        _contextWindowDetected = true;
        _availableModels = [
          for (final available in _availableModels)
            if (available.id == model.id)
              OpenAiCompatibleModelInfo(
                id: available.id,
                contextWindowTokens: contextTokens,
              )
            else
              available,
        ];
      });
    } on Object {
      // The model name is still usable. Context remains explicitly manual.
    } finally {
      if (mounted) setState(() => _refreshingModels = false);
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
                  provider: AiProviderMode.appleOnDevice,
                  icon: HeroAppIcons.mobileScreenButton,
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
                backgroundColor: switch (provider) {
                  AiProviderMode.applePcc => const Color(0xFF7467F0),
                  AiProviderMode.appleOnDevice => const Color(0xFF16A085),
                  AiProviderMode.openAiCompatible => const Color(0xFF3478F6),
                },
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
        AiProviderMode.appleOnDevice =>
          AppStringKeys.aiProviderAppleOnDevice.l10n(context),
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
