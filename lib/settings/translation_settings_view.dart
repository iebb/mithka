//
//  translation_settings_view.dart
//
//  翻译 settings: provider and target language preferences.
//

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/telegram_language_controller.dart';
import '../theme/app_theme.dart';
import 'ai_settings_controller.dart';
import 'ai_settings_view.dart';
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
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStringKeys.translationSettingsAiPrompt.l10n(context),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
              children: [
                Text(
                  AppStringKeys.translationSettingsAiPromptDescription.l10n(
                    context,
                  ),
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Semantics(
                  textField: true,
                  label: AppStringKeys.translationSettingsAiPrompt.l10n(
                    context,
                  ),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 300),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.divider, width: 0.5),
                    ),
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
                const SizedBox(height: 12),
                _actionButton(
                  label: AppStringKeys.translationSettingsAiPromptSave.l10n(
                    context,
                  ),
                  onTap: _save,
                ),
                const SizedBox(height: 8),
                _actionButton(
                  label: AppStringKeys.translationSettingsAiPromptReset.l10n(
                    context,
                  ),
                  onTap: () => setState(
                    () => _prompt.text = defaultAiTranslationPrompt.trim(),
                  ),
                  backgroundColor: c.card,
                  foregroundColor: AppTheme.brand,
                  borderColor: AppTheme.brand,
                ),
              ],
            ),
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
          borderRadius: BorderRadius.circular(12),
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

