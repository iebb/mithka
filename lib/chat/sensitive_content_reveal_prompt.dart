import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

enum SensitiveContentRevealChoice { enableGlobally, keepOff, revealOnce }

/// Shows the three sensitive-content choices beside the message interaction.
///
/// The route has a transparent barrier: clicking outside is equivalent to
/// keeping the account setting off, without dimming or relaying out the chat.
Future<SensitiveContentRevealChoice> showSensitiveContentRevealPrompt(
  BuildContext context, {
  Rect? anchor,
}) async {
  final keepOff = AppStringKeys.sensitiveContentChoiceKeepOff.l10n(context);
  final result = await showGeneralDialog<SensitiveContentRevealChoice>(
    context: context,
    barrierDismissible: true,
    barrierLabel: keepOff,
    barrierColor: Colors.transparent,
    transitionDuration: AppMotion.duration(context, AppMotion.quick),
    transitionBuilder: (context, animation, _, child) {
      if (AppMotion.isReduced(context)) return child;
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: AppMotion.standard),
        child: child,
      );
    },
    pageBuilder: (dialogContext, _, _) => _SensitiveContentRevealPrompt(
      anchor: anchor,
      onSelected: (choice) => Navigator.of(dialogContext).pop(choice),
    ),
  );
  return result ?? SensitiveContentRevealChoice.keepOff;
}

class _SensitiveContentRevealPrompt extends StatelessWidget {
  const _SensitiveContentRevealPrompt({
    required this.anchor,
    required this.onSelected,
  });

  final Rect? anchor;
  final ValueChanged<SensitiveContentRevealChoice> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final padding = MediaQuery.paddingOf(context);
    return CustomSingleChildLayout(
      delegate: _SensitiveContentPromptLayout(anchor: anchor, padding: padding),
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        child: DecoratedBox(
          key: const ValueKey('sensitive-content-choice-surface'),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: c.divider, width: 0.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.20),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: DefaultTextStyle(
              style: AppTextStyle.body(c.textPrimary),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 5),
                    child: Text(
                      AppStringKeys.sensitiveContentUnblockTitle.l10n(context),
                      style: AppTextStyle.bodyLarge(
                        c.textPrimary,
                        weight: AppTextWeight.semibold,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 11),
                    child: Text(
                      AppStringKeys.sensitiveContentUnblockMessage.l10n(
                        context,
                      ),
                      style: AppTextStyle.body(
                        c.textSecondary,
                      ).copyWith(height: 1.3),
                    ),
                  ),
                  ColoredBox(
                    color: c.divider,
                    child: const SizedBox(height: 1),
                  ),
                  _SensitiveContentChoiceRow(
                    key: const ValueKey('sensitive-content-enable'),
                    label: AppStringKeys.sensitiveContentChoiceEnable.l10n(
                      context,
                    ),
                    color: c.linkBlue,
                    onTap: () =>
                        onSelected(SensitiveContentRevealChoice.enableGlobally),
                  ),
                  ColoredBox(
                    color: c.divider,
                    child: const SizedBox(height: 1),
                  ),
                  _SensitiveContentChoiceRow(
                    key: const ValueKey('sensitive-content-reveal-once'),
                    label: AppStringKeys.sensitiveContentChoiceRevealOnce.l10n(
                      context,
                    ),
                    color: c.textPrimary,
                    onTap: () =>
                        onSelected(SensitiveContentRevealChoice.revealOnce),
                  ),
                  ColoredBox(
                    color: c.divider,
                    child: const SizedBox(height: 1),
                  ),
                  _SensitiveContentChoiceRow(
                    key: const ValueKey('sensitive-content-keep-off'),
                    label: AppStringKeys.sensitiveContentChoiceKeepOff.l10n(
                      context,
                    ),
                    color: c.textSecondary,
                    onTap: () =>
                        onSelected(SensitiveContentRevealChoice.keepOff),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SensitiveContentChoiceRow extends StatelessWidget {
  const _SensitiveContentChoiceRow({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 42),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              label,
              style: AppTextStyle.body(color, weight: AppTextWeight.medium),
            ),
          ),
        ),
      ),
    ),
  );
}

class _SensitiveContentPromptLayout extends SingleChildLayoutDelegate {
  const _SensitiveContentPromptLayout({
    required this.anchor,
    required this.padding,
  });

  final Rect? anchor;
  final EdgeInsets padding;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final availableWidth = math.max(
      1.0,
      constraints.maxWidth - padding.horizontal - 24,
    );
    return BoxConstraints.tightFor(width: math.min(328, availableWidth));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    const margin = 12.0;
    final minLeft = padding.left + margin;
    final maxLeft = math.max(
      minLeft,
      size.width - padding.right - margin - childSize.width,
    );
    final minTop = padding.top + margin;
    final maxTop = math.max(
      minTop,
      size.height - padding.bottom - margin - childSize.height,
    );
    final target = anchor;
    if (target == null) {
      return Offset(
        ((size.width - childSize.width) / 2).clamp(minLeft, maxLeft),
        ((size.height - childSize.height) / 2).clamp(minTop, maxTop),
      );
    }
    final left = (target.center.dx - childSize.width / 2).clamp(
      minLeft,
      maxLeft,
    );
    final below = target.bottom + 8;
    final top = below + childSize.height <= maxTop + childSize.height
        ? below.clamp(minTop, maxTop)
        : (target.top - childSize.height - 8).clamp(minTop, maxTop);
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(covariant _SensitiveContentPromptLayout oldDelegate) =>
      anchor != oldDelegate.anchor || padding != oldDelegate.padding;
}
