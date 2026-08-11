//
//  translation_settings_view.dart
//
//  翻译 settings: provider and target language preferences.
//

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../components/app_icons.dart';
import '../components/settings_selection_row.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'ai_settings_controller.dart';
import 'ai_translation_prompt.dart';
import 'translation_api.dart';
import 'translation_controller.dart';

class TranslationSettingsView extends StatefulWidget {
  const TranslationSettingsView({super.key});

  @override
  State<TranslationSettingsView> createState() =>
      _TranslationSettingsViewState();
}

class _AiTranslationPromptEditorView extends StatefulWidget {
  const _AiTranslationPromptEditorView({required this.translation});

  final TranslationController translation;

  @override
  State<_AiTranslationPromptEditorView> createState() =>
      _AiTranslationPromptEditorViewState();
}

class _AiTranslationPromptEditorViewState
    extends State<_AiTranslationPromptEditorView> {
  late final TextEditingController _prompt;

  @override
  void initState() {
    super.initState();
    _prompt = TextEditingController(
      text: widget.translation.aiTranslationPrompt,
    );
  }

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SettingsPageScaffold(
      title: AppStringKeys.translationSettingsAiPrompt.l10n(context),
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        children: [
          Text(
            AppStringKeys.translationSettingsAiPromptDescription.l10n(context),
            style: AppTextStyle.footnote(c.textSecondary).copyWith(height: 1.4),
          ),
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            textField: true,
            label: AppStringKeys.translationSettingsAiPrompt.l10n(context),
            child: SettingsPanel(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 300),
                child: TextField(
                  key: const ValueKey('aiTranslationPromptField'),
                  controller: _prompt,
                  minLines: 14,
                  maxLines: null,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                  cursorColor: AppTheme.brand,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                    hintText: defaultAiTranslationPrompt.trim(),
                    hintStyle: TextStyle(
                      color: c.textTertiary,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _actionButton(
            label: AppStringKeys.translationSettingsAiPromptSave.l10n(context),
            onTap: _save,
          ),
          const SizedBox(height: AppSpacing.sm),
          _actionButton(
            label: AppStringKeys.translationSettingsAiPromptReset.l10n(context),
            onTap: () => setState(
              () => _prompt.text = defaultAiTranslationPrompt.trim(),
            ),
            backgroundColor: c.card,
            foregroundColor: AppTheme.brand,
            borderColor: AppTheme.brand,
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required VoidCallback onTap,
    Color? backgroundColor,
    Color? foregroundColor,
    Color? borderColor,
  }) => Semantics(
    button: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: backgroundColor ?? AppTheme.brand,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: borderColor == null ? null : Border.all(color: borderColor),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: foregroundColor ?? const Color(0xFFFFFFFF),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );

  void _save() {
    if (_prompt.text.trim().isEmpty) {
      showToast(
        context,
        AppStringKeys.translationSettingsAiPromptEmpty.l10n(context),
      );
      return;
    }
    widget.translation.setAiTranslationPrompt(_prompt.text);
    Navigator.of(context).pop();
  }
}

class _TranslationOptionDescriptor {
  const _TranslationOptionDescriptor({
    required this.id,
    required this.title,
    required this.icon,
    required this.available,
    this.subtitle,
  });

  final String id;
  final String title;
  final String? subtitle;
  final AppIconData icon;
  final bool available;
}

class _TranslationSettingsViewState extends State<TranslationSettingsView> {
  late final Future<Set<TranslationProvider>> _availableProvidersFuture =
      NativeTranslationApi.availableProviders();

  @override
  Widget build(BuildContext context) {
    final translation = context.watch<TranslationController>();
    final ai = context.watch<AiSettingsController>();
    return SettingsPageScaffold(
      title: AppStrings.t(AppStringKeys.messageActionTranslate),
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        children: [
          SettingsSection(
            rows: [
              SettingsSwitchRow(
                leading: const SettingsLeadingIcon(icon: HeroAppIcons.language),
                title: AppStrings.t(
                  AppStringKeys.translationSettingsShowTranslateButton,
                ),
                value: translation.enabled,
                onChanged: (value) => translation.enabled = value,
              ),
              SettingsSwitchRow(
                leading: const SettingsLeadingIcon(icon: HeroAppIcons.comments),
                title: AppStrings.t(
                  AppStringKeys.translationSettingsTranslateChats,
                ),
                value: translation.translateChats,
                onChanged: (value) => translation.translateChats = value,
              ),
              SettingsSelectionRow<TranslationDisplayStyle>(
                menuKey: const ValueKey('translation-display-style-menu'),
                leading: const SettingsLeadingIcon(
                  icon: HeroAppIcons.quoteLeft,
                ),
                title: AppStringKeys.translationSettingsDisplayStyle,
                value: translation.displayStyleLabel,
                options: [
                  for (final style in TranslationDisplayStyle.values)
                    SettingsSelectionOption(
                      id: 'translation-display-style-${style.name}',
                      value: style,
                      label: style.label,
                      icon: HeroAppIcons.quoteLeft,
                    ),
                ],
                isSelected: (style) => translation.displayStyle == style,
                onSelected: (style) => translation.displayStyle = style,
              ),
              SettingsSelectionRow<TranslationLanguage>(
                menuKey: const ValueKey('translation-target-language-menu'),
                leading: const SettingsLeadingIcon(icon: HeroAppIcons.globe),
                title: AppStrings.t(
                  AppStringKeys.translationSettingsTargetLanguage,
                ),
                value: translation.targetLanguageLabel,
                options: [
                  for (final language in TranslationController.targetLanguages)
                    SettingsSelectionOption(
                      id: 'translation-target-language-${language.code}',
                      value: language,
                      label: language.label,
                      icon: HeroAppIcons.globe,
                    ),
                ],
                isSelected: (language) =>
                    translation.targetLanguageCode == language.code,
                onSelected: (language) =>
                    translation.targetLanguageCode = language.code,
              ),
              if (translation.enabled || translation.translateChats)
                SettingsSelectionRow<TranslationLanguage>(
                  menuKey: const ValueKey('translation-ignored-languages-menu'),
                  leading: const SettingsLeadingIcon(icon: HeroAppIcons.ban),
                  title: AppStrings.t(
                    AppStringKeys.translationSettingsDoNotTranslate,
                  ),
                  value: _ignoredLanguagesSummary(translation),
                  menuTitle: AppStringKeys.translationSettingsDoNotTranslate,
                  dismissOnSelect: false,
                  options: [
                    for (final language
                        in TranslationController.targetLanguages)
                      SettingsSelectionOption(
                        id: 'translation-ignored-language-${language.code}',
                        value: language,
                        label: language.label,
                        icon: HeroAppIcons.ban,
                      ),
                  ],
                  isSelected: (language) {
                    final normalized =
                        TranslationController.normalizeLanguageCode(
                          language.code,
                        );
                    return normalized != null &&
                        translation.ignoredLanguageCodes.contains(normalized);
                  },
                  onSelected: (language) {
                    final normalized =
                        TranslationController.normalizeLanguageCode(
                          language.code,
                        );
                    if (normalized == null) return;
                    translation.setIgnoredLanguage(
                      language.code,
                      !translation.ignoredLanguageCodes.contains(normalized),
                    );
                  },
                ),
              SettingsRow(
                leading: const SettingsLeadingIcon(
                  icon: HeroAppIcons.penToSquare,
                ),
                title: AppStringKeys.translationSettingsAiPrompt.l10n(context),
                value:
                    (translation.hasCustomAiTranslationPrompt
                            ? AppStringKeys.translationSettingsAiPromptCustom
                            : AppStringKeys.translationSettingsAiPromptDefault)
                        .l10n(context),
                onTap: () => Navigator.of(context).push(
                  AppPageRoute<void>(
                    pageBuilder: (_, _, _) => _AiTranslationPromptEditorView(
                      translation: translation,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SettingsSectionHeader(
            AppStringKeys.translationSettingsOptionsSection,
          ),
          FutureBuilder<Set<TranslationProvider>>(
            future: _availableProvidersFuture,
            builder: (context, snapshot) => _translationOptionsPanel(
              context,
              translation,
              ai,
              snapshot.data ?? const <TranslationProvider>{},
            ),
          ),
          SettingsNote(
            key: const ValueKey('translation-fallback-description'),
            text: AppStringKeys.translationSettingsFallbackDescription.l10n(
              context,
            ),
          ),
        ],
      ),
    );
  }

  Widget _translationOptionsPanel(
    BuildContext context,
    TranslationController translation,
    AiSettingsController ai,
    Set<TranslationProvider> nativeProviders,
  ) {
    final options = _translationOptions(
      context,
      translation,
      ai,
      nativeProviders,
    );
    return SettingsPanel(
      clipBehavior: Clip.antiAlias,
      child: ReorderableListView.builder(
        key: const ValueKey('translation-options-list'),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: options.length,
        onReorderItem: (oldIndex, newIndex) =>
            translation.reorderTranslationOptions(
              options.map((option) => option.id).toList(growable: false),
              oldIndex,
              newIndex,
            ),
        itemBuilder: (context, index) {
          final option = options[index];
          return Column(
            key: ValueKey('translation-option-${option.id}'),
            children: [
              _translationOptionRow(context, translation, option, index),
              if (index < options.length - 1) const SettingsDivider.text(),
            ],
          );
        },
      ),
    );
  }

  List<_TranslationOptionDescriptor> _translationOptions(
    BuildContext context,
    TranslationController translation,
    AiSettingsController ai,
    Set<TranslationProvider> nativeProviders,
  ) {
    _TranslationOptionDescriptor provider(
      TranslationProvider value,
      AppIconData icon, {
      bool available = true,
    }) => _TranslationOptionDescriptor(
      id: TranslationOptionIds.provider(value),
      title: value.label.l10n(context),
      icon: icon,
      available: available,
      subtitle: available
          ? null
          : AppStringKeys.translationSettingsOptionUnavailable.l10n(context),
    );

    final all = <_TranslationOptionDescriptor>[
      provider(TranslationProvider.tdlib, HeroAppIcons.paperPlane),
      for (final candidate in ai.modelCandidatesForFeature(
        AiFeature.translation,
      ))
        _aiTranslationOption(context, ai, candidate),
      for (final native in nativeProviders)
        provider(native, HeroAppIcons.cpuChip),
      provider(TranslationProvider.myMemory, HeroAppIcons.globe),
      provider(TranslationProvider.lingva, HeroAppIcons.globe),
      provider(
        TranslationProvider.libreTranslate,
        HeroAppIcons.server,
        available: translation.libreTranslateEndpoint.isNotEmpty,
      ),
    ];
    final byId = {for (final option in all) option.id: option};
    return translation
        .orderedTranslationOptions(byId.keys)
        .map((id) => byId[id]!)
        .toList(growable: false);
  }

  _TranslationOptionDescriptor _aiTranslationOption(
    BuildContext context,
    AiSettingsController ai,
    AiModelCandidate candidate,
  ) {
    final available = ai.isConfiguredCandidate(candidate);
    final title = _aiModelLabel(context, candidate);
    final providerName = candidate.serverProvider?.name.trim() ?? '';
    return _TranslationOptionDescriptor(
      id: TranslationOptionIds.ai(candidate.id),
      title: title,
      subtitle: available
          ? (providerName.isEmpty ? null : providerName)
          : AppStringKeys.translationSettingsOptionUnavailable.l10n(context),
      icon: switch (candidate.kind) {
        AiModelCandidateKind.applePcc => HeroAppIcons.cloud,
        AiModelCandidateKind.appleOnDevice => HeroAppIcons.cpuChip,
        AiModelCandidateKind.server => HeroAppIcons.cube,
        AiModelCandidateKind.telegramCocoon => HeroAppIcons.wandMagicSparkles,
      },
      available: available,
    );
  }

  Widget _translationOptionRow(
    BuildContext context,
    TranslationController translation,
    _TranslationOptionDescriptor option,
    int index,
  ) {
    final colors = context.colors;
    final enabled = translation.isTranslationOptionEnabled(option.id);
    return SizedBox(
      height: option.subtitle == null ? 58 : 68,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: SizedBox(
                width: 30,
                height: 44,
                child: Center(
                  child: AppIcon(
                    HeroAppIcons.bars,
                    size: AppIconSize.lg,
                    color: colors.textTertiary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            AppIcon(
              option.icon,
              size: AppIconSize.lg,
              color: option.available
                  ? colors.textSecondary
                  : colors.textTertiary,
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: option.available
                          ? colors.textPrimary
                          : colors.textTertiary,
                      fontSize: AppTextSize.body,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (option.subtitle case final subtitle?) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.footnote(colors.textTertiary),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            AppSwitch(
              key: ValueKey('translation-option-switch-${option.id}'),
              value: enabled,
              enabled: option.available,
              semanticLabel: option.title,
              onChanged: (value) =>
                  translation.setTranslationOptionEnabled(option.id, value),
            ),
          ],
        ),
      ),
    );
  }

  String _ignoredLanguagesSummary(TranslationController translation) {
    final ignored = translation.ignoredLanguageCodes;
    if (ignored.isEmpty) {
      return AppStrings.t(AppStringKeys.translationSettingsNone);
    }
    if (ignored.length == 1) {
      final code = ignored.single;
      final language = TranslationController.targetLanguages.firstWhere(
        (language) =>
            TranslationController.normalizeLanguageCode(language.code) == code,
        orElse: () => TranslationLanguage(code, code.toUpperCase()),
      );
      return language.label;
    }
    return AppStrings.t(AppStringKeys.translationSettingsLanguageCount, {
      'value1': ignored.length,
    });
  }

  String _aiModelLabel(BuildContext context, AiModelCandidate candidate) =>
      switch (candidate.kind) {
        AiModelCandidateKind.applePcc => AppStringKeys.aiProviderApplePcc.l10n(
          context,
        ),
        AiModelCandidateKind.appleOnDevice =>
          AppStringKeys.aiProviderAppleOnDevice.l10n(context),
        AiModelCandidateKind.server => candidate.model,
        AiModelCandidateKind.telegramCocoon =>
          AppStringKeys.aiProviderTelegramCocoon.l10n(context),
      };
}
