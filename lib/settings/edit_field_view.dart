//
//  edit_field_view.dart
//
//  custom single-field editor: a flat nav header with a 保存 action and a
//  clean borderless field on a white card — no Material dialog / underlined
//  input. Returns the edited string via Navigator.pop.
//

import 'package:flutter/material.dart';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
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
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          _header(c),
          const SizedBox(height: 14),
          Container(
            color: c.card,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                            child: FaIcon(
                              FontAwesomeIcons.xmark,
                              size: 17,
                              color: c.textTertiary,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
          if (widget.maxLength != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerRight,
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _controller,
                  builder: (context, value, _) => Text(
                    '${value.text.characters.length}/${widget.maxLength}',
                    style: TextStyle(fontSize: 12, color: c.textTertiary),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _header(AppColors c) {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: FaIcon(
                    FontAwesomeIcons.chevronLeft,
                    size: 22,
                    color: c.textPrimary,
                  ),
                ),
              ),
            ),
            Text(
              widget.title.l10n(context),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _save,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '保存'.l10n(context),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.brand,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
