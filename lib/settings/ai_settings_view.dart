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

class _AiModelEditorSheet extends StatefulWidget {
  const _AiModelEditorSheet({
    required this.settings,
    required this.provider,
    required this.discoveredModel,
    required this.manual,
  });

  final AiSettingsController settings;
  final AiServerProvider provider;
  final OpenAiCompatibleModelInfo? discoveredModel;
  final bool manual;

  @override
  State<_AiModelEditorSheet> createState() => _AiModelEditorSheetState();
}

class _AiModelEditorSheetState extends State<_AiModelEditorSheet> {
  late final TextEditingController _model;
  late final TextEditingController _contextWindow;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _model = TextEditingController(text: widget.discoveredModel?.id ?? '');
    _contextWindow = TextEditingController(
      text:
          '${widget.discoveredModel?.contextWindowTokens ?? AiModelProfile.defaultContextWindowTokens}',
    );
  }

  @override
  void dispose() {
    _model.dispose();
    _contextWindow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: c.groupedBackground,
            borderRadius: BorderRadius.circular(14),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsRow(
                  title: AppStringKeys.aiProviders.l10n(context),
                  value: widget.provider.name,
                  leading: const SettingsIconTile(
                    icon: HeroAppIcons.server,
                    backgroundColor: Color(0xFF3478F6),
                  ),
                  showChevron: false,
                ),
                const SizedBox(height: AppSpacing.sm),
                _field(
                  controller: _model,
                  icon: HeroAppIcons.cube,
                  label: AppStringKeys.aiServerModel.l10n(context),
                  hint: AppStringKeys.aiServerModelHint.l10n(context),
                  readOnly: !widget.manual,
                ),
                const SizedBox(height: AppSpacing.sm),
                _field(
                  controller: _contextWindow,
                  icon: HeroAppIcons.tokenStack,
                  label: AppStringKeys.aiContextWindow.l10n(context),
                  hint: '${AiModelProfile.defaultContextWindowTokens}',
                  keyboardType: TextInputType.number,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, AppSpacing.sm, 4, 0),
                  child: Text(
                    (widget.discoveredModel?.contextWindowTokens != null
                            ? AppStringKeys.aiContextDetected
                            : AppStringKeys.aiContextManual)
                        .l10n(context),
                    style: AppTextStyle.footnote(c.textSecondary),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _saveButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required AppIconData icon,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    bool readOnly = false,
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
                    readOnly: readOnly,
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
          ],
        ),
      ),
    );
  }

  Widget _saveButton() => Semantics(
    button: true,
    enabled: !_saving,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _saving ? null : _save,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 140),
        opacity: _saving ? 0.55 : 1,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTheme.brand,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: _saving
              ? const AppActivityIndicator(size: 20, color: Color(0xFFFFFFFF))
              : Text(
                  AppStringKeys.aiSaveModel.l10n(context),
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

  Future<void> _save() async {
    final contextWindow = int.tryParse(_contextWindow.text.trim());
    if (contextWindow == null) {
      showToast(context, AppStringKeys.aiInvalidModel.l10n(context));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.settings.saveModelProfile(
        providerId: widget.provider.id,
        model: _model.text,
        contextWindowTokens: contextWindow,
        contextWindowDetected:
            widget.discoveredModel?.contextWindowTokens != null,
      );
      if (!mounted) return;
      showToast(context, AppStringKeys.aiSaved.l10n(context));
      Navigator.of(context).pop();
    } on FormatException {
      if (!mounted) return;
      showToast(context, AppStringKeys.aiInvalidModel.l10n(context));
      setState(() => _saving = false);
    }
  }
}

