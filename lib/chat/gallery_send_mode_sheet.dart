import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../theme/app_theme.dart';

enum GallerySendMode { media, highDefinition, livePhoto }

Future<GallerySendMode?> showGallerySendModeSheet(BuildContext context) {
  return showModalBottomSheet<GallerySendMode>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => const _GallerySendModeSheet(),
  );
}

class _GallerySendModeSheet extends StatelessWidget {
  const _GallerySendModeSheet();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: c.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          border: Border(top: BorderSide(color: c.divider, width: 0.5)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: c.textTertiary.withValues(alpha: 0.34),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            _option(
              context,
              key: const ValueKey('gallerySendAsMedia'),
              icon: HeroAppIcons.images,
              title: AppStringKeys.composerSendAsMedia.l10n(context),
              subtitle: AppStringKeys.gallerySendMediaSubtitle.l10n(context),
              onTap: () => Navigator.of(context).pop(GallerySendMode.media),
            ),
            Divider(height: 1, indent: 52, color: c.divider),
            _option(
              context,
              key: const ValueKey('gallerySendAsHd'),
              icon: HeroAppIcons.wandMagicSparkles,
              title: AppStringKeys.gallerySendHdTitle.l10n(context),
              subtitle: AppStringKeys.gallerySendHdSubtitle.l10n(context),
              onTap: () =>
                  Navigator.of(context).pop(GallerySendMode.highDefinition),
            ),
            Divider(height: 1, indent: 52, color: c.divider),
            _option(
              context,
              key: const ValueKey('gallerySendLivePhoto'),
              icon: HeroAppIcons.play,
              title: AppStringKeys.gallerySendMotionTitle.l10n(context),
              subtitle: AppStringKeys.gallerySendMotionSubtitle.l10n(context),
              onTap: () => Navigator.of(context).pop(GallerySendMode.livePhoto),
            ),
          ],
        ),
      ),
    );
  }

  Widget _option(
    BuildContext context, {
    required Key key,
    required AppIconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 62),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.brand.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: AppIcon(icon, size: 20, color: AppTheme.brand),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 12,
                          height: 1.25,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AppIcon(
                HeroAppIcons.chevronRight,
                size: 18,
                color: c.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
