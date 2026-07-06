//
//  translation_settings_view.dart
//
//  翻译 settings: provider and target language preferences.
//

import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../l10n/telegram_language_controller.dart';
import '../theme/app_theme.dart';
import 'translation_api.dart';
import 'translation_controller.dart';

class TranslationSettingsView extends StatefulWidget {
  const TranslationSettingsView({super.key});

  @override
  State<TranslationSettingsView> createState() =>
      _TranslationSettingsViewState();
}

class _TranslationSettingsViewState extends State<TranslationSettingsView> {
  late final Future<Set<TranslationProvider>> _availableProvidersFuture =
      NativeTranslationApi.availableProviders();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final translation = context.watch<TranslationController>();
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
                    icon: HeroAppIcons.language.data,
                    title: AppStrings.t(AppStringKeys.translationSettingsTitle),
                    value: translation.enabled,
                    onChanged: (v) => translation.enabled = v,
                  ),
                ]),
                const SizedBox(height: 14),
                _card(context, [
                  _navRow(
                    context,
                    icon: HeroAppIcons.networkWired.data,
                    title: AppStrings.t(
                      AppStringKeys.translationSettingsService,
                    ),
                    trailing: translation.providerLabel,
                    onTap: () => _showProviderPicker(context),
                  ),
                  const InsetDivider(leadingInset: 56),
                  _navRow(
                    context,
                    icon: HeroAppIcons.globe.data,
                    title: AppStrings.t(
                      AppStringKeys.translationSettingsTargetLanguage,
                    ),
                    trailing: translation.targetLanguageLabel,
                    onTap: () => _showTargetPicker(context),
                  ),
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
                                HeroAppIcons.networkWired.data,
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
                            HeroAppIcons.globe.data,
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

  Widget _card(BuildContext context, List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(12),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );

  Widget _switchRow(
    BuildContext context, {
    required IconData icon,
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
            Text(
              title.l10n(context),
              style: TextStyle(fontSize: 16, color: c.textPrimary),
            ),
            const Spacer(),
            CupertinoSwitch(
              value: value,
              activeTrackColor: AppTheme.brand,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _navRow(
    BuildContext context, {
    required IconData icon,
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

  Widget _iconBadge(BuildContext context, IconData icon, Color color) =>
      Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Icon(icon, size: 15, color: Colors.white),
      );
}
