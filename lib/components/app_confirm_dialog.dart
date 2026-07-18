import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// Project-styled confirmation dialog without Material or Cupertino widgets.
Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  required String confirmText,
  String cancelText = AppStringKeys.countryPickerCancel,
  AppColors? colors,
  bool destructive = false,
}) async {
  final c = colors ?? context.colors;
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: cancelText.l10n(context),
    barrierColor: const Color(0x99000000),
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (dialogContext, _, _) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(18),
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
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title.l10n(dialogContext),
                        textAlign: TextAlign.center,
                        style: AppTextStyle.title(
                          c.textPrimary,
                          weight: AppTextWeight.semibold,
                        ),
                      ),
                      if (message != null && message.trim().isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          message.l10n(dialogContext),
                          textAlign: TextAlign.center,
                          style: AppTextStyle.body(
                            c.textSecondary,
                          ).copyWith(height: 1.35),
                        ),
                      ],
                    ],
                  ),
                ),
                ColoredBox(color: c.divider, child: const SizedBox(height: 1)),
                SizedBox(
                  height: 50,
                  child: Row(
                    children: [
                      Expanded(
                        child: _DialogAction(
                          key: const ValueKey('app-confirm-cancel'),
                          label: cancelText.l10n(dialogContext),
                          color: c.textSecondary,
                          onTap: () => Navigator.of(dialogContext).pop(false),
                        ),
                      ),
                      ColoredBox(
                        color: c.divider,
                        child: const SizedBox(width: 1),
                      ),
                      Expanded(
                        child: _DialogAction(
                          key: const ValueKey('app-confirm-accept'),
                          label: confirmText.l10n(dialogContext),
                          color: destructive ? AppTheme.tagRed : c.linkBlue,
                          onTap: () => Navigator.of(dialogContext).pop(true),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (_, animation, _, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
        child: child,
      ),
    ),
  );
  return result ?? false;
}

class _DialogAction extends StatelessWidget {
  const _DialogAction({
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
      child: Center(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyle.bodyLarge(color, weight: AppTextWeight.semibold),
        ),
      ),
    ),
  );
}
