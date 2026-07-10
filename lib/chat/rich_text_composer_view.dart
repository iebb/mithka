import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../theme/app_theme.dart';
import 'emoji_text_controller.dart';
import 'image_edit_view.dart';
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
  List<Map<String, dynamic>> initialEntities = const [],
  List<XFile> initialMedia = const [],
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
        initialEntities: initialEntities,
        initialMedia: initialMedia,
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
    this.initialEntities = const [],
    this.initialMedia = const [],
    this.title = AppStringKeys.topicChatShare,
    this.submitText = AppStringKeys.topicChatPublish,
    this.hintText = AppStringKeys.richTextComposerContentPlaceholder,
    this.allowMedia = true,
    this.asSheet = false,
  });

  final String initialText;
  final List<Map<String, dynamic>> initialEntities;
  final List<XFile> initialMedia;
  final String title;
  final String submitText;
  final String hintText;
  final bool allowMedia;
  final bool asSheet;

  @override
  State<RichTextComposerView> createState() => _RichTextComposerViewState();
}

class _RichTableDraft {
  _RichTableDraft({int rows = 3, int columns = 3})
    : cells = List.generate(
        rows,
        (row) => List.generate(
          columns,
          (column) => TextEditingController(
            text: row == 0 ? 'Column ${column + 1}' : '',
          ),
        ),
      );

  static const maxColumns = 20;

  final List<List<TextEditingController>> cells;

  int get rowCount => cells.length;
  int get columnCount => cells.isEmpty ? 0 : cells.first.length;

  void dispose() {
    for (final row in cells) {
      for (final cell in row) {
        cell.dispose();
      }
    }
  }

  void addRow() {
    cells.add(List.generate(columnCount, (_) => TextEditingController()));
  }

  void removeRow() {
    if (rowCount <= 2) return;
    final removed = cells.removeLast();
    for (final cell in removed) {
      cell.dispose();
    }
  }

  void addColumn() {
    if (columnCount >= maxColumns) return;
    for (var row = 0; row < cells.length; row++) {
      cells[row].add(
        TextEditingController(
          text: row == 0 ? 'Column ${columnCount + 1}' : '',
        ),
      );
    }
  }

  void removeColumn() {
    if (columnCount <= 2) return;
    for (final row in cells) {
      row.removeLast().dispose();
    }
  }

  String toMarkdown() {
    final rows = cells
        .map((row) => row.map((cell) => _escapeCell(cell.text)).toList())
        .toList();
    if (rows.isEmpty || rows.first.isEmpty) return '';
    final widths = List<int>.generate(rows.first.length, (column) {
      var width = 3;
      for (final row in rows) {
        if (column < row.length && row[column].length > width) {
          width = row[column].length;
        }
      }
      return width;
    });
    final buffer = StringBuffer();
    buffer.writeln(_markdownRow(rows.first, widths));
    buffer.writeln(_markdownRow(widths.map((w) => '-' * w).toList(), widths));
    for (final row in rows.skip(1)) {
      buffer.writeln(_markdownRow(row, widths));
    }
    return buffer.toString().trimRight();
  }

  static String _escapeCell(String value) {
    return value
        .replaceAll('\n', ' ')
        .replaceAll('\r', ' ')
        .replaceAll('|', r'\|')
        .trim();
  }

  static String _markdownRow(List<String> row, List<int> widths) {
    final cells = <String>[];
    for (var i = 0; i < widths.length; i++) {
      final value = i < row.length ? row[i] : '';
      cells.add(' ${value.padRight(widths[i])} ');
    }
    return '|${cells.join('|')}|';
  }
}

class _RichTextBlock {
  _RichTextBlock(this.controller, this.focusNode);

  final EmojiTextEditingController controller;
  final FocusNode focusNode;
}

class _RichContentBlock {
  const _RichContentBlock.text(this.text) : table = null;
  const _RichContentBlock.table(this.table) : text = null;

  final _RichTextBlock? text;
  final _RichTableDraft? table;
}

class _RichTextComposerViewState extends State<RichTextComposerView> {
  static const _obsidianAccent = Color(0xFF7C3AED);

  final _picker = ImagePicker();
  final _media = <XFile>[];
  late final List<_RichContentBlock> _blocks;
  late _RichTextBlock _activeTextBlock;

  EmojiTextEditingController get _controller => _activeTextBlock.controller;

  @override
  void initState() {
    super.initState();
    final first = _createTextBlock(
      widget.initialText,
      entities: widget.initialEntities,
    );
    _blocks = [_RichContentBlock.text(first)];
    _activeTextBlock = first;
    _media.addAll(widget.initialMedia.take(9));
  }

  @override
  void dispose() {
    for (final block in _blocks) {
      _disposeBlock(block);
    }
    super.dispose();
  }

