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
  bool _refreshedCapabilities = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = context.watch<AiSettingsController>();
    if (settings.initialized && !_refreshedCapabilities) {
      _refreshedCapabilities = true;
      unawaited(settings.refreshPccCapabilities());
    }
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
                        AppStringKeys.aiModels.l10n(context),
                      ),
                      SettingsCard(
                        children: [
                          SettingsRow(
                            title: AppStringKeys.aiProviders.l10n(context),
                            value: '${settings.serverProviders.length}',
                            leading: const SettingsIconTile(
                              icon: HeroAppIcons.server,
                              backgroundColor: Color(0xFF3478F6),
                            ),
                            onTap: () =>
                                _push(context, const AiProviderListView()),
                          ),
                          const InsetDivider(leadingInset: 56),
                          SettingsRow(
                            title: AppStringKeys.aiModels.l10n(context),
                            value: '${settings.modelCandidates.length}',
                            leading: const SettingsIconTile(
                              icon: HeroAppIcons.cube,
                              backgroundColor: Color(0xFF7467F0),
                            ),
                            onTap: () =>
                                _push(context, const AiModelListView()),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.section),
                      _sectionTitle(
                        context,
                        AppStringKeys.aiModelConfiguration.l10n(context),
                      ),
                      SettingsCard(
                        children: [
                          _featureModelRow(
                            context,
                            settings: settings,
                            feature: AiFeature.translation,
                            title: AppStringKeys.aiTranslateUsing.l10n(context),
                            icon: HeroAppIcons.language,
                            color: const Color(0xFF16A085),
                          ),
                          const InsetDivider(leadingInset: 56),
                          _featureModelRow(
                            context,
                            settings: settings,
                            feature: AiFeature.summary,
                            title: AppStringKeys.aiSummarizeUsing.l10n(context),
                            icon: HeroAppIcons.listCheck,
                            color: const Color(0xFF7467F0),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _featureModelRow(
    BuildContext context, {
    required AiSettingsController settings,
    required AiFeature feature,
    required String title,
    required AppIconData icon,
    required Color color,
  }) {
    final candidate = feature == AiFeature.translation
        ? settings.translationModelCandidate
        : settings.summaryModelCandidate;
    return SettingsRow(
      title: title,
      value: _candidateLabel(context, candidate),
      leading: SettingsIconTile(icon: icon, backgroundColor: color),
      onTap: () => _showFeatureModelPicker(
        context,
        settings: settings,
        feature: feature,
      ),
    );
  }
}

class AiProviderListView extends StatelessWidget {
  const AiProviderListView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final settings = context.watch<AiSettingsController>();
    final providers = settings.serverProviders;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStringKeys.aiProviders.l10n(context),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.section,
              ),
              children: [
                SettingsCard(
                  children: [
                    for (var index = 0; index < providers.length; index++) ...[
                      if (index > 0) const InsetDivider(leadingInset: 56),
                      SettingsRow(
                        title: providers[index].name,
                        value: providers[index].endpoint,
                        leading: const SettingsIconTile(
                          icon: HeroAppIcons.server,
                          backgroundColor: Color(0xFF3478F6),
                        ),
                        onTap: () => _push(
                          context,
                          AiProviderEditorView(
                            provider: providers[index],
                            initialApiKey: settings.apiKeyForServerProvider(
                              providers[index].id,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (providers.isNotEmpty)
                      const InsetDivider(leadingInset: 56),
                    SettingsRow(
                      title: AppStringKeys.aiAddProvider.l10n(context),
                      leading: const SettingsIconTile(
                        icon: HeroAppIcons.circlePlus,
                        backgroundColor: Color(0xFF20A45B),
                      ),
                      onTap: () => _push(context, const AiProviderEditorView()),
                    ),
                  ],
                ),
                if (providers.isEmpty)
                  _note(context, AppStringKeys.aiNoProvider.l10n(context)),
                _note(context, AppStringKeys.aiServerPrivacy.l10n(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AiProviderEditorView extends StatefulWidget {
  const AiProviderEditorView({
    super.key,
    this.provider,
    this.initialApiKey = '',
  });

  final AiServerProvider? provider;
  final String initialApiKey;

  @override
  State<AiProviderEditorView> createState() => _AiProviderEditorViewState();
}

class _AiProviderEditorViewState extends State<AiProviderEditorView> {
  late final TextEditingController _name;
  late final TextEditingController _endpoint;
  late final TextEditingController _apiKey;
  bool _obscureApiKey = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.provider?.name ?? '');
    _endpoint = TextEditingController(text: widget.provider?.endpoint ?? '');
    _apiKey = TextEditingController(text: widget.initialApiKey);
  }

  @override
  void dispose() {
    _name.dispose();
    _endpoint.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title:
                (widget.provider == null
                        ? AppStringKeys.aiAddProvider
                        : AppStringKeys.aiEditProvider)
                    .l10n(context),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.section,
              ),
              children: [
                _inputField(
                  context,
                  controller: _name,
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
                    onTap: () =>
                        setState(() => _obscureApiKey = !_obscureApiKey),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: AppIcon(
                        _obscureApiKey
                            ? HeroAppIcons.eye
                            : HeroAppIcons.eyeSlash,
                        size: 19,
                        color: c.textSecondary,
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
                  onTap: _save,
                ),
                if (widget.provider != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _actionButton(
                    context,
                    label: AppStringKeys.aiDeleteProvider.l10n(context),
                    saving: _saving,
                    onTap: _delete,
                    backgroundColor: const Color(0xFFDC3C3C),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await context.read<AiSettingsController>().saveServerProvider(
        id: widget.provider?.id,
        name: _name.text,
        endpoint: _endpoint.text,
        apiKey: _apiKey.text,
      );
      if (!mounted) return;
      showToast(context, AppStringKeys.aiSaved.l10n(context));
      Navigator.of(context).pop();
    } on FormatException {
      if (!mounted) return;
      showToast(context, AppStringKeys.aiInvalidEndpoint.l10n(context));
      setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final provider = widget.provider;
    if (provider == null || _saving) return;
    setState(() => _saving = true);
    await context.read<AiSettingsController>().deleteServerProvider(
      provider.id,
    );
    if (mounted) Navigator.of(context).pop();
  }
}

class AiModelListView extends StatelessWidget {
  const AiModelListView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final settings = context.watch<AiSettingsController>();
    final candidates = settings.modelCandidates;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStringKeys.aiModels.l10n(context),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.section,
              ),
              children: [
                SettingsCard(
                  children: [
                    for (var index = 0; index < candidates.length; index++) ...[
                      if (index > 0) const InsetDivider(leadingInset: 56),
                      _candidateListRow(
                        context,
                        settings: settings,
                        candidate: candidates[index],
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                _addModelCard(context, settings),
                _note(
                  context,
                  AppStringKeys.aiModelCandidatesDescription.l10n(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _candidateListRow(
    BuildContext context, {
    required AiSettingsController settings,
    required AiModelCandidate candidate,
  }) {
    final profile = candidate.profile;
    return SettingsRow(
      title: _candidateLabel(context, candidate),
      value: _candidateDetail(context, settings, candidate),
      leading: SettingsIconTile(
        icon: _candidateIcon(candidate),
        backgroundColor: _candidateColor(candidate),
      ),
      onTap: profile == null
          ? null
          : () => _push(context, AiModelEditorView(profile: profile)),
      showChevron: profile != null,
    );
  }

  Widget _addModelCard(BuildContext context, AiSettingsController settings) {
    final c = context.colors;
    final enabled = settings.serverProviders.isNotEmpty;
    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        key: const ValueKey('aiAddModelCard'),
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => _push(context, const AiModelEditorView()) : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: enabled ? 1 : 0.58,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: enabled ? AppTheme.brand.withValues(alpha: 0.08) : c.card,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: enabled
                    ? AppTheme.brand.withValues(alpha: 0.24)
                    : c.divider,
                width: 0.8,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: enabled ? const Color(0xFF20A45B) : c.textTertiary,
                    shape: BoxShape.circle,
                  ),
                  child: const AppIcon(
                    HeroAppIcons.circlePlus,
                    size: 21,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppStringKeys.aiAddModel.l10n(context),
                        style: AppTextStyle.body(
                          enabled ? c.textPrimary : c.textTertiary,
                          weight: AppTextWeight.semibold,
                        ),
                      ),
                      if (!enabled) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          AppStringKeys.aiAddProviderFirst.l10n(context),
                          style: AppTextStyle.footnote(c.textTertiary),
                        ),
                      ],
                    ],
                  ),
                ),
                if (enabled)
                  AppIcon(
                    HeroAppIcons.chevronRight,
                    size: AppIconSize.chevron,
                    color: c.textTertiary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AiModelEditorView extends StatefulWidget {
  const AiModelEditorView({super.key, this.profile});

  final AiModelProfile? profile;

  @override
  State<AiModelEditorView> createState() => _AiModelEditorViewState();
}

class _AiModelEditorViewState extends State<AiModelEditorView> {
  late final TextEditingController _model;
  late final TextEditingController _contextWindow;
  late final TextEditingController _testPrompt;
  String? _providerId;
  bool _contextDetected = false;
  bool _saving = false;
  bool _loadingModels = false;
  bool _modelsLoadFailed = false;
  bool _manualModelEntry = false;
  bool _testingModel = false;
  bool _testFailed = false;
  String? _testResponse;
  String? _autoDiscoveryProviderId;
  int _discoveryGeneration = 0;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _providerId = profile?.providerId;
    _model = TextEditingController(text: profile?.model ?? '');
    _contextWindow = TextEditingController(
      text:
          '${profile?.contextWindowTokens ?? AiModelProfile.defaultContextWindowTokens}',
    );
    _testPrompt = TextEditingController();
    _contextDetected = profile?.contextWindowDetected ?? false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_testPrompt.text.isEmpty) {
      _testPrompt.text = AppStringKeys.aiTestPromptDefault.l10n(context);
    }
    final settings = context.read<AiSettingsController>();
    _providerId ??= settings.serverProviders.firstOrNull?.id;
    final providerId = _providerId;
    if (providerId != null && _autoDiscoveryProviderId != providerId) {
      _autoDiscoveryProviderId = providerId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _providerId == providerId) {
          unawaited(_loadModels(settings));
        }
      });
    }
  }

  @override
  void dispose() {
    _model.dispose();
    _contextWindow.dispose();
    _testPrompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final settings = context.watch<AiSettingsController>();
    final provider = settings.serverProviders
        .where((item) => item.id == _providerId)
        .firstOrNull;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title:
                (widget.profile == null
                        ? AppStringKeys.aiAddModel
                        : AppStringKeys.aiEditModel)
                    .l10n(context),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.section,
              ),
              children: [
                SettingsCard(
                  children: [
                    SettingsRow(
                      title: AppStringKeys.aiProviders.l10n(context),
                      value:
                          provider?.name ??
                          AppStringKeys.aiNoProvider.l10n(context),
                      leading: const SettingsIconTile(
                        icon: HeroAppIcons.server,
                        backgroundColor: Color(0xFF3478F6),
                      ),
                      onTap: settings.serverProviders.isEmpty
                          ? null
                          : () => _pickProvider(settings),
                      showChevron: settings.serverProviders.isNotEmpty,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (provider != null)
                  _modelDiscoveryCard(context, settings, provider)
                else
                  _inputField(
                    context,
                    controller: _model,
                    icon: HeroAppIcons.cube,
                    label: AppStringKeys.aiServerModel.l10n(context),
                    hint: AppStringKeys.aiServerModelHint.l10n(context),
                  ),
                const SizedBox(height: AppSpacing.sm),
                _inputField(
                  context,
                  controller: _contextWindow,
                  icon: HeroAppIcons.tokenStack,
                  label: AppStringKeys.aiContextWindow.l10n(context),
                  hint: '${AiModelProfile.defaultContextWindowTokens}',
                  keyboardType: TextInputType.number,
                ),
                _note(
                  context,
                  (_contextDetected
                          ? AppStringKeys.aiContextDetected
                          : AppStringKeys.aiContextManual)
                      .l10n(context),
                ),
                const SizedBox(height: AppSpacing.lg),
                _inputField(
                  context,
                  controller: _testPrompt,
                  icon: HeroAppIcons.message,
                  label: AppStringKeys.aiTestPrompt.l10n(context),
                  hint: AppStringKeys.aiTestPromptHint.l10n(context),
                ),
                const SizedBox(height: AppSpacing.sm),
                _actionButton(
                  context,
                  label: AppStringKeys.aiTestModel.l10n(context),
                  saving: _testingModel,
                  onTap: provider == null ? null : () => _testModel(settings),
                  backgroundColor: c.card,
                  foregroundColor: provider == null
                      ? c.textTertiary
                      : AppTheme.brand,
                  borderColor: c.divider,
                ),
                if (_testResponse case final response?) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _modelTestResponse(context, response, failed: _testFailed),
                ],
                const SizedBox(height: AppSpacing.lg),
                _actionButton(
                  context,
                  label: AppStringKeys.aiSaveModel.l10n(context),
                  saving: _saving,
                  onTap: _save,
                ),
                if (widget.profile != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _actionButton(
                    context,
                    label: AppStringKeys.aiDeleteModel.l10n(context),
                    saving: _saving,
                    onTap: _delete,
                    backgroundColor: const Color(0xFFDC3C3C),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickProvider(AiSettingsController settings) async {
    final selected = await showModalBottomSheet<AiServerProvider>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _PickerCard(
        children: [
          for (final provider in settings.serverProviders)
            _pickerRow(
              sheetContext,
              icon: HeroAppIcons.server,
              color: const Color(0xFF3478F6),
              title: provider.name,
              value: provider.endpoint,
              selected: provider.id == _providerId,
              onTap: () => Navigator.of(sheetContext).pop(provider),
            ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    final providerChanged = selected.id != _providerId;
    setState(() {
      _providerId = selected.id;
      _modelsLoadFailed = false;
      _manualModelEntry = false;
      if (providerChanged) {
        _model.clear();
        _contextWindow.text = '${AiModelProfile.defaultContextWindowTokens}';
        _contextDetected = false;
      }
    });
    _autoDiscoveryProviderId = selected.id;
    unawaited(_loadModels(settings));
  }

  Widget _modelDiscoveryCard(
    BuildContext context,
    AiSettingsController settings,
    AiServerProvider provider,
  ) {
    final models = provider.availableModels;
    final hasDiscoveryRow =
        models.isNotEmpty || _loadingModels || _modelsLoadFailed;
    return Column(
      key: const ValueKey('aiModelDiscoveryCard'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsCard(
          children: [
            if (models.isNotEmpty)
              SettingsRow(
                key: const ValueKey('aiDiscoveredModelSelector'),
                title: AppStringKeys.aiServerModel.l10n(context),
                value: _model.text.trim().isEmpty
                    ? AppStringKeys.aiServerModelHint.l10n(context)
                    : _model.text.trim(),
                leading: const SettingsIconTile(
                  icon: HeroAppIcons.cube,
                  backgroundColor: Color(0xFF7467F0),
                ),
                onTap: () => _pickAvailableModel(settings, provider),
              ),
            if (models.isNotEmpty && (_loadingModels || _modelsLoadFailed))
              const InsetDivider(leadingInset: 56),
            if (_loadingModels)
              SettingsRow(
                key: const ValueKey('aiModelDiscoveryLoading'),
                title: AppStringKeys.aiModels.l10n(context),
                value: provider.name,
                leading: const SettingsIconTile(
                  icon: HeroAppIcons.arrowsRotate,
                  backgroundColor: Color(0xFF3478F6),
                ),
                trailing: const AppActivityIndicator(size: 17),
                showChevron: false,
              )
            else if (_modelsLoadFailed)
              _modelDiscoveryErrorRow(context, settings),
            if (hasDiscoveryRow) const InsetDivider(leadingInset: 56),
            SettingsRow(
              key: const ValueKey('aiEnterModelManually'),
              title: AppStringKeys.aiEnterModelManually.l10n(context),
              leading: const SettingsIconTile(
                icon: HeroAppIcons.penToSquare,
                backgroundColor: Color(0xFF8E7BFF),
              ),
              onTap: () =>
                  setState(() => _manualModelEntry = !_manualModelEntry),
              trailing: AppIcon(
                _manualModelEntry
                    ? HeroAppIcons.chevronUp
                    : HeroAppIcons.chevronDown,
                size: AppIconSize.chevron,
                color: context.colors.textTertiary,
              ),
              showChevron: false,
            ),
          ],
        ),
        if (_manualModelEntry) ...[
          const SizedBox(height: AppSpacing.sm),
          _inputField(
            context,
            controller: _model,
            icon: HeroAppIcons.cube,
            label: AppStringKeys.aiServerModel.l10n(context),
            hint: AppStringKeys.aiServerModelHint.l10n(context),
          ),
        ],
      ],
    );
  }

  Widget _modelDiscoveryErrorRow(
    BuildContext context,
    AiSettingsController settings,
  ) {
    final c = context.colors;
    return GestureDetector(
      key: const ValueKey('aiModelDiscoveryError'),
      behavior: HitTestBehavior.opaque,
      onTap: () => unawaited(_loadModels(settings)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppMetric.settingsLeadingInset,
          AppSpacing.sm,
          AppMetric.settingsTrailingInset,
          AppSpacing.sm,
        ),
        child: Row(
          children: [
            const SettingsIconTile(
              icon: HeroAppIcons.triangleExclamation,
              backgroundColor: Color(0xFFDC3C3C),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                AppStringKeys.aiModelsFailed.l10n(context),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.footnote(c.textSecondary),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppIcon(
              HeroAppIcons.arrowsRotate,
              size: AppIconSize.md,
              color: AppTheme.brand,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAvailableModel(
    AiSettingsController settings,
    AiServerProvider provider,
  ) async {
    final selected = await _pickDiscoveredModel(provider.availableModels);
    if (selected == null || !mounted) return;
    await _applyDiscoveredModel(settings, provider, selected);
  }

  Future<void> _loadModels(AiSettingsController settings) async {
    final providerId = _providerId;
    if (providerId == null) return;
    final generation = ++_discoveryGeneration;
    setState(() {
      _loadingModels = true;
      _modelsLoadFailed = false;
    });
    try {
      final models = await settings.refreshModelsForProvider(providerId);
      if (!mounted || generation != _discoveryGeneration) return;
      final currentModel = _model.text.trim();
      final selected = models
          .where((model) => model.id == currentModel)
          .firstOrNull;
      setState(() {
        _loadingModels = false;
        _modelsLoadFailed = false;
        _manualModelEntry =
            models.isEmpty || (currentModel.isNotEmpty && selected == null);
        final contextTokens = selected?.contextWindowTokens;
        if (contextTokens != null) {
          _contextWindow.text = '$contextTokens';
          _contextDetected = true;
        }
      });
    } on Object {
      if (!mounted || generation != _discoveryGeneration) return;
      setState(() {
        _loadingModels = false;
        _modelsLoadFailed = true;
        if (_model.text.trim().isEmpty) _manualModelEntry = true;
      });
    } finally {
      if (mounted && generation == _discoveryGeneration && _loadingModels) {
        setState(() => _loadingModels = false);
      }
    }
  }

  Future<OpenAiCompatibleModelInfo?> _pickDiscoveredModel(
    List<OpenAiCompatibleModelInfo> models,
  ) => showModalBottomSheet<OpenAiCompatibleModelInfo>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _PickerCard(
      children: [
        for (final model in models)
          _pickerRow(
            sheetContext,
            icon: HeroAppIcons.cube,
            color: const Color(0xFF7467F0),
            title: model.id,
            value: model.contextWindowTokens == null
                ? ''
                : '${model.contextWindowTokens! ~/ 1024}K',
            selected: model.id == _model.text.trim(),
            onTap: () => Navigator.of(sheetContext).pop(model),
          ),
      ],
    ),
  );

  Future<void> _applyDiscoveredModel(
    AiSettingsController settings,
    AiServerProvider provider,
    OpenAiCompatibleModelInfo selected,
  ) async {
    var details = selected;
    if (selected.contextWindowTokens == null) {
      try {
        details =
            await settings.discoverModelDetails(
              endpoint: provider.endpoint,
              apiKey: settings.apiKeyForServerProvider(provider.id),
              model: selected.id,
            ) ??
            selected;
      } on Object {
        details = selected;
      }
    }
    if (!mounted) return;
    setState(() {
      _manualModelEntry = false;
      _model.text = details.id;
      final contextTokens = details.contextWindowTokens;
      if (contextTokens != null) _contextWindow.text = '$contextTokens';
      _contextDetected = contextTokens != null;
    });
  }

  Future<void> _testModel(AiSettingsController settings) async {
    final providerId = _providerId;
    final model = _model.text.trim();
    final prompt = _testPrompt.text.trim();
    if (providerId == null || model.isEmpty || prompt.isEmpty) {
      showToast(context, AppStringKeys.aiInvalidModel.l10n(context));
      return;
    }
    setState(() {
      _testingModel = true;
      _testResponse = null;
      _testFailed = false;
    });
    try {
      final response = await settings.testServerModel(
        providerId: providerId,
        model: model,
        prompt: prompt,
      );
      if (!mounted) return;
      setState(() => _testResponse = response);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _testFailed = true;
        _testResponse = error.toString();
      });
    } finally {
      if (mounted) setState(() => _testingModel = false);
    }
  }

  Future<void> _save() async {
    final providerId = _providerId;
    final contextWindow = int.tryParse(_contextWindow.text.trim());
    if (providerId == null || contextWindow == null) {
      showToast(context, AppStringKeys.aiInvalidModel.l10n(context));
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<AiSettingsController>().saveModelProfile(
        id: widget.profile?.id,
        providerId: providerId,
        model: _model.text,
        contextWindowTokens: contextWindow,
        contextWindowDetected: _contextDetected,
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

  Future<void> _delete() async {
    final profile = widget.profile;
    if (profile == null || _saving) return;
    setState(() => _saving = true);
    await context.read<AiSettingsController>().deleteModelProfile(profile.id);
    if (mounted) Navigator.of(context).pop();
  }
}

Future<void> _showFeatureModelPicker(
  BuildContext context, {
  required AiSettingsController settings,
  required AiFeature feature,
}) async {
  final selectedId = feature == AiFeature.translation
      ? settings.translationModelCandidateId
      : settings.summaryModelCandidateId;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _PickerCard(
      children: [
        for (final candidate in settings.modelCandidates)
          _pickerRow(
            sheetContext,
            icon: _candidateIcon(candidate),
            color: _candidateColor(candidate),
            title: _candidateLabel(sheetContext, candidate),
            value: _candidateDetail(sheetContext, settings, candidate),
            selected: candidate.id == selectedId,
            onTap: () async {
              await settings.setFeatureModelCandidate(feature, candidate.id);
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
            },
          ),
      ],
    ),
  );
}

class _PickerCard extends StatelessWidget {
  const _PickerCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: children.length,
          separatorBuilder: (_, _) => const InsetDivider(leadingInset: 56),
          itemBuilder: (_, index) => children[index],
        ),
      ),
    );
  }
}

Widget _pickerRow(
  BuildContext context, {
  required AppIconData icon,
  required Color color,
  required String title,
  required String value,
  required bool selected,
  required VoidCallback onTap,
}) {
  final c = context.colors;
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 62),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            SettingsIconTile(icon: icon, backgroundColor: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.body(c.textPrimary),
                  ),
                  if (value.isNotEmpty)
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.caption(c.textSecondary),
                    ),
                ],
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

String _candidateLabel(BuildContext context, AiModelCandidate candidate) =>
    switch (candidate.kind) {
      AiModelCandidateKind.applePcc => AppStringKeys.aiProviderApplePcc.l10n(
        context,
      ),
      AiModelCandidateKind.appleOnDevice =>
        AppStringKeys.aiProviderAppleOnDevice.l10n(context),
      AiModelCandidateKind.server => candidate.model,
    };

String _candidateDetail(
  BuildContext context,
  AiSettingsController settings,
  AiModelCandidate candidate,
) => switch (candidate.kind) {
  AiModelCandidateKind.applePcc => _appleCandidateDetail(
    context,
    available:
        settings.pccCapabilities?.available == true &&
        settings.pccCapabilities?.quotaLimitReached != true,
    contextWindowTokens: settings.pccCapabilities?.contextSize,
  ),
  AiModelCandidateKind.appleOnDevice => _appleCandidateDetail(
    context,
    available: settings.pccCapabilities?.onDeviceAvailable == true,
    contextWindowTokens: settings.pccCapabilities?.onDeviceContextSize,
  ),
  AiModelCandidateKind.server =>
    '${candidate.serverProvider?.name ?? ''} · ${(candidate.contextWindowTokens ?? 0) ~/ 1024}K',
};

String _appleCandidateDetail(
  BuildContext context, {
  required bool available,
  required int? contextWindowTokens,
}) {
  final availability =
      (available
              ? AppStringKeys.aiPccAvailable
              : AppStringKeys.aiPccUnavailable)
          .l10n(context);
  if (contextWindowTokens == null || contextWindowTokens <= 0) {
    return availability;
  }
  return '$availability · ${contextWindowTokens ~/ 1024}K';
}

AppIconData _candidateIcon(AiModelCandidate candidate) =>
    switch (candidate.kind) {
      AiModelCandidateKind.applePcc => HeroAppIcons.cloud,
      AiModelCandidateKind.appleOnDevice => HeroAppIcons.cpuChip,
      AiModelCandidateKind.server => HeroAppIcons.cube,
    };

Color _candidateColor(AiModelCandidate candidate) => switch (candidate.kind) {
  AiModelCandidateKind.applePcc => const Color(0xFF7467F0),
  AiModelCandidateKind.appleOnDevice => const Color(0xFF16A085),
  AiModelCandidateKind.server => const Color(0xFF3478F6),
};

Future<T?> _push<T>(BuildContext context, Widget view) =>
    Navigator.of(context).push<T>(MaterialPageRoute<T>(builder: (_) => view));

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
  required VoidCallback? onTap,
  Color? backgroundColor,
  Color? foregroundColor,
  Color? borderColor,
}) => Semantics(
  button: true,
  enabled: !saving && onTap != null,
  child: GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: saving ? null : onTap,
    child: AnimatedOpacity(
      duration: const Duration(milliseconds: 140),
      opacity: saving || onTap == null ? 0.55 : 1,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: backgroundColor ?? AppTheme.brand,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: borderColor == null ? null : Border.all(color: borderColor),
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

Widget _modelTestResponse(
  BuildContext context,
  String response, {
  required bool failed,
}) {
  final c = context.colors;
  final accent = failed ? const Color(0xFFDC3C3C) : const Color(0xFF16A085);
  final title =
      (failed ? AppStringKeys.aiTestFailed : AppStringKeys.aiTestResponse).l10n(
        context,
      );
  return Semantics(
    liveRegion: true,
    label: title,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(
            failed ? HeroAppIcons.circleXmark : HeroAppIcons.circleCheck,
            size: 20,
            color: accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyle.caption(accent)),
                const SizedBox(height: 5),
                SelectableText(
                  response,
                  style: AppTextStyle.body(c.textPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _sectionTitle(BuildContext context, String title) => Padding(
  padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.sm),
  child: Text(title, style: AppTextStyle.caption(context.colors.textTertiary)),
);

Widget _note(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.fromLTRB(4, AppSpacing.sm, 4, 0),
  child: Text(text, style: AppTextStyle.footnote(context.colors.textSecondary)),
);
