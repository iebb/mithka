import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'app_interactive_surface.dart';

/// Project-styled confirmation dialog without Material or Cupertino widgets.
Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  Widget? content,
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
    transitionDuration: AppMotion.duration(context, AppMotion.responsive),
    pageBuilder: (dialogContext, _, _) => Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(AppRadius.lg),
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
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(
                              title.l10n(dialogContext),
                              textAlign: TextAlign.center,
                              style: AppTextStyle.title(
                                c.textPrimary,
                                weight: AppTextWeight.semibold,
                              ),
                            ),
                          ),
                          if (content != null) ...[
                            const SizedBox(height: 14),
                            content,
                          ],
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
                  ),
                  ColoredBox(
                    color: c.divider,
                    child: const SizedBox(height: 1),
                  ),
                  _DialogActions(
                    cancelLabel: cancelText.l10n(dialogContext),
                    confirmLabel: confirmText.l10n(dialogContext),
                    cancelColor: c.textSecondary,
                    confirmColor: destructive ? AppTheme.tagRed : c.linkBlue,
                    dividerColor: c.divider,
                    onCancel: () => Navigator.of(dialogContext).pop(false),
                    onConfirm: () => Navigator.of(dialogContext).pop(true),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: AppMotion.dialogTransition,
  );
  return result ?? false;
}

class _DialogActions extends StatelessWidget {
  const _DialogActions({
    required this.cancelLabel,
    required this.confirmLabel,
    required this.cancelColor,
    required this.confirmColor,
    required this.dividerColor,
    required this.onCancel,
    required this.onConfirm,
  });

  final String cancelLabel;
  final String confirmLabel;
  final Color cancelColor;
  final Color confirmColor;
  final Color dividerColor;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final scaledBodySize = MediaQuery.textScalerOf(context).scale(16);
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackActions = constraints.maxWidth < 300 || scaledBodySize >= 22;
        final cancel = _DialogAction(
          key: const ValueKey('app-confirm-cancel'),
          label: cancelLabel,
          color: cancelColor,
          autofocus: true,
          onTap: onCancel,
        );
        final confirm = _DialogAction(
          key: const ValueKey('app-confirm-accept'),
          label: confirmLabel,
          color: confirmColor,
          onTap: onConfirm,
        );

        if (stackActions) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              confirm,
              ColoredBox(color: dividerColor, child: const SizedBox(height: 1)),
              cancel,
            ],
          );
        }

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: cancel),
              ColoredBox(color: dividerColor, child: const SizedBox(width: 1)),
              Expanded(child: confirm),
            ],
          ),
        );
      },
    );
  }
}

class _DialogAction extends StatelessWidget {
  const _DialogAction({
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
      constraints: const BoxConstraints(minHeight: 50),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
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
