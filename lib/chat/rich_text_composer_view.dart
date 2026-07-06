import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../theme/app_theme.dart';
import 'emoji_text_controller.dart';
import 'rich_text_format.dart';

class RichTextComposerResult {
  const RichTextComposerResult({
    required this.text,
    required this.entities,
    required this.media,
  });

  final String text;
  final List<Map<String, dynamic>> entities;
  final List<XFile> media;

  FormattedTextPayload get formattedText =>
      FormattedTextPayload(text, entities);
}

Future<RichTextComposerResult?> showRichTextComposerSheet(
  BuildContext context, {
  required String initialText,
  String title = AppStringKeys.topicChatShare,
  String submitText = AppStringKeys.topicChatPublish,
  String hintText = AppStringKeys.richTextComposerContentPlaceholder,
  bool allowMedia = true,
}) {
  return showGeneralDialog<RichTextComposerResult>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title.l10n(context),
    barrierColor: Colors.black.withValues(alpha: 0.36),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (dialogContext, _, _) {
      return RichTextComposerView(
        initialText: initialText,
        title: title,
        submitText: submitText,
        hintText: hintText,
        allowMedia: allowMedia,
        asSheet: true,
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

class RichTextComposerView extends StatefulWidget {
  const RichTextComposerView({
    super.key,
    required this.initialText,
    this.title = AppStringKeys.topicChatShare,
    this.submitText = AppStringKeys.topicChatPublish,
    this.hintText = AppStringKeys.richTextComposerContentPlaceholder,
    this.allowMedia = true,
    this.asSheet = false,
  });

  final String initialText;
  final String title;
  final String submitText;
  final String hintText;
  final bool allowMedia;
  final bool asSheet;

  @override
  State<RichTextComposerView> createState() => _RichTextComposerViewState();
}

class _RichTextComposerViewState extends State<RichTextComposerView> {
  static const _obsidianAccent = Color(0xFF7C3AED);

  late final EmojiTextEditingController _controller;
  final _picker = ImagePicker();
  final _media = <XFile>[];

  @override
  void initState() {
    super.initState();
    _controller = EmojiTextEditingController()
      ..text = widget.initialText
      ..addListener(_onEditorChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onEditorChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onEditorChanged() {
    if (mounted) setState(() {});
  }

  void _submit() {
    final (text, entities) = _controller.toFormatted();
    Navigator.of(context).pop(
      RichTextComposerResult(
        text: text,
        entities: entities,
        media: List<XFile>.of(_media),
      ),
    );
  }

  void _toggleFormat(String type, String placeholder) {
    if (_controller.hasSelection) {
      _controller.toggleFormat(type);
      return;
    }
    _insertPlaceholder(placeholder, type: type);
  }

  void _insertPlaceholder(String placeholder, {String? type}) {
    final selection = _controller.selection;
    final start = selection.isValid ? selection.start : _controller.text.length;
    _controller.insertFormattedText(placeholder, type: type);
    _controller.selection = TextSelection(
      baseOffset: start,
      extentOffset: start + placeholder.length,
    );
  }

  void _insertHeading() {
    final selection = _controller.selection;
    if (selection.isValid && !selection.isCollapsed) {
      final start = selection.start < selection.end
          ? selection.start
          : selection.end;
      final end = selection.start < selection.end
          ? selection.end
          : selection.start;
      _controller.formatRange(start, end, 'textEntityTypeBold');
      return;
    }
    final range = _currentLineRange();
    if (range.end > range.start) {
      _controller.formatRange(range.start, range.end, 'textEntityTypeBold');
      return;
    }
    _insertPlaceholder('Heading', type: 'textEntityTypeBold');
  }

  void _insertList(String marker) {
    final selection = _controller.selection;
    final text = _controller.text;
    final low = selection.isValid
        ? (selection.start < selection.end ? selection.start : selection.end)
        : text.length;
    final high = selection.isValid
        ? (selection.start < selection.end ? selection.end : selection.start)
        : low;
    final lineStart = text.lastIndexOf('\n', low > 0 ? low - 1 : 0) + 1;
    final nextBreak = text.indexOf('\n', high);
    final lineEnd = nextBreak < 0 ? text.length : nextBreak;
    final selected = text.substring(lineStart, lineEnd);
    final lines = selected.isEmpty ? [''] : selected.split('\n');
    final replacement = [
      for (var i = 0; i < lines.length; i++)
        '${marker == '1. ' ? '${i + 1}. ' : marker}${lines[i].trimLeft()}',
    ].join('\n');
    _controller.value = TextEditingValue(
      text: text.replaceRange(lineStart, lineEnd, replacement),
      selection: TextSelection.collapsed(
        offset: lineStart + replacement.length,
      ),
    );
  }

  ({int start, int end}) _currentLineRange() {
    final text = _controller.text;
    final selection = _controller.selection;
    final offset = selection.isValid
        ? selection.start.clamp(0, text.length)
        : text.length;
    final start = text.lastIndexOf('\n', offset > 0 ? offset - 1 : 0) + 1;
    final nextBreak = text.indexOf('\n', offset);
    return (start: start, end: nextBreak < 0 ? text.length : nextBreak);
  }

  void _insertTable() {
    const table =
        '\n| Column 1 | Column 2 | Column 3 |\n'
        '|----------|----------|----------|\n'
        '|          |          |          |\n'
        '|          |          |          |\n';
    _controller.insertFormattedText(table, type: 'textEntityTypePre');
  }

  void _insertCodeBlock() {
    _controller.insertFormattedText('\ncode\n', type: 'textEntityTypePre');
  }

  void _insertLink() {
    _insertPlaceholder('https://example.com');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final content = SafeArea(
      top: !widget.asSheet,
      child: Column(
        children: [
          SizedBox(
            height: 54,
            child: Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      AppStringKeys.countryPickerCancel.l10n(context),
                      style: TextStyle(fontSize: 16, color: c.textPrimary),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    widget.title.l10n(context),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _submit,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      widget.submitText.l10n(context),
                      style: TextStyle(
                        fontSize: 16,
                        color: AppTheme.brand,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: c.divider),
          _toolbar(c),
          if (widget.allowMedia) _mediaStrip(c),
          Expanded(
            child: TextField(
              controller: _controller,
              autofocus: true,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              contextMenuBuilder: (context, editableTextState) {
                return AdaptiveTextSelectionToolbar.editableText(
                  editableTextState: editableTextState,
                );
              },
              style: TextStyle(fontSize: 16, height: 1.4, color: c.textPrimary),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.all(16),
                border: InputBorder.none,
                hintText: widget.hintText.l10n(context),
                hintStyle: TextStyle(color: c.textTertiary),
              ),
            ),
          ),
        ],
      ),
    );
    if (!widget.asSheet) {
      return Scaffold(backgroundColor: c.background, body: content);
    }
    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: Colors.transparent,
        child: FractionallySizedBox(
          heightFactor: 0.86,
          widthFactor: 1,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: ColoredBox(color: c.background, child: content),
          ),
        ),
      ),
    );
  }

  Widget _toolbar(AppColors c) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: c.background,
        border: Border(bottom: BorderSide(color: c.divider)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
        children: [
          _toolbarGroup(c, [
            _formatChip(
              c,
              AppStringKeys.richTextComposerFormatBoldMark.l10n(context),
              'textEntityTypeBold',
              AppStringKeys.richTextComposerFormatBold.l10n(context),
            ),
            _formatChip(
              c,
              AppStringKeys.richTextComposerFormatItalicMark.l10n(context),
              'textEntityTypeItalic',
              AppStringKeys.richTextComposerFormatItalic.l10n(context),
            ),
            _formatChip(
              c,
              AppStringKeys.richTextComposerFormatUnderlineMark.l10n(context),
              'textEntityTypeUnderline',
              AppStringKeys.richTextComposerFormatUnderline.l10n(context),
            ),
            _formatChip(
              c,
              AppStringKeys.richTextComposerFormatStrikethroughMark.l10n(
                context,
              ),
              'textEntityTypeStrikethrough',
              AppStringKeys.richTextComposerFormatStrikethrough.l10n(context),
            ),
          ]),
          _toolbarGroup(c, [
            _formatChip(
              c,
              '</>',
              'textEntityTypeCode',
              AppStringKeys.richTextComposerFormatCode.l10n(context),
            ),
            _formatChip(
              c,
              AppStringKeys.richTextComposerFormatSpoiler.l10n(context),
              'textEntityTypeSpoiler',
              AppStringKeys.richTextComposerFormatSpoiler.l10n(context),
            ),
            _iconButton(
              c,
              icon: HeroAppIcons.quoteLeft,
              label: AppStringKeys.messageActionQuote.l10n(context),
              onTap: () => _toggleFormat(
                'textEntityTypeBlockQuote',
                AppStringKeys.messageActionQuote.l10n(context),
              ),
            ),
            _iconButton(
              c,
              icon: HeroAppIcons.link,
              label: AppStringKeys.sharedMediaLinks.l10n(context),
              onTap: _insertLink,
            ),
          ]),
          _toolbarGroup(c, [
            _actionChip(c, 'H1', _insertHeading),
            _actionChip(c, '•', () => _insertList('- ')),
            _actionChip(c, '1.', () => _insertList('1. ')),
            _actionChip(c, '☑', () => _insertList('- [ ] ')),
            _iconButton(
              c,
              icon: HeroAppIcons.code,
              label: AppStringKeys.richTextComposerFormatCode.l10n(context),
              onTap: _insertCodeBlock,
            ),
            _iconButton(
              c,
              icon: HeroAppIcons.tableCells,
              label: AppStringKeys.richTextComposerInsertTable.l10n(context),
              onTap: _insertTable,
            ),
          ]),
        ],
      ),
    );
  }

  Widget _mediaStrip(AppColors c) {
    if (_media.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _pickMedia,
          icon: const AppIcon(HeroAppIcons.image, size: 20),
          label: Text(AppStringKeys.richTextComposerPhotoVideo.l10n(context)),
        ),
      );
    }
    return SizedBox(
      height: 94,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        scrollDirection: Axis.horizontal,
        itemCount: _media.length + (_media.length < 9 ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == _media.length) return _addMediaTile(c);
          return _mediaTile(c, index);
        },
      ),
    );
  }

  Widget _addMediaTile(AppColors c) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _pickMedia,
      child: Container(
        width: 84,
        height: 84,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.searchFill,
          borderRadius: BorderRadius.circular(8),
        ),
        child: AppIcon(HeroAppIcons.plus, color: c.textTertiary),
      ),
    );
  }

  Widget _mediaTile(AppColors c, int index) {
    final item = _media[index];
    final isVideo = _isVideoPath(item.path);
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(item.path),
            width: 84,
            height: 84,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: 84,
              height: 84,
              color: c.searchFill,
              child: AppIcon(
                isVideo ? HeroAppIcons.solidFileVideo : HeroAppIcons.image,
                color: c.textTertiary,
              ),
            ),
          ),
        ),
        if (isVideo)
          const Positioned.fill(
            child: Center(
              child: AppIcon(HeroAppIcons.play, color: Colors.white, size: 24),
            ),
          ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _media.removeAt(index)),
            child: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: const AppIcon(
                HeroAppIcons.xmark,
                size: 12,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickMedia() async {
    try {
      final picked = await _picker.pickMultipleMedia();
      if (picked.isEmpty || !mounted) return;
      final remaining = 9 - _media.length;
      setState(() => _media.addAll(picked.take(remaining)));
    } catch (_) {}
  }

  Widget _toolbarGroup(AppColors c, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.searchFill.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.divider),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _formatChip(
    AppColors c,
    String label,
    String type,
    String placeholder,
  ) {
    final active = _controller.selectionHasFormat(type);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggleFormat(type, placeholder),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? _obsidianAccent.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: active
              ? Border.all(color: _obsidianAccent.withValues(alpha: 0.65))
              : null,
        ),
        child: Text(
          label,
          style: AppTextStyle.callout(
            active ? _obsidianAccent : c.textPrimary,
            weight: AppTextWeight.semibold,
          ),
        ),
      ),
    );
  }

  Widget _actionChip(AppColors c, String label, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
        child: Text(
          label,
          style: AppTextStyle.callout(
            c.textPrimary,
            weight: AppTextWeight.semibold,
          ),
        ),
      ),
    );
  }

  Widget _iconButton(
    AppColors c, {
    required AppIconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
          child: AppIcon(icon, size: 18, color: c.textPrimary),
        ),
      ),
    );
  }

  bool _isVideoPath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.webm');
  }
}