class _AiSettingsViewState extends State<AiSettingsView> {
  final _providerName = TextEditingController();
  final _endpoint = TextEditingController();
  final _apiKey = TextEditingController();
  String? _editingProfileId;
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
      _loadProfile(settings.activeServerProfile, settings.apiKey);
      _didLoadValues = true;
    }
  }

  @override
  void dispose() {
    _providerName.dispose();
    _endpoint.dispose();
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
                              icon: HeroAppIcons.cpuChip,
                              backgroundColor: Color(0xFF7467F0),
                            ),
                            onChanged: (value) =>
                                unawaited(settings.setEnabled(value)),
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
                            leading: SettingsIconTile(
                              icon: _providerIcon(settings.provider),
                              backgroundColor: const Color(0xFF3478F6),
                            ),
                            onTap: () => _showProviderPicker(settings),
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
                    ? (isPcc ? HeroAppIcons.cloud : HeroAppIcons.cpuChip)
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
    final activeProvider = settings.activeServerProvider;
    final activeModel = settings.activeModelProfile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(context, AppStringKeys.aiProviders.l10n(context)),
        SettingsCard(
          children: [
            if (settings.serverProviders.isNotEmpty) ...[
              SettingsRow(
                title: AppStringKeys.aiProviders.l10n(context),
                value:
                    activeProvider?.name ??
                    AppStringKeys.aiNoProvider.l10n(context),
                leading: const SettingsIconTile(
                  icon: HeroAppIcons.server,
                  backgroundColor: Color(0xFF3478F6),
                ),
                onTap: () => _showServerProviderPicker(settings),
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
          icon: HeroAppIcons.server,
          label: AppStringKeys.aiProviderName.l10n(context),
          hint: AppStringKeys.aiProviderNameHint.l10n(context),
        ),
        const SizedBox(height: AppSpacing.sm),
        _inputField(
          context,
          controller: _endpoint,
          icon: HeroAppIcons.link,
          label: AppStringKeys.aiServerEndpoint.l10n(context),
          hint: AppStringKeys.aiServerEndpointHint.l10n(context),
          keyboardType: TextInputType.url,
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
          label: AppStringKeys.aiSaveProvider.l10n(context),
          saving: _saving,
          onTap: _saveServerProvider,
        ),
        if (_editingProfileId != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _actionButton(
            context,
            label: AppStringKeys.aiDeleteProvider.l10n(context),
            saving: _saving,
            onTap: _deleteServerProvider,
            backgroundColor: const Color(0xFFDC3C3C),
          ),
        ],
        const SizedBox(height: AppSpacing.section),
        _sectionTitle(context, AppStringKeys.aiModels.l10n(context)),
        SettingsCard(
          children: [
            if (activeProvider != null) ...[
              SettingsRow(
                title: AppStringKeys.aiServerModel.l10n(context),
                value:
                    activeModel?.model ?? AppStringKeys.aiNoModel.l10n(context),
                leading: const SettingsIconTile(
                  icon: HeroAppIcons.cube,
                  backgroundColor: Color(0xFF7467F0),
                ),
                onTap: settings.modelsForProvider(activeProvider.id).isEmpty
                    ? null
                    : () => _showSavedModelPicker(settings),
              ),
              const InsetDivider(leadingInset: 56),
            ],
            SettingsRow(
              title: AppStringKeys.aiAddModel.l10n(context),
              value: activeProvider == null
                  ? AppStringKeys.aiAddProviderFirst.l10n(context)
                  : '',
              leading: SettingsIconTile(
                icon: HeroAppIcons.circlePlus,
                backgroundColor: activeProvider == null
                    ? context.colors.textTertiary
                    : const Color(0xFF20A45B),
              ),
              onTap: activeProvider == null
                  ? null
                  : () => _startAddModel(settings),
              showChevron: activeProvider != null,
            ),
          ],
        ),
        if (activeModel != null) ...[
          _note(
            context,
            context.l10n.t(AppStringKeys.aiModelProvider, {
              'value1': activeProvider?.name ?? '',
            }),
          ),
          const SizedBox(height: AppSpacing.sm),
          _actionButton(
            context,
            label: AppStringKeys.aiDeleteModel.l10n(context),
            saving: _saving,
            onTap: () => _deleteActiveModel(settings),
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
    bool readOnly = false,
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
                    readOnly: readOnly,
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

  Future<void> _saveServerProvider() async {
    if (_saving) return;
    setState(() => _saving = true);
    final settings = context.read<AiSettingsController>();
    try {
      final saved = await settings.saveServerProvider(
        id: _editingProfileId,
        name: _providerName.text,
        endpoint: _endpoint.text,
        apiKey: _apiKey.text,
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

  Future<void> _deleteServerProvider() async {
    final profileId = _editingProfileId;
    if (profileId == null || _saving) return;
    setState(() => _saving = true);
    try {
      final settings = context.read<AiSettingsController>();
      await settings.deleteServerProvider(profileId);
      if (!mounted) return;
      _loadProfile(settings.activeServerProvider, settings.apiKey);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _startNewProfile() {
    setState(() {
      _editingProfileId = null;
      _providerName.clear();
      _endpoint.clear();
      _apiKey.clear();
    });
  }

  void _loadProfile(AiServerProvider? provider, String apiKey) {
    _editingProfileId = provider?.id;
    _providerName.text = provider?.name ?? '';
    _endpoint.text = provider?.endpoint ?? '';
    _apiKey.text = apiKey;
  }

  Future<void> _showServerProviderPicker(AiSettingsController settings) async {
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
              itemCount: settings.serverProviders.length,
              separatorBuilder: (_, _) => const InsetDivider(leadingInset: 56),
              itemBuilder: (_, index) {
                final provider = settings.serverProviders[index];
                final selected = provider.id == settings.activeServerProviderId;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () async {
                    await settings.selectServerProvider(provider.id);
                    if (!mounted || !sheetContext.mounted) return;
                    setState(() {
                      _loadProfile(
                        provider,
                        settings.apiKeyForServerProvider(provider.id),
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
                            icon: HeroAppIcons.server,
                            backgroundColor: Color(0xFF3478F6),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  provider.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyle.body(c.textPrimary),
                                ),
                                Text(
                                  provider.endpoint,
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

  Future<void> _showSavedModelPicker(AiSettingsController settings) async {
    final provider = settings.activeServerProvider;
    if (provider == null) return;
    final models = settings.modelsForProvider(provider.id);
    if (models.isEmpty) return;
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
              separatorBuilder: (_, _) => const InsetDivider(leadingInset: 56),
              itemBuilder: (_, index) {
                final model = models[index];
                final selected = model.id == settings.activeModelProfileId;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () async {
                    await settings.selectModelProfile(model.id);
                    if (sheetContext.mounted) {
                      Navigator.of(sheetContext).pop();
                    }
                  },
                  child: SizedBox(
                    height: 60,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const SettingsIconTile(
                            icon: HeroAppIcons.cube,
                            backgroundColor: Color(0xFF7467F0),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              model.model,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.body(c.textPrimary),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: Text(
                              '${model.contextWindowTokens ~/ 1024}K',
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

  Future<void> _startAddModel(AiSettingsController settings) async {
    final provider = await _pickModelProvider(settings);
    if (provider == null || !mounted) return;
    var models = provider.availableModels;
    try {
      models = await settings.refreshModelsForProvider(provider.id);
      if (mounted) {
        showToast(
          context,
          context.l10n.t(AppStringKeys.aiModelsLoaded, {
            'value1': models.length,
          }),
        );
      }
    } on Object {
      if (mounted) {
        showToast(context, AppStringKeys.aiModelsFailed.l10n(context));
      }
    }
    if (!mounted) return;
    final choice = await _pickDiscoveredModel(models);
    if (choice == null || !mounted) return;
    var discovered = choice.model;
    if (!choice.manual && discovered?.contextWindowTokens == null) {
      try {
        discovered =
            await settings.discoverModelDetails(
              endpoint: provider.endpoint,
              apiKey: settings.apiKeyForServerProvider(provider.id),
              model: discovered!.id,
            ) ??
            discovered;
      } on Object {
        // The model remains usable with an explicitly confirmed context size.
      }
    }
    if (!mounted) return;
    await _showModelEditor(
      settings: settings,
      provider: provider,
      discoveredModel: discovered,
      manual: choice.manual,
    );
  }

  Future<AiServerProvider?> _pickModelProvider(AiSettingsController settings) =>
      showModalBottomSheet<AiServerProvider>(
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
                itemCount: settings.serverProviders.length,
                separatorBuilder: (_, _) =>
                    const InsetDivider(leadingInset: 56),
                itemBuilder: (_, index) {
                  final provider = settings.serverProviders[index];
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(sheetContext).pop(provider),
                    child: SizedBox(
                      height: 64,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            const SettingsIconTile(
                              icon: HeroAppIcons.server,
                              backgroundColor: Color(0xFF3478F6),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    provider.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyle.body(c.textPrimary),
                                  ),
                                  Text(
                                    provider.endpoint,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyle.caption(
                                      c.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
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

  Future<({bool manual, OpenAiCompatibleModelInfo? model})?>
  _pickDiscoveredModel(List<OpenAiCompatibleModelInfo> models) =>
      showModalBottomSheet<({bool manual, OpenAiCompatibleModelInfo? model})>(
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
                itemCount: models.length + 1,
                separatorBuilder: (_, _) =>
                    const InsetDivider(leadingInset: 56),
                itemBuilder: (_, index) {
                  if (index == models.length) {
                    return _modelChoiceRow(
                      sheetContext,
                      icon: HeroAppIcons.pen,
                      title: AppStringKeys.aiEnterModelManually.l10n(
                        sheetContext,
                      ),
                      onTap: () => Navigator.of(
                        sheetContext,
                      ).pop((manual: true, model: null)),
                    );
                  }
                  final model = models[index];
                  return _modelChoiceRow(
                    sheetContext,
                    icon: HeroAppIcons.cube,
                    title: model.id,
                    value: model.contextWindowTokens == null
                        ? ''
                        : '${model.contextWindowTokens! ~/ 1024}K',
                    onTap: () => Navigator.of(
                      sheetContext,
                    ).pop((manual: false, model: model)),
                  );
                },
              ),
            ),
          );
        },
      );

  Widget _modelChoiceRow(
    BuildContext context, {
    required AppIconData icon,
    required String title,
    String value = '',
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 60,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              SettingsIconTile(
                icon: icon,
                backgroundColor: const Color(0xFF7467F0),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.body(c.textPrimary),
                ),
              ),
              if (value.isNotEmpty)
                Text(value, style: AppTextStyle.caption(c.textSecondary)),
              const SizedBox(width: 8),
              AppIcon(
                HeroAppIcons.chevronRight,
                size: 16,
                color: c.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showModelEditor({
    required AiSettingsController settings,
    required AiServerProvider provider,
    required OpenAiCompatibleModelInfo? discoveredModel,
    required bool manual,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AiModelEditorSheet(
      settings: settings,
      provider: provider,
      discoveredModel: discoveredModel,
      manual: manual,
    ),
  );

  Future<void> _deleteActiveModel(AiSettingsController settings) async {
    final id = settings.activeModelProfileId;
    if (id == null || _saving) return;
    setState(() => _saving = true);
    try {
      await settings.deleteModelProfile(id);
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
                  icon: HeroAppIcons.cloud,
                ),
                const InsetDivider(leadingInset: 56),
                _providerOption(
                  sheetContext,
                  settings: settings,
                  provider: AiProviderMode.appleOnDevice,
                  icon: HeroAppIcons.cpuChip,
                ),
                const InsetDivider(leadingInset: 56),
                _providerOption(
                  sheetContext,
                  settings: settings,
                  provider: AiProviderMode.openAiCompatible,
                  icon: HeroAppIcons.server,
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

  AppIconData _providerIcon(AiProviderMode provider) => switch (provider) {
    AiProviderMode.applePcc => HeroAppIcons.cloud,
    AiProviderMode.appleOnDevice => HeroAppIcons.cpuChip,
    AiProviderMode.openAiCompatible => HeroAppIcons.server,
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
