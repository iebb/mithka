import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../media/app_asset_picker.dart';
import '../theme/app_theme.dart';
import 'emoji_text_controller.dart';
import 'image_edit_view.dart';
import 'outgoing_attachment.dart';
import 'rich_message_source.dart';
import 'rich_text_format.dart';

class RichTextComposerResult {
  const RichTextComposerResult({
    required this.text,
    required this.entities,
    required this.attachments,
    required this.segments,
  });

  final String text;
  final List<Map<String, dynamic>> entities;
  final List<OutgoingAttachment> attachments;
  final List<RichMessageSendSegment> segments;

  FormattedTextPayload get formattedText =>
      FormattedTextPayload(text, entities);
}

Future<RichTextComposerResult?> showRichTextComposerSheet(
  BuildContext context, {
  required String initialText,
  List<Map<String, dynamic>> initialEntities = const [],
  List<XFile> initialMedia = const [],
  List<OutgoingAttachment> initialAttachments = const [],
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
        initialAttachments: initialAttachments,
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
    this.initialAttachments = const [],
    this.title = AppStringKeys.topicChatShare,
    this.submitText = AppStringKeys.topicChatPublish,
    this.hintText = AppStringKeys.richTextComposerContentPlaceholder,
    this.allowMedia = true,
    this.asSheet = false,
  });

  final String initialText;
  final List<Map<String, dynamic>> initialEntities;
  final List<XFile> initialMedia;
  final List<OutgoingAttachment> initialAttachments;
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

  String toHtml() {
    if (cells.isEmpty || cells.first.isEmpty) return '';
    final buffer = StringBuffer('<table bordered striped>');
    for (var rowIndex = 0; rowIndex < cells.length; rowIndex++) {
      buffer.write('<tr>');
      for (final cell in cells[rowIndex]) {
        final tag = rowIndex == 0 ? 'th' : 'td';
        buffer
          ..write('<$tag>')
          ..write(escapeRichHtml(cell.text.trim()))
          ..write('</$tag>');
      }
      buffer.write('</tr>');
    }
    buffer.write('</table>');
    return buffer.toString();
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
  _RichTextBlock(this.controller, this.focusNode, this.onTextChanged)
    : lastText = controller.text;

  final EmojiTextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onTextChanged;
  String lastText;
  int headingLevel = 0;
}

class _RichMathDraft {
  _RichMathDraft() : controller = TextEditingController(text: r'E = mc^2');

  final TextEditingController controller;

  void dispose() => controller.dispose();
}

class _RichContentBlock {
  const _RichContentBlock.text(this.text)
    : table = null,
      math = null,
      attachment = null;
  const _RichContentBlock.table(this.table)
    : text = null,
      math = null,
      attachment = null;
  const _RichContentBlock.math(this.math)
    : text = null,
      table = null,
      attachment = null;
  const _RichContentBlock.attachment(this.attachment)
    : text = null,
      table = null,
      math = null;

  final _RichTextBlock? text;
  final _RichTableDraft? table;
  final _RichMathDraft? math;
  final OutgoingAttachment? attachment;
}

class _RichTextComposerViewState extends State<RichTextComposerView> {
  static const _maxAttachments = 10;

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
    final initialAttachments = <OutgoingAttachment>[
      ...widget.initialAttachments,
      ...widget.initialMedia.map(_attachmentFromPickedMedia),
    ].take(_maxAttachments);
    _blocks.addAll(initialAttachments.map(_RichContentBlock.attachment));
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
    final focusNode = FocusNode();
    late final _RichTextBlock block;
    void onTextChanged() {
      if (controller.text == block.lastText) return;
      block.lastText = controller.text;
      if (mounted) setState(() {});
    }