class _TranslationSettingsViewState extends State<TranslationSettingsView> {
  late final Future<Set<TranslationProvider>> _availableProvidersFuture =
      NativeTranslationApi.availableProviders();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final translation = context.watch<TranslationController>();
    final ai = context.watch<AiSettingsController>();
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: telegramText(AppStringKeys.messageActionTranslate),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
              children: [
                _card(context, [
                  _switchRow(
                    context,
                    icon: HeroAppIcons.language,
                    title: AppStrings.t(
                      AppStringKeys.translationSettingsShowTranslateButton,
                    ),
                    value: translation.enabled,
                    onChanged: (v) => translation.enabled = v,
                  ),
                  const InsetDivider(leadingInset: 56),
                  _switchRow(
                    context,
                    icon: HeroAppIcons.comments,
                    title: AppStrings.t(
                      AppStringKeys.translationSettingsTranslateChats,
                    ),
                    value: translation.translateChats,
                    onChanged: (v) => translation.translateChats = v,
                  ),
                ]),
                const SizedBox(height: 14),
                _sectionTitle(
                  context,
                  AppStringKeys.translationSettingsAiSection.l10n(context),
                ),
                _card(context, [
                  _switchRow(
                    context,
                    icon: HeroAppIcons.cpuChip,
                    title: AppStringKeys.translationSettingsAiEnabled.l10n(
                      context,
                    ),
                    value: translation.aiTranslationEnabled,
                    onChanged: (value) =>
                        translation.aiTranslationEnabled = value,
                  ),
                  const InsetDivider(leadingInset: 56),
                  _navRow(
                    context,
                    icon: switch (ai.translationModelCandidate.kind) {
                      AiModelCandidateKind.applePcc => HeroAppIcons.cloud,
                      AiModelCandidateKind.appleOnDevice =>
                        HeroAppIcons.cpuChip,
                      AiModelCandidateKind.server => HeroAppIcons.cube,
                      AiModelCandidateKind.telegramCocoon =>
                        HeroAppIcons.wandMagicSparkles,
                    },
                    title: AppStringKeys.aiTranslateUsing.l10n(context),
                    trailing: _aiModelLabel(
                      context,
                      ai.translationModelCandidate,
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AiSettingsView()),
                    ),
                  ),
                  const InsetDivider(leadingInset: 56),
                  _navRow(
                    context,
                    icon: HeroAppIcons.penToSquare,
                    title: AppStringKeys.translationSettingsAiPrompt.l10n(
                      context,
                    ),
                    trailing:
                        (translation.hasCustomAiTranslationPrompt
                                ? AppStringKeys
                                      .translationSettingsAiPromptCustom
                                : AppStringKeys
                                      .translationSettingsAiPromptDefault)
                            .l10n(context),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _AiTranslationPromptEditorView(
                          translation: translation,
                        ),
                      ),
                    ),
                  ),
                ]),
                _note(
                  context,
                  AppStringKeys.translationSettingsAiDescription.l10n(context),
                ),
                const SizedBox(height: 14),
                _sectionTitle(
                  context,
                  AppStringKeys.translationSettingsStandardSection.l10n(
                    context,
                  ),
                ),
                _card(context, [
                  _navRow(
                    context,
                    icon: HeroAppIcons.server,
                    title: AppStrings.t(
                      AppStringKeys.translationSettingsService,
                    ),
                    trailing: translation.providerLabel,
                    onTap: () => _showProviderPicker(context),
                  ),
                  const InsetDivider(leadingInset: 56),
                  _navRow(
                    context,
                    icon: HeroAppIcons.globe,
                    title: AppStrings.t(
                      AppStringKeys.translationSettingsTargetLanguage,
                    ),
                    trailing: translation.targetLanguageLabel,
                    onTap: () => _showTargetPicker(context),
                  ),
                  if (translation.enabled || translation.translateChats) ...[
                    const InsetDivider(leadingInset: 56),
                    _navRow(
                      context,
                      icon: HeroAppIcons.ban,
                      title: AppStrings.t(
                        AppStringKeys.translationSettingsDoNotTranslate,
                      ),
                      trailing: _ignoredLanguagesSummary(translation),
                      onTap: () => _showIgnoredLanguagesPicker(context),
                    ),
                  ],
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showProviderPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final c = context.colors;
        final translation = context.watch<TranslationController>();
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(14),
            ),
            clipBehavior: Clip.antiAlias,
            child: FutureBuilder<Set<TranslationProvider>>(
              future: _availableProvidersFuture,
              builder: (context, snapshot) {
                final nativeProviders =
                    snapshot.data ?? const <TranslationProvider>{};
                final providers = TranslationProvider.selectableProviders
                    .where(
                      (provider) =>
                          !provider.isNative ||
                          nativeProviders.contains(provider),
                    )
                    .toList();
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: providers.length,
                  separatorBuilder: (_, _) =>
                      const InsetDivider(leadingInset: 56),
                  itemBuilder: (context, i) {
                    final provider = providers[i];
                    final selected = translation.provider == provider;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        translation.provider = provider;
                        Navigator.of(context).pop();
                      },
                      child: SizedBox(
                        height: 52,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              _iconBadge(
                                context,
                                HeroAppIcons.server,
                                const Color(0xFF34A2DF),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  provider.label.l10n(context),
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: c.textPrimary,
                                  ),
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
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showTargetPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final c = context.colors;
        final translation = context.watch<TranslationController>();
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(14),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: TranslationController.targetLanguages.length,
              separatorBuilder: (_, _) => const InsetDivider(leadingInset: 56),
              itemBuilder: (context, i) {
                final language = TranslationController.targetLanguages[i];
                final selected =
                    translation.targetLanguageCode == language.code;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    translation.targetLanguageCode = language.code;
                    Navigator.of(context).pop();
                  },
                  child: SizedBox(
                    height: 52,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          _iconBadge(
                            context,
                            HeroAppIcons.globe,
                            const Color(0xFF34A2DF),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              language.label.l10n(context),
                              style: TextStyle(
                                fontSize: 16,
                                color: c.textPrimary,
                              ),
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

  void _showIgnoredLanguagesPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final c = context.colors;
        final translation = context.watch<TranslationController>();
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      AppStringKeys.translationSettingsDoNotTranslate.l10n(
                        context,
                      ),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                ),
                const InsetDivider(),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: TranslationController.targetLanguages.length,
                    separatorBuilder: (_, _) =>
                        const InsetDivider(leadingInset: 56),
                    itemBuilder: (context, i) {
                      final language = TranslationController.targetLanguages[i];
                      final normalized =
                          TranslationController.normalizeLanguageCode(
                            language.code,
                          );
                      final selected =
                          normalized != null &&
                          translation.ignoredLanguageCodes.contains(normalized);
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => translation.setIgnoredLanguage(
                          language.code,
                          !selected,
                        ),
                        child: SizedBox(
                          height: 52,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                _iconBadge(
                                  context,
                                  HeroAppIcons.ban,
                                  const Color(0xFF34A2DF),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    language.label.l10n(context),
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: c.textPrimary,
                                    ),
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
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _card(BuildContext context, List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(12),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );

  Widget _sectionTitle(BuildContext context, String title) => Padding(
    padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
    child: Text(
      title,
      style: TextStyle(
        color: context.colors.textTertiary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _note(BuildContext context, String text) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(4, 8, 4, 0),
    child: Text(
      text,
      style: TextStyle(
        color: context.colors.textTertiary,
        fontSize: 13,
        height: 1.35,
      ),
    ),
  );

  Widget _switchRow(
    BuildContext context, {
    required AppIconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final c = context.colors;
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _iconBadge(context, icon, const Color(0xFF34A2DF)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title.l10n(context),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, color: c.textPrimary),
              ),
            ),
            const SizedBox(width: 12),
            AppSwitch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }

  Widget _navRow(
    BuildContext context, {
    required AppIconData icon,
    required String title,
    required String trailing,
    required VoidCallback? onTap,
  }) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _iconBadge(context, icon, const Color(0xFF34A2DF)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title.l10n(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, color: c.textPrimary),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: math.min(MediaQuery.sizeOf(context).width * 0.42, 190),
                child: Text(
                  trailing.l10n(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 13, color: c.textTertiary),
                ),
              ),
              const SizedBox(width: 6),
              if (onTap != null)
                SizedBox(
                  width: 14,
                  child: AppIcon(
                    HeroAppIcons.chevronRight,
                    size: 14,
                    color: c.textTertiary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconBadge(BuildContext context, AppIconData icon, Color color) =>
      SettingsIconTile(icon: icon, backgroundColor: color);
}