  _RichTextBlock _createTextBlock(
    String text, {
    List<Map<String, dynamic>> entities = const [],
  }) {
    final controller = EmojiTextEditingController();
    if (entities.isEmpty) {
      controller.text = text;
    } else {
      controller.setFormattedText(text, entities);
    }
    controller.addListener(_onEditorChanged);
    final focusNode = FocusNode();
    final block = _RichTextBlock(controller, focusNode);
    focusNode.addListener(() {
      if (focusNode.hasFocus) _activeTextBlock = block;
    });
    return block;
  }

  void _disposeTextBlock(_RichTextBlock block) {
    block.controller.removeListener(_onEditorChanged);
    block.controller.dispose();
    block.focusNode.dispose();
  }

  void _disposeBlock(_RichContentBlock block) {
    final text = block.text;
    if (text != null) _disposeTextBlock(text);
    block.table?.dispose();
  }

  void _onEditorChanged() {
    if (mounted) setState(() {});
  }

  void _submit() {
    final buffer = StringBuffer();
    final entities = <Map<String, dynamic>>[];
    var hasContent = false;
    for (final block in _blocks) {
      String text;
      List<Map<String, dynamic>> blockEntities = const [];
      if (block.text != null) {
        final formatted = block.text!.controller.toFormatted();
        text = formatted.$1;
        blockEntities = formatted.$2;
      } else {
        text = block.table?.toMarkdown() ?? '';
      }
      if (text.trim().isEmpty) continue;
      if (hasContent) buffer.write('\n\n');
      final offset = buffer.length;
      buffer.write(text);
      for (final entity in blockEntities) {
        entities.add(_shiftTextEntity(entity, offset));
      }
      hasContent = true;
    }
    Navigator.of(context).pop(
      RichTextComposerResult(
        text: buffer.toString(),
        entities: entities,
        media: List<XFile>.of(_media),
      ),
    );
  }

