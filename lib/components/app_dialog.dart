import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_motion.dart';
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
                child: DefaultTextStyle(
                  style: AppTextStyle.body(c.dialogText),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: AppTextStyle.title(c.dialogText),
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
        ? c.dialogButton
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
  String? cancelLabel,
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
  String? emptyError,
}) {
  // Callers pass already-resolved copy; only the two defaults resolve here.
  final cancel = cancelLabel ?? AppStrings.t(AppStringKeys.confirmCancel);
  final requiredMessage =
      emptyError ?? AppStrings.t(AppStringKeys.appDialogRequiredField);
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: cancel,
    barrierColor: Colors.black.withValues(alpha: 0.52),
    transitionDuration: AppMotion.duration(context, AppMotion.responsive),
    transitionBuilder: AppMotion.dialogTransition,
    pageBuilder: (dialogContext, _, _) => _AppTextEntryDialog(
      title: title,
      actionLabel: actionLabel,
      cancelLabel: cancel,
      hint: hint,
      label: label,
      description: description,
      initial: initial,
      maxLength: maxLength,
      minLines: minLines,
      maxLines: maxLines,
      keyboardType: keyboardType,
      obscureText: obscureText,
      allowEmpty: allowEmpty,
      requiredMessage: requiredMessage,
    ),
  );
}

class _AppTextEntryDialog extends StatefulWidget {
  const _AppTextEntryDialog({
    required this.title,
    required this.actionLabel,
    required this.cancelLabel,
    required this.hint,
    required this.label,
    required this.description,
    required this.initial,
    required this.maxLength,
    required this.minLines,
    required this.maxLines,
    required this.keyboardType,
    required this.obscureText,
    required this.allowEmpty,
    required this.requiredMessage,
  });

  final String title;
  final String actionLabel;
  final String cancelLabel;
  final String hint;
  final String label;
  final String? description;
  final String initial;
  final int? maxLength;
  final int minLines;
  final int maxLines;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool allowEmpty;
  final String requiredMessage;

  @override
  State<_AppTextEntryDialog> createState() => _AppTextEntryDialogState();
}

class _AppTextEntryDialogState extends State<_AppTextEntryDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  String? _validationMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (!widget.allowEmpty && text.isEmpty) {
      setState(() => _validationMessage = widget.requiredMessage);
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final description = widget.description;
    return AppDialogSurface(
      title: widget.title,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (description != null && description.isNotEmpty) ...[
            Text(
              description,
              style: AppTextStyle.body(context.colors.textSecondary),
            ),
            const SizedBox(height: 14),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 2),
            decoration: BoxDecoration(
              color: context.colors.searchFill,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: context.colors.divider),
            ),
            child: TextField(
              controller: _controller,
              autofocus: true,
              maxLength: widget.maxLength,
              minLines: widget.obscureText ? 1 : widget.minLines,
              maxLines: widget.obscureText ? 1 : widget.maxLines,
              obscureText: widget.obscureText,
              keyboardType: widget.keyboardType,
              textInputAction: widget.maxLines == 1
                  ? TextInputAction.done
                  : TextInputAction.newline,
              onSubmitted: widget.maxLines == 1 ? (_) => _submit() : null,
              onChanged: _validationMessage == null
                  ? null
                  : (_) => setState(() => _validationMessage = null),
              style: AppTextStyle.body(context.colors.dialogText),
              decoration: InputDecoration(
                labelText: widget.label.isEmpty ? null : widget.label,
                hintText: widget.hint,
                errorText: _validationMessage,
                hintStyle: AppTextStyle.body(context.colors.textTertiary),
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
          label: widget.cancelLabel,
          onTap: () => Navigator.of(context).pop(),
        ),
        AppDialogAction(
          label: widget.actionLabel,
          primary: true,
          onTap: _submit,
        ),
      ],
    );
  }
}
