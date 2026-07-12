import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../l10n/app_locale_controller.dart';
import '../l10n/app_localizations.dart';
import '../l10n/telegram_language_controller.dart';
import '../theme/app_theme.dart';
import 'translation_settings_view.dart';

class LanguageSettingsView extends StatelessWidget {
  const LanguageSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final locale = context.watch<AppLocaleController>();
    final telegramLanguage = context.watch<TelegramLanguageController>();
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.languageTitle),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
              children: [
                SettingsCard(
                  children: [
                    _NavLanguageRow(
                      icon: HeroAppIcons.language,
                      title: AppStringKeys.languageMithkaLanguage.l10n(context),
                      subtitle: locale.selectedLabel(context),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MithkaLanguageSettingsView(),
                        ),
                      ),
                    ),
                    const InsetDivider(leadingInset: 56),
                    _NavLanguageRow(
                      icon: HeroAppIcons.globe,
                      title: AppStringKeys.languageTelegramLanguage.l10n(
                        context,
                      ),
                      subtitle: _telegramSummary(
                        context,
                        telegramLanguage,
                        fallbackName: locale.selectedLabel(context),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const TelegramLanguageSettingsView(),
                        ),
                      ),
                    ),
                    const InsetDivider(leadingInset: 56),
                    _NavLanguageRow(
                      icon: HeroAppIcons.language,
                      title: telegramText(AppStringKeys.messageActionTranslate),
                      subtitle: AppStrings.t(
                        AppStringKeys.translationSettingsTitle,
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const TranslationSettingsView(),
                        ),
                      ),
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
}

class MithkaLanguageSettingsView extends StatelessWidget {
  const MithkaLanguageSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final locale = context.watch<AppLocaleController>();
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStringKeys.languageMithkaLanguage.l10n(context),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
              children: [
                SettingsCard(
                  children: [
                    _LanguageRow(
                      title: AppStringKeys.appLocaleFollowSystem.l10n(context),
                      selected: locale.followsSystem,
                      onTap: () => locale.locale = null,
                    ),
                    const InsetDivider(leadingInset: 16),
                    for (final option in AppLocaleController.options) ...[
                      _LanguageRow(
                        title: option.label.l10n(context),
                        selected:
                            !locale.followsSystem &&
                            option.tag == locale.locale!.toLanguageTag(),
                        onTap: () => locale.locale = option.locale,
                      ),
                      if (option != AppLocaleController.options.last)
                        const InsetDivider(leadingInset: 16),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TelegramLanguageSettingsView extends StatelessWidget {
  const TelegramLanguageSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final locale = context.watch<AppLocaleController>();
    final telegramLanguage = context.watch<TelegramLanguageController>();
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStringKeys.languageTelegramLanguage.l10n(context),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
              children: [
                SettingsCard(
                  children: [
                    _LanguageRow(
                      title: AppStringKeys.languageTelegramFollowMithka.l10n(
                        context,
                      ),
                      subtitle: _telegramUsing(
                        context,
                        telegramLanguage,
                        fallbackName: locale.selectedLabel(context),
                      ),
                      selected: telegramLanguage.followsAppLanguage,
                      onTap: () => telegramLanguage.setSelectedPack(null),
                    ),
                    if (telegramLanguage.packs.isNotEmpty)
                      const InsetDivider(leadingInset: 16),
                    for (final pack in telegramLanguage.packs) ...[
                      _LanguageRow(
                        title: pack.displayName,
                        subtitle: _packSubtitle(context, pack),
                        selected:
                            !telegramLanguage.followsAppLanguage &&
                            telegramLanguage.activePackId == pack.id,
                        onTap: () => telegramLanguage.setSelectedPack(pack.id),
                      ),
                      if (pack != telegramLanguage.packs.last)
                        const InsetDivider(leadingInset: 16),
                    ],
                    if (telegramLanguage.isLoading)
                      _StatusRow(
                        text: AppStringKeys.languageTelegramLoading.l10n(
                          context,
                        ),
                      ),
                    if (!telegramLanguage.isLoading &&
                        telegramLanguage.errorText != null)
                      _StatusRow(
                        text: AppStringKeys.languageTelegramLoadFailed.l10n(
                          context,
                        ),
                        isError: true,
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
}

String _telegramSummary(
  BuildContext context,
  TelegramLanguageController controller, {
  required String fallbackName,
}) {
  if (controller.followsAppLanguage) {
    final using = _telegramUsing(
      context,
      controller,
      fallbackName: fallbackName,
    );
    return using == null
        ? AppStringKeys.languageTelegramFollowMithka.l10n(context)
        : '${AppStringKeys.languageTelegramFollowMithka.l10n(context)} · $using';
  }
  return _activeTelegramPackName(controller) ?? fallbackName;
}

String? _telegramUsing(
  BuildContext context,
  TelegramLanguageController controller, {
  required String fallbackName,
}) {
  if (controller.activePackId == null) return null;
  final name = _activeTelegramPackName(controller) ?? fallbackName;
  return AppStringKeys.languageTelegramUsing
      .l10n(context)
      .replaceAll('{value1}', name);
}

String? _activeTelegramPackName(TelegramLanguageController controller) {
  return controller.packs
      .where((pack) => pack.id == controller.activePackId)
      .firstOrNull
      ?.displayName;
}

String? _packSubtitle(BuildContext context, TelegramLanguagePackOption pack) {
  final badges = <String>[];
  if (pack.isOfficial) {
    badges.add(AppStringKeys.languageTelegramOfficial.l10n(context));
  }
  if (pack.name.trim().isNotEmpty &&
      pack.name.trim() != pack.displayName.trim()) {
    badges.add(pack.name.trim());
  }
  return badges.isEmpty ? null : badges.join(' · ');
}

class _NavLanguageRow extends StatelessWidget {
  const _NavLanguageRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final AppIconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 58,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              AppIcon(icon, size: 22, color: AppTheme.brand),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, color: c.textPrimary),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 13, color: c.textTertiary),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              AppIcon(
                HeroAppIcons.chevronRight,
                size: 14,
                color: c.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.title,
    this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: subtitle == null ? 52 : 58,
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
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, color: c.textPrimary),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.textSecondary),
                      ),
                    ],
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
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.text, this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              color: isError ? AppTheme.tagRed : c.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
  }
}
