//
//  update_prompt_dialog.dart
//
//  The card that offers a newer build. The app's own surface — mark, title,
//  the version pair, an optional note, and tall stacked actions — instead of a
//  bare two-line alert, so an update prompt reads as part of Mithka rather
//  than as something the platform drew over it.
//

import 'package:flutter/widgets.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

/// Asks whether to take [latest] over [current]; true when the confirm action
/// was chosen.
///
/// [note] is an extra paragraph under the version pair — the reason a build
/// cannot be installed in place, for example. The copy arrives already
/// localized because every caller reads it from the same catalogue the buttons
/// come from.
Future<bool> showUpdatePromptDialog(
  BuildContext context, {
  required String title,
  required String current,
  required String latest,
  required String confirmText,
  String? cancelText,
  String? note,
}) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: (cancelText ?? AppStrings.t(AppStringKeys.updateLater)),
    barrierColor: const Color(0x99000000),
    transitionDuration: AppMotion.duration(context, AppMotion.responsive),
    transitionBuilder: AppMotion.dialogTransition,
    pageBuilder: (dialogContext, _, _) => _UpdatePromptDialog(
      title: title,
      current: current,
      latest: latest,
      confirmText: confirmText,
      cancelText: cancelText ?? AppStrings.t(AppStringKeys.updateLater),
      note: note,
    ),
  );
  return result ?? false;
}

class _UpdatePromptDialog extends StatelessWidget {
  const _UpdatePromptDialog({
    required this.title,
    required this.current,
    required this.latest,
    required this.confirmText,
    required this.cancelText,
    required this.note,
  });

  final String title;
  final String current;
  final String latest;
  final String confirmText;
  final String cancelText;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final note = this.note;
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.section),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: c.divider, width: 0.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x44000000),
                      blurRadius: 24,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _UpdateBadge(color: c.linkBlue),
                            const SizedBox(height: AppSpacing.lg),
                            Semantics(
                              header: true,
                              child: Text(
                                title,
                                textAlign: TextAlign.center,
                                style: AppTextStyle.title(
                                  c.textPrimary,
                                  weight: AppTextWeight.semibold,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            _VersionPair(
                              current: current,
                              latest: latest,
                              colors: c,
                            ),
                            if (note != null && note.trim().isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.lg),
                              Text(
                                note,
                                textAlign: TextAlign.center,
                                style: AppTextStyle.body(
                                  c.textSecondary,
                                ).copyWith(height: 1.35),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    ColoredBox(
                      color: c.divider,
                      child: const SizedBox(height: 1),
                    ),
                    _UpdateAction(
                      key: const ValueKey('update-prompt-confirm'),
                      label: confirmText,
                      color: c.linkBlue,
                      onTap: () => Navigator.of(context).pop(true),
                    ),
                    ColoredBox(
                      color: c.divider,
                      child: const SizedBox(height: 1),
                    ),
                    _UpdateAction(
                      key: const ValueKey('update-prompt-cancel'),
                      label: cancelText,
                      color: c.textSecondary,
                      autofocus: true,
                      onTap: () => Navigator.of(context).pop(false),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The update mark: a download glyph in the accent's tinted circle, the same
/// weight the app's other identity surfaces carry.
class _UpdateBadge extends StatelessWidget {
  const _UpdateBadge({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 52,
    height: 52,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      shape: BoxShape.circle,
    ),
    child: AppIcon(HeroAppIcons.cloudArrowDown, size: 26, color: color),
  );
}

/// 旧版本 → 新版本, on the inset fill the app uses for read-only facts.
class _VersionPair extends StatelessWidget {
  const _VersionPair({
    required this.current,
    required this.latest,
    required this.colors,
  });

  final String current;
  final String latest;
  final AppColors colors;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.md,
    ),
    decoration: BoxDecoration(
      color: colors.groupedBackground,
      borderRadius: BorderRadius.circular(AppRadius.card),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          current,
          style: AppTextStyle.body(
            colors.textSecondary,
          ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: AppIcon(
            HeroAppIcons.arrowRight,
            size: AppIconSize.sm,
            color: colors.textTertiary,
          ),
        ),
        Text(
          latest,
          style: AppTextStyle.body(
            colors.linkBlue,
            weight: AppTextWeight.semibold,
          ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ],
    ),
  );
}

class _UpdateAction extends StatelessWidget {
  const _UpdateAction({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
    this.autofocus = false,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => AppInteractiveSurface(
    semanticLabel: label,
    autofocus: autofocus,
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: AppMetric.compactSettingsRowHeight,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.lg,
        ),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppTextStyle.bodyLarge(
              color,
              weight: AppTextWeight.semibold,
            ),
          ),
        ),
      ),
    ),
  );
}
