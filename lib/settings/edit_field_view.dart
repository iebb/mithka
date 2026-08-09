//
//  edit_field_view.dart
//
//  custom single-field editor: a flat nav header with a 保存 action and a
//  clean borderless field on a white card — no Material dialog / underlined
//  input. Returns the edited string via Navigator.pop.
//

import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

class EditFieldView extends StatefulWidget {
  const EditFieldView({
    super.key,
    required this.title,
    required this.initial,
    this.hint = '',
    this.prefix = '',
    this.multiline = false,
    this.maxLength,
    this.keyboardType,
  });
  final String title;
  final String initial;
  final String hint;
  final String prefix;
  final bool multiline;
  final int? maxLength;
  final TextInputType? keyboardType;

  @override
  State<EditFieldView> createState() => _EditFieldViewState();
}

class _EditFieldViewState extends State<EditFieldView> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SettingsPageScaffold(
      title: widget.title,
      onBack: () => Navigator.of(context).pop(),
      trailing: AppInteractiveSurface(
        semanticLabel: AppStrings.t(AppStringKeys.accentColorPickerSave),
        onTap: _save,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Text(
            AppStrings.t(AppStringKeys.accentColorPickerSave),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.brand,
            ),
          ),
        ),
      ),
      child: SettingsListView(
        children: [
          SettingsPanel(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxl,
              vertical: AppSpacing.xl,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.prefix.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 1, right: 2),
                    child: Text(
                      widget.prefix,
                      style: TextStyle(fontSize: 17, color: c.textSecondary),
                    ),
                  ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    autocorrect: false,
                    maxLines: widget.multiline ? 4 : 1,
                    minLines: 1,
                    maxLength: widget.maxLength,
                    keyboardType:
                        widget.keyboardType ??
                        (widget.multiline ? TextInputType.multiline : null),
                    textInputAction: widget.multiline
                        ? TextInputAction.newline
                        : TextInputAction.done,
                    onSubmitted: widget.multiline ? null : (_) => _save(),
                    style: TextStyle(fontSize: 17, color: c.textPrimary),
                    cursorColor: AppTheme.brand,
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: widget.hint.l10n(context),
                      hintStyle: TextStyle(color: c.textTertiary),
                      counterText: '',
                    ),
                  ),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _controller,
                  builder: (context, value, _) => value.text.isEmpty
                      ? const SizedBox.shrink()
                      : GestureDetector(
                          onTap: () => _controller.clear(),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8, top: 2),
                            child: AppIcon(
                              HeroAppIcons.xmark,
                              size: 17,
                              color: c.textTertiary,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
          if (widget.maxLength != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) => Text(
                  '${value.text.characters.length}/${widget.maxLength}',
                  style: TextStyle(fontSize: 12, color: c.textTertiary),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
