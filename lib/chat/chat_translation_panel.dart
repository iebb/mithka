import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

class ChatTranslationPanel extends StatelessWidget {
  const ChatTranslationPanel({
    super.key,
    required this.active,
    required this.targetLanguageLabel,
    required this.isTranslating,
    required this.onToggle,
    required this.onChooseLanguage,
    required this.onDismiss,
  });

  final bool active;
  final String targetLanguageLabel;
  final bool isTranslating;
  final VoidCallback onToggle;
  final VoidCallback onChooseLanguage;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = active
        ? AppStringKeys.chatTranslationShowOriginal.l10n(context)
        : AppStrings.t(AppStringKeys.chatTranslationTranslateTo, {
            'value1': targetLanguageLabel,
          });
    return Container(
      key: const ValueKey('chat-translation-panel'),
      height: 40,
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(top: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              key: const ValueKey('chat-translation-toggle'),
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 8, 0),
                child: Row(
                  children: [
                    if (isTranslating)
                      AppActivityIndicator(size: 16, color: AppTheme.brand)
                    else
                      AppIcon(
                        HeroAppIcons.language,
                        size: 18,
                        color: AppTheme.brand,
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppTheme.brand,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _PanelButton(
            key: const ValueKey('chat-translation-language'),
            icon: HeroAppIcons.ellipsis,
            color: c.textSecondary,
            onTap: onChooseLanguage,
          ),
          _PanelButton(
            key: const ValueKey('chat-translation-dismiss'),
            icon: HeroAppIcons.xmark,
            color: c.textSecondary,
            onTap: onDismiss,
          ),
        ],
      ),
    );
  }
}

class _PanelButton extends StatelessWidget {
  const _PanelButton({
    super.key,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final AppIconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: SizedBox(
      width: 42,
      height: 40,
      child: Center(child: AppIcon(icon, size: 18, color: color)),
    ),
  );
}
