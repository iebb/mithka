import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// Persistent delivery-limit notice for group chats opened as a Bot API bot.
class BotApiAccessWarning extends StatelessWidget {
  const BotApiAccessWarning({
    super.key,
    required this.showPrivacyWarning,
    required this.showBotToBotWarning,
    this.onDismiss,
  });

  final bool showPrivacyWarning;
  final bool showBotToBotWarning;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF382E19) : const Color(0xFFFFF5D9);
    final border = dark ? const Color(0xFF8E6B28) : const Color(0xFFE7B343);
    final foreground = dark ? const Color(0xFFFFD47A) : const Color(0xFF76500A);
    final notices = <String>[
      if (showPrivacyWarning) AppStringKeys.botApiPrivacyWarning.l10n(context),
      if (showBotToBotWarning)
        AppStringKeys.botApiBotToBotWarning.l10n(context),
    ];
    if (notices.isEmpty) return const SizedBox.shrink();

    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        key: const ValueKey('botApiAccessWarning'),
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: background,
          border: Border(
            top: BorderSide(color: border, width: 0.5),
            bottom: BorderSide(color: border, width: 0.5),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: AppIcon(
                HeroAppIcons.triangleExclamation,
                size: 18,
                color: foreground,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                notices.join('\n'),
                style: AppTextStyle.footnote(
                  foreground,
                  weight: AppTextWeight.medium,
                ).copyWith(height: 1.35),
              ),
            ),
            if (onDismiss != null) ...[
              const SizedBox(width: 8),
              AppInteractiveSurface(
                key: const ValueKey('botApiAccessWarningDismiss'),
                semanticLabel: AppStringKeys.botApiWarningDismiss.l10n(context),
                onTap: onDismiss,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: Center(
                    child: AppIcon(
                      HeroAppIcons.xmark,
                      size: 16,
                      color: foreground,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