    block = _RichTextBlock(controller, focusNode, onTextChanged);
    controller.addListener(onTextChanged);
    focusNode.addListener(() {
      if (focusNode.hasFocus) _activeTextBlock = block;
    });
    return block;
  }

  void _disposeTextBlock(_RichTextBlock block) {
    block.controller.removeListener(block.onTextChanged);
    block.controller.dispose();
    block.focusNode.dispose();
  }

  void _disposeBlock(_RichContentBlock block) {
    final text = block.text;
    if (text != null) _disposeTextBlock(text);
    block.table?.dispose();
    block.math?.dispose();
  }

  void _submit() {
    final buffer = StringBuffer();
    final entities = <Map<String, dynamic>>[];
    final attachments = <OutgoingAttachment>[];
    final segments = <RichMessageSendSegment>[];
    final htmlBuffer = StringBuffer();
    final htmlFiles = <RichMessageSendFile>[];
    final pendingAttachments = <OutgoingAttachment>[];
    var hasContent = false;

    void flushHtml() {
      final html = htmlBuffer.toString().trim();
      if (html.isNotEmpty) {
        segments.add(
          RichMessageSendSegment.html(
            html,
            richFiles: List<RichMessageSendFile>.unmodifiable(htmlFiles),
          ),
        );
      }
      htmlBuffer.clear();
      htmlFiles.clear();
    }

    void flushAttachments() {
      if (pendingAttachments.isEmpty) return;
      segments.add(
        RichMessageSendSegment.attachments(
          List<OutgoingAttachment>.unmodifiable(pendingAttachments),
        ),
      );
      pendingAttachments.clear();
    }

    for (final block in _blocks) {
      final attachment = block.attachment;
      if (attachment != null) {
        attachments.add(attachment);
        if (attachment.kind == OutgoingAttachmentKind.document) {
          flushHtml();
          pendingAttachments.add(attachment);
          continue;
        }
        flushAttachments();
        final id = 'mithka-rich-${segments.length}-${htmlFiles.length}';
        htmlFiles.add(RichMessageSendFile(id: id, attachment: attachment));
        htmlBuffer.write(switch (attachment.kind) {
          OutgoingAttachmentKind.photo => '<img src="$id"/>',
          OutgoingAttachmentKind.video ||
          OutgoingAttachmentKind.animation => '<video src="$id"></video>',
          OutgoingAttachmentKind.audio => '<audio src="$id"></audio>',
          OutgoingAttachmentKind.document => '',
        });
        continue;
      }
      flushAttachments();
      String text;
      List<Map<String, dynamic>> blockEntities = const [];
      if (block.text != null) {
        final formatted = block.text!.controller.toFormatted();
        text = formatted.$1;
        blockEntities = formatted.$2;
        htmlBuffer.write(
          formattedTextToRichHtml(
            text,
            blockEntities,
            headingLevel: block.text!.headingLevel,
          ),
        );
      } else if (block.math != null) {
        text = block.math!.controller.text.trim();
        if (text.isNotEmpty) {
          htmlBuffer.write(
            '<tg-math-block>${escapeRichHtml(text)}</tg-math-block>',
          );
        }
      } else {
        text = block.table?.toMarkdown() ?? '';
        htmlBuffer.write(block.table?.toHtml() ?? '');
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
    flushAttachments();
    flushHtml();
    Navigator.of(context).pop(
      RichTextComposerResult(
        text: buffer.toString(),
        entities: entities,
        attachments: List.unmodifiable(attachments),
        segments: List.unmodifiable(segments),
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
    setState(() {
      _activeTextBlock.headingLevel = (_activeTextBlock.headingLevel + 1) % 4;
    });
    if (_controller.text.trim().isEmpty) {
      _insertPlaceholder('Heading');
    }
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

  void _insertMathBlock() {
    final index = _blocks.indexWhere((block) => block.text == _activeTextBlock);
    final nextText = _createTextBlock('');
    setState(() {
      final insertIndex = index < 0 ? _blocks.length : index + 1;
      _blocks.insertAll(insertIndex, [
        _RichContentBlock.math(_RichMathDraft()),
        _RichContentBlock.text(nextText),
      ]);
      _activeTextBlock = nextText;
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
          if (widget.allowMedia) _attachmentDock(c),
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
          heightFactor: 0.94,
          widthFactor: 1,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
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
    final attachment = block.attachment;
    if (attachment != null) {
      return _inlineAttachmentBlock(c, index, attachment);
    }
    final math = block.math;
    if (math != null) {
      return _mathEditor(c, index, math);
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
    final hasStructuredBlocks = _blocks.any(
      (block) =>
          block.table != null || block.math != null || block.attachment != null,
    );
    if (!hasStructuredBlocks && _blocks.length == 1) return availableHeight;
    final lineCount = block.controller.text.split('\n').length;
    return (86.0 + lineCount * 23.0).clamp(120.0, 260.0);
  }

  Widget _mathEditor(AppColors c, int index, _RichMathDraft math) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'LaTeX',
                  style: AppTextStyle.callout(
                    c.textPrimary,
                    weight: AppTextWeight.semibold,
                  ),
                ),
                const Spacer(),
                _miniIconButton(
                  c,
                  icon: HeroAppIcons.trash,
                  label: AppStringKeys.richTextComposerRemoveTable.l10n(
                    context,
                  ),
                  destructive: true,
                  onTap: () => _removeStructuredBlock(index),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: math.controller,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              style: AppTextStyle.callout(c.textPrimary),
              decoration: InputDecoration(
                filled: true,
                fillColor: c.searchFill,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(10),
              ),
            ),
            if (math.controller.text.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Math.tex(
                  math.controller.text,
                  textStyle: TextStyle(fontSize: 18, color: c.textPrimary),
                  onErrorFallback: (_) => Text(
                    math.controller.text,
                    style: TextStyle(color: c.textSecondary),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _removeStructuredBlock(int index) {
    if (index < 0 || index >= _blocks.length) return;
    setState(() {
      final removed = _blocks.removeAt(index);
      _disposeBlock(removed);
    });
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
        color: isHeader ? AppTheme.brand.withValues(alpha: 0.1) : c.background,
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
      height: 48,
      decoration: BoxDecoration(
        color: c.background,
        border: Border(bottom: BorderSide(color: c.divider)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        children: [
          ...[
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
          ],
          _toolbarDivider(c),
          ...[
            _formatChip(
              c,
              '</>',
              'textEntityTypeCode',
              AppStringKeys.richTextComposerFormatCode.l10n(context),
            ),
            _formatChip(
              c,
              '||',
              'textEntityTypeSpoiler',
              AppStringKeys.richTextComposerFormatSpoiler.l10n(context),
            ),
            _formatChip(
              c,
              'M',
              'textEntityTypeMarked',
              AppStringKeys.richTextComposerFormatMarked.l10n(context),
            ),
            _formatChip(
              c,
              'x₂',
              'textEntityTypeSubscript',
              AppStringKeys.richTextComposerFormatSubscript.l10n(context),
            ),
            _formatChip(
              c,
              'x²',
              'textEntityTypeSuperscript',
              AppStringKeys.richTextComposerFormatSuperscript.l10n(context),
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
          ],
          _toolbarDivider(c),
          ...[
            _actionChip(
              c,
              _activeTextBlock.headingLevel == 0
                  ? 'H'
                  : 'H${_activeTextBlock.headingLevel}',
              _insertHeading,
            ),
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
            _actionChip(c, '∑', _insertMathBlock),
          ],
        ],
      ),
    );
  }

  Widget _toolbarDivider(AppColors c) {
    return Container(
      width: 1,
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      color: c.divider,
    );
  }

  Widget _attachmentDock(AppColors c) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.background,
        border: Border(top: BorderSide(color: c.divider)),
      ),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            Expanded(
              child: _attachmentAction(
                c,
                icon: HeroAppIcons.image,
                label: AppStringKeys.richTextComposerPhotoVideo.l10n(context),
                onTap: _pickMedia,
              ),
            ),
            Expanded(
              child: _attachmentAction(
                c,
                icon: HeroAppIcons.file,
                label: AppStringKeys.topicPostContentFile.l10n(context),
                onTap: _pickFiles,
              ),
            ),
            Expanded(
              child: _attachmentAction(
                c,
                icon: HeroAppIcons.music,
                label: AppStringKeys.composerAudio.l10n(context),
                onTap: _pickMusic,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Text(
                '$_attachmentCount/$_maxAttachments',
                style: AppTextStyle.caption(c.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int get _attachmentCount =>
      _blocks.where((block) => block.attachment != null).length;

  Widget _attachmentAction(
    AppColors c, {
    required AppIconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final enabled = _attachmentCount < _maxAttachments;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon(
              icon,
              size: 20,
              color: enabled ? c.textPrimary : c.textTertiary,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.caption(
                  enabled ? c.textPrimary : c.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inlineAttachmentBlock(
    AppColors c,
    int blockIndex,
    OutgoingAttachment item,
  ) {
    final isPhoto = item.kind == OutgoingAttachmentKind.photo;
    final isVisual = isPhoto || item.kind == OutgoingAttachmentKind.video;
    if (isVisual) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Container(
          height: 190,
          decoration: BoxDecoration(
            color: c.searchFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.divider),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: isPhoto ? () => _editAttachment(blockIndex) : null,
                child: _attachmentPreview(
                  c,
                  item,
                  width: double.infinity,
                  height: 190,
                  fit: BoxFit.contain,
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xB8000000),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _mediaOverlayAction(
                        HeroAppIcons.arrowUp,
                        blockIndex <= 0
                            ? null
                            : () => _moveBlock(blockIndex, blockIndex - 1),
                      ),
                      _mediaOverlayAction(
                        HeroAppIcons.arrowDown,
                        blockIndex >= _blocks.length - 1
                            ? null
                            : () => _moveBlock(blockIndex, blockIndex + 1),
                      ),
                      _mediaOverlayAction(
                        HeroAppIcons.trash,
                        () => _removeStructuredBlock(blockIndex),
                        destructive: true,
                      ),
                    ],
                  ),
                ),
              ),
              if (item.kind == OutgoingAttachmentKind.video)
                const Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0x99000000),
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: AppIcon(
                        HeroAppIcons.play,
                        size: 24,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Container(
        constraints: const BoxConstraints(minHeight: 86),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: c.searchFill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.divider),
        ),
        child: Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: isPhoto ? () => _editAttachment(blockIndex) : null,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: _attachmentIcon(c, item, size: 70),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _fileName(item.path),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.callout(
                      c.textPrimary,
                      weight: AppTextWeight.semibold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _attachmentLabel(item.kind),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.caption(c.textTertiary),
                  ),
                ],
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _miniIconButton(
                  c,
                  icon: HeroAppIcons.arrowUp,
                  label: AppStringKeys.richTextComposerMoveUp.l10n(context),
                  onTap: blockIndex <= 0
                      ? null
                      : () => _moveBlock(blockIndex, blockIndex - 1),
                ),
                _miniIconButton(
                  c,
                  icon: HeroAppIcons.arrowDown,
                  label: AppStringKeys.richTextComposerMoveDown.l10n(context),
                  onTap: blockIndex >= _blocks.length - 1
                      ? null
                      : () => _moveBlock(blockIndex, blockIndex + 1),
                ),
                _miniIconButton(
                  c,
                  icon: HeroAppIcons.trash,
                  label: AppStringKeys.richTextComposerRemoveTable.l10n(
                    context,
                  ),
                  destructive: true,
                  onTap: () => _removeStructuredBlock(blockIndex),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _mediaOverlayAction(
    AppIconData icon,
    VoidCallback? onTap, {
    bool destructive = false,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Center(
          child: AppIcon(
            icon,
            size: 17,
            color: onTap == null
                ? Colors.white38
                : destructive
                ? const Color(0xFFFF706A)
                : Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _attachmentPreview(
    AppColors c,
    OutgoingAttachment attachment, {
    required double width,
    required double height,
    BoxFit fit = BoxFit.cover,
  }) {
    final previewBytes = attachment.previewBytes;
    if (previewBytes != null && previewBytes.isNotEmpty) {
      return Image.memory(
        previewBytes,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, _, _) => _attachmentIcon(c, attachment, size: height),
      );
    }
    return Image.file(
      File(attachment.path),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, _, _) => _attachmentIcon(c, attachment, size: height),
    );
  }

  Widget _attachmentIcon(
    AppColors c,
    OutgoingAttachment attachment, {
    double size = 52,
  }) {
    return Container(
      width: size,
      height: size,
      color: c.card,
      alignment: Alignment.center,
      child: AppIcon(
        switch (attachment.kind) {
          OutgoingAttachmentKind.photo => HeroAppIcons.image,
          OutgoingAttachmentKind.video ||
          OutgoingAttachmentKind.animation => HeroAppIcons.solidFileVideo,
          OutgoingAttachmentKind.document => HeroAppIcons.file,
          OutgoingAttachmentKind.audio => HeroAppIcons.music,
        },
        size: 23,
        color: c.textSecondary,
      ),
    );
  }

  String _attachmentLabel(OutgoingAttachmentKind kind) {
    return switch (kind) {
      OutgoingAttachmentKind.photo ||
      OutgoingAttachmentKind.video ||
      OutgoingAttachmentKind.animation =>
        AppStringKeys.richTextComposerPhotoVideo.l10n(context),
      OutgoingAttachmentKind.document =>
        AppStringKeys.topicPostContentFile.l10n(context),
      OutgoingAttachmentKind.audio => AppStringKeys.composerAudio.l10n(context),
    };
  }

  String _fileName(String path) {
    final segments = File(path).uri.pathSegments;
    return segments.isEmpty ? path : segments.last;
  }

  Future<void> _editAttachment(int index) async {
    if (index < 0 || index >= _blocks.length) return;
    final item = _blocks[index].attachment;
    if (item == null) return;
    if (item.kind != OutgoingAttachmentKind.photo) return;
    final result = await Navigator.of(context).push<ImageEditResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ImageEditView(sourcePath: item.path),
      ),
    );
    if (!mounted || result == null || index >= _blocks.length) return;
    setState(() {
      _blocks[index] = _RichContentBlock.attachment(
        item.copyWith(path: result.path, clearPreviewBytes: true),
      );
    });
    if (result.caption.trim().isNotEmpty) {
      _activeTextBlock.controller.insertText(result.caption);
    }
  }

  OutgoingAttachment _attachmentFromPickedMedia(XFile file) {
    final kind = isPickedAssetVideo(file)
        ? OutgoingAttachmentKind.video
        : isPickedAssetGif(file)
        ? OutgoingAttachmentKind.animation
        : OutgoingAttachmentKind.photo;
    return OutgoingAttachment(path: file.path, kind: kind);
  }

  OutgoingAttachment _attachmentFromAppPickedAsset(AppPickedAsset asset) {
    return _attachmentFromPickedMedia(
      asset.file,
    ).copyWith(previewBytes: asset.thumbnailBytes);
  }

  void _moveBlock(int from, int to) {
    if (from < 0 || from >= _blocks.length || to < 0 || to >= _blocks.length) {
      return;
    }
    setState(() {
      final block = _blocks.removeAt(from);
      _blocks.insert(to, block);
    });
  }

  void _insertAttachmentsAfterActive(Iterable<OutgoingAttachment> attachments) {
    final items = attachments.take(_maxAttachments - _attachmentCount).toList();
    if (items.isEmpty) return;
    var index = _blocks.indexWhere((block) => block.text == _activeTextBlock);
    if (index < 0) index = _blocks.length - 1;
    final trailingText = _createTextBlock('');
    setState(() {
      _blocks.insertAll(index + 1, [
        ...items.map(_RichContentBlock.attachment),
        _RichContentBlock.text(trailingText),
      ]);
      _activeTextBlock = trailingText;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) trailingText.focusNode.requestFocus();
    });
  }

  Future<void> _pickMedia() async {
    final remaining = _maxAttachments - _attachmentCount;
    if (remaining <= 0) return;
    try {
      final picked = await AppAssetPicker.pickDetailed(
        context,
        type: AppAssetPickerType.imageAndVideo,
        maxAssets: remaining,
      );
      if (picked.assets.isEmpty || !mounted) return;
      _insertAttachmentsAfterActive(
        picked.assets.map(_attachmentFromAppPickedAsset),
      );
    } catch (_) {}
  }

  Future<void> _pickFiles() async {
    final remaining = _maxAttachments - _attachmentCount;
    if (remaining <= 0) return;
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (!mounted || result == null) return;
      final paths = result.files.map((file) => file.path).whereType<String>();
      _insertAttachmentsAfterActive(
        paths
            .take(remaining)
            .map(
              (path) => OutgoingAttachment(
                path: path,
                kind: OutgoingAttachmentKind.document,
              ),
            ),
      );
    } catch (_) {}
  }

  Future<void> _pickMusic() async {
    final remaining = _maxAttachments - _attachmentCount;
    if (remaining <= 0) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: const [
          'mp3',
          'm4a',
          'aac',
          'flac',
          'wav',
          'ogg',
          'opus',
          'amr',
        ],
      );
      if (!mounted || result == null) return;
      final paths = result.files.map((file) => file.path).whereType<String>();
      _insertAttachmentsAfterActive(
        paths
            .take(remaining)
            .map(
              (path) => OutgoingAttachment(
                path: path,
                kind: OutgoingAttachmentKind.audio,
              ),
            ),
      );
    } catch (_) {}
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
              ? AppTheme.brand.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: active
              ? Border.all(color: AppTheme.brand.withValues(alpha: 0.5))
              : null,
        ),
        child: Text(
          label,
          style: AppTextStyle.callout(
            active ? AppTheme.brand : c.textPrimary,
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
}
