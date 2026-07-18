import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Project-owned modal surface with explicit dimensions, colors, and actions.
class AppDialogSurface extends StatelessWidget {
  const AppDialogSurface({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
    this.maxWidth = 380,
  });

  final String title;
  final Widget content;
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Material(
              color: Colors.transparent,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: c.divider, width: 0.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x44000000),
                      blurRadius: 24,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: DefaultTextStyle(
                  style: AppTextStyle.body(c.textPrimary),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: AppTextStyle.title(c.textPrimary),
                        ),
                      ),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
                          child: content,
                        ),
                      ),
                      ColoredBox(
                        color: c.divider,
                        child: const SizedBox(height: 0.5),
                      ),
                      SizedBox(height: 50, child: Row(children: actions)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppDialogAction extends StatelessWidget {
  const AppDialogAction({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = destructive
        ? AppTheme.tagRed
        : primary
        ? c.linkBlue
        : c.textSecondary;
    return Expanded(
      child: Semantics(
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
}

Future<String?> showAppTextEntryDialog(
  BuildContext context, {
  required String title,
  required String actionLabel,
  String cancelLabel = 'Cancel',
  String hint = '',
  String label = '',
  String? description,
  String initial = '',
  int? maxLength,
  int minLines = 1,
  int maxLines = 1,
  TextInputType? keyboardType,
  bool obscureText = false,
  bool allowEmpty = true,
  String emptyError = 'Required',
}) async {
  final controller = TextEditingController(text: initial);
  String? validationMessage;
  final value = await showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: cancelLabel,
    barrierColor: Colors.black.withValues(alpha: 0.52),
    transitionDuration: const Duration(milliseconds: 160),
    transitionBuilder: (_, animation, _, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
        child: child,
      ),
    ),
    pageBuilder: (dialogContext, _, _) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        void submit() {
          final text = controller.text.trim();
          if (!allowEmpty && text.isEmpty) {
            setDialogState(() => validationMessage = emptyError);
            return;
          }
          Navigator.of(dialogContext).pop(text);
        }

        return AppDialogSurface(
          title: title,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (description != null && description.isNotEmpty) ...[
                Text(
                  description,
                  style: AppTextStyle.body(dialogContext.colors.textSecondary),
                ),
                const SizedBox(height: 14),
              ],
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: dialogContext.colors.searchFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: dialogContext.colors.divider),
                ),
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: maxLength,
                  minLines: obscureText ? 1 : minLines,
                  maxLines: obscureText ? 1 : maxLines,
                  obscureText: obscureText,
                  keyboardType: keyboardType,
                  textInputAction: maxLines == 1
                      ? TextInputAction.done
                      : TextInputAction.newline,
                  onSubmitted: maxLines == 1 ? (_) => submit() : null,
                  onChanged: validationMessage == null
                      ? null
                      : (_) => setDialogState(() => validationMessage = null),
                  style: AppTextStyle.body(dialogContext.colors.textPrimary),
                  decoration: InputDecoration(
                    labelText: label.isEmpty ? null : label,
                    hintText: hint,
                    errorText: validationMessage,
                    hintStyle: AppTextStyle.body(
                      dialogContext.colors.textTertiary,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            AppDialogAction(
              label: cancelLabel,
              onTap: () => Navigator.of(dialogContext).pop(),
            ),
            AppDialogAction(label: actionLabel, primary: true, onTap: submit),
          ],
        );
      },
    ),
  );
  controller.dispose();
  return value;
}