  Map<String, dynamic> _shiftTextEntity(Map<String, dynamic> entity, int by) {
    return {
      ...entity,
      'offset': ((entity['offset'] as int?) ?? 0) + by,
      if (entity['type'] is Map<String, dynamic>)
        'type': Map<String, dynamic>.of(entity['type'] as Map<String, dynamic>),
    };
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
    final textBlock = _activeTextBlock;
    final index = _blocks.indexWhere((block) => block.text == textBlock);
    final controller = textBlock.controller;
    final text = controller.text;
    final selection = controller.selection;
    final start = selection.isValid
        ? (selection.start < selection.end ? selection.start : selection.end)
        : text.length;
    final end = selection.isValid
        ? (selection.start < selection.end ? selection.end : selection.start)
        : text.length;
    final before = text.substring(0, start);
    final after = text.substring(end);
    final nextText = _createTextBlock(after);
    controller.value = TextEditingValue(
      text: before,
      selection: TextSelection.collapsed(offset: before.length),
    );
    setState(() {
      final insertIndex = index < 0 ? _blocks.length : index + 1;
      _blocks.insertAll(insertIndex, [
        _RichContentBlock.table(_RichTableDraft()),
        _RichContentBlock.text(nextText),
      ]);
      _activeTextBlock = nextText;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) nextText.focusNode.requestFocus();
    });
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
                return SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.manual,
                  padding: EdgeInsets.only(bottom: 18 + keyboardInset),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var index = 0; index < _blocks.length; index++)
                          _contentBlock(c, constraints.maxHeight, index),
                      ],
                    ),
                  ),
                );
              },
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

  Widget _contentBlock(AppColors c, double availableHeight, int index) {
    final block = _blocks[index];
    final text = block.text;
    if (text != null) {
      return _textEditor(c, availableHeight, text);
    }
    final table = block.table;
    if (table == null) return const SizedBox.shrink();
    final tableNumber = _blocks
        .take(index + 1)
        .where((block) => block.table != null)
        .length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: _tableEditor(c, table, tableNumber),
    );
  }

  Widget _textEditor(
    AppColors c,
    double availableHeight,
    _RichTextBlock block,
  ) {
    return SizedBox(
      height: _textBlockHeight(block, availableHeight),
      child: TextField(
        controller: block.controller,
        focusNode: block.focusNode,
        autofocus: block == _blocks.first.text,
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
          hintText: _hasAnyText ? null : widget.hintText.l10n(context),
          hintStyle: TextStyle(color: c.textTertiary),
        ),
      ),
    );
  }

  bool get _hasAnyText => _blocks.any(
    (block) => block.text?.controller.text.trim().isNotEmpty ?? false,
  );

  double _textBlockHeight(_RichTextBlock block, double availableHeight) {
    final hasTables = _blocks.any((block) => block.table != null);
    if (!hasTables && _blocks.length == 1) return availableHeight;
    final lineCount = block.controller.text.split('\n').length;
    return (86.0 + lineCount * 23.0).clamp(120.0, 260.0);
  }

  void _removeTable(_RichTableDraft table) {
    final index = _blocks.indexWhere((block) => block.table == table);
    if (index < 0) return;
    setState(() {
      _blocks.removeAt(index).table?.dispose();
      if (!_blocks.any((block) => block.text != null)) {
        final text = _createTextBlock('');
        _blocks.add(_RichContentBlock.text(text));
        _activeTextBlock = text;
      }
    });
  }

  Widget _tableEditor(AppColors c, _RichTableDraft table, int tableNumber) {
    final tableHeight = (table.rowCount * 42.0 + 18).clamp(102.0, 260.0);
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.divider),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Row(
              children: [
                AppIcon(
                  HeroAppIcons.tableCells,
                  size: 18,
                  color: c.textPrimary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${AppStringKeys.richTextComposerInsertTable.l10n(context)} $tableNumber',
                    style: AppTextStyle.callout(
                      c.textPrimary,
                      weight: AppTextWeight.semibold,
                    ),
                  ),
                ),
                _miniIconButton(
                  c,
                  icon: HeroAppIcons.plus,
                  label: AppStringKeys.richTextComposerAddRow.l10n(context),
                  onTap: () => setState(table.addRow),
                ),
                _miniIconButton(
                  c,
                  icon: HeroAppIcons.tableColumns,
                  label: AppStringKeys.richTextComposerAddColumn.l10n(context),
                  onTap: table.columnCount >= _RichTableDraft.maxColumns
                      ? null
                      : () => setState(table.addColumn),
                ),
                _miniIconButton(
                  c,
                  icon: HeroAppIcons.minus,
                  label: AppStringKeys.richTextComposerRemoveRow.l10n(context),
                  onTap: table.rowCount <= 2
                      ? null
                      : () => setState(table.removeRow),
                ),
                _miniIconButton(
                  c,
                  icon: HeroAppIcons.circleMinus,
                  label: AppStringKeys.richTextComposerRemoveColumn.l10n(
                    context,
                  ),
                  onTap: table.columnCount <= 2
                      ? null
                      : () => setState(table.removeColumn),
                ),
                _miniIconButton(
                  c,
                  icon: HeroAppIcons.trash,
                  label: AppStringKeys.richTextComposerRemoveTable.l10n(
                    context,
                  ),
                  destructive: true,
                  onTap: () => _removeTable(table),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: tableHeight),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              child: Scrollbar(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    children: [
                      for (var row = 0; row < table.rowCount; row++)
                        Row(
                          children: [
                            for (
                              var column = 0;
                              column < table.columnCount;
                              column++
                            )
                              _tableCell(c, table, row, column),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableCell(AppColors c, _RichTableDraft table, int row, int column) {
    final isHeader = row == 0;
    return Container(
      width: 132,
      height: 42,
      decoration: BoxDecoration(
        color: isHeader
            ? _obsidianAccent.withValues(alpha: 0.12)
            : c.background,
        border: Border(
          right: BorderSide(color: c.divider),
          bottom: BorderSide(color: c.divider),
          left: column == 0 ? BorderSide(color: c.divider) : BorderSide.none,
          top: row == 0 ? BorderSide(color: c.divider) : BorderSide.none,
        ),
      ),
      child: TextField(
        controller: table.cells[row][column],
        textInputAction: TextInputAction.next,
        style: AppTextStyle.callout(
          c.textPrimary,
          weight: isHeader ? AppTextWeight.semibold : AppTextWeight.regular,
        ),
        decoration: const InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 11),
        ),
      ),
    );
  }

  Widget _miniIconButton(
    AppColors c, {
    required AppIconData icon,
    required String label,
    required VoidCallback? onTap,
    bool destructive = false,
  }) {
    final enabled = onTap != null;
    final color = destructive
        ? const Color(0xFFFF5A52)
        : enabled
        ? c.textPrimary
        : c.textTertiary.withValues(alpha: 0.48);
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
          child: AppIcon(icon, size: 17, color: color),
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isVideo ? null : () => _editMedia(index),
      child: Stack(
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
                child: AppIcon(
                  HeroAppIcons.play,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          if (!isVideo)
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: const AppIcon(
                  HeroAppIcons.pen,
                  size: 12,
                  color: Colors.white,
                ),
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
      ),
    );
  }

  Future<void> _editMedia(int index) async {
    if (index < 0 || index >= _media.length) return;
    final result = await Navigator.of(context).push<ImageEditResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ImageEditView(sourcePath: _media[index].path),
      ),
    );
    if (!mounted || result == null || index >= _media.length) return;
    setState(() => _media[index] = XFile(result.path));
    if (result.caption.trim().isNotEmpty) {
      _activeTextBlock.controller.insertText(result.caption);
    }
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
