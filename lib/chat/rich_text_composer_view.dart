import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../components/app_icons.dart';
import '../components/toast.dart';
import '../media/app_asset_picker.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'emoji_text_controller.dart';
import 'image_edit_view.dart';
import 'location_picker_view.dart';
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

enum _RichCellHorizontalAlignment { left, center, right }

enum _RichCellVerticalAlignment { top, middle, bottom }

enum _RichTableMenuAction {
  addRowAbove,
  addRowBelow,
  addColumnLeft,
  addColumnRight,
  toggleHeader,
  alignLeft,
  alignCenter,
  alignRight,
  alignTop,
  alignMiddle,
  alignBottom,
  toggleBorderless,
  toggleStriped,
  removeRow,
  removeColumn,
  removeTable,
}

class _RichTableCellStyle {
  _RichTableCellStyle({this.isHeader = false});

  bool isHeader;
  _RichCellHorizontalAlignment horizontal = _RichCellHorizontalAlignment.left;
  _RichCellVerticalAlignment vertical = _RichCellVerticalAlignment.top;
}

class _RichTableDraft {
  _RichTableDraft({int rows = 3, int columns = 3, String title = ''})
    : title = TextEditingController(text: title),
      cells = List.generate(
        rows,
        (row) => List.generate(
          columns,
          (column) => TextEditingController(
            text: row == 0 ? 'Column ${column + 1}' : '',
          ),
        ),
      ),
      styles = List.generate(
        rows,
        (row) => List.generate(
          columns,
          (_) => _RichTableCellStyle(isHeader: row == 0),
        ),
      );

  static const maxColumns = 20;

  final TextEditingController title;
  final List<List<TextEditingController>> cells;
  final List<List<_RichTableCellStyle>> styles;
  bool bordered = true;
  bool striped = true;

  int get rowCount => cells.length;
  int get columnCount => cells.isEmpty ? 0 : cells.first.length;

  void dispose() {
    title.dispose();
    for (final row in cells) {
      for (final cell in row) {
        cell.dispose();
      }
    }
  }

  void addRow() {
    insertRow(rowCount);
  }

  void insertRow(int index) {
    final safeIndex = index.clamp(0, rowCount);
    cells.insert(
      safeIndex,
      List.generate(columnCount, (_) => TextEditingController()),
    );
    styles.insert(
      safeIndex,
      List.generate(columnCount, (_) => _RichTableCellStyle()),
    );
  }

  void removeRowAt(int index) {
    if (rowCount <= 1 || index < 0 || index >= rowCount) return;
    final removed = cells.removeAt(index);
    styles.removeAt(index);
    for (final cell in removed) {
      cell.dispose();
    }
  }

  void addColumn() {
    insertColumn(columnCount);
  }

  void insertColumn(int index) {
    if (columnCount >= maxColumns) return;
    final oldColumnCount = columnCount;
    final safeIndex = index.clamp(0, oldColumnCount);
    for (var row = 0; row < cells.length; row++) {
      cells[row].insert(
        safeIndex,
        TextEditingController(
          text: row == 0 ? 'Column ${oldColumnCount + 1}' : '',
        ),
      );
      styles[row].insert(safeIndex, _RichTableCellStyle(isHeader: row == 0));
    }
  }

  void removeColumnAt(int index) {
    if (columnCount <= 1 || index < 0 || index >= columnCount) return;
    for (var row = 0; row < cells.length; row++) {
      cells[row].removeAt(index).dispose();
      styles[row].removeAt(index);
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
    final tableTitle = title.text.trim();
    if (tableTitle.isNotEmpty) {
      buffer
        ..writeln(tableTitle)
        ..writeln();
    }
    buffer.writeln(_markdownRow(rows.first, widths));
    buffer.writeln(_markdownRow(widths.map((w) => '-' * w).toList(), widths));
    for (final row in rows.skip(1)) {
      buffer.writeln(_markdownRow(row, widths));
    }
    return buffer.toString().trimRight();
  }

  String toHtml() {
    if (cells.isEmpty || cells.first.isEmpty) return '';
    final tableAttributes = [if (bordered) 'bordered', if (striped) 'striped'];
    final buffer = StringBuffer(
      '<table${tableAttributes.isEmpty ? '' : ' ${tableAttributes.join(' ')}'}>',
    );
    final tableTitle = title.text.trim();
    if (tableTitle.isNotEmpty) {
      buffer
        ..write('<caption>')
        ..write(escapeRichHtml(tableTitle))
        ..write('</caption>');
    }
    for (var rowIndex = 0; rowIndex < cells.length; rowIndex++) {
      buffer.write('<tr>');
      for (
        var columnIndex = 0;
        columnIndex < cells[rowIndex].length;
        columnIndex++
      ) {
        final cell = cells[rowIndex][columnIndex];
        final style = styles[rowIndex][columnIndex];
        final tag = style.isHeader ? 'th' : 'td';
        buffer
          ..write(
            '<$tag align="${style.horizontal.name}" '
            'valign="${style.vertical.name}">',
          )
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

enum _RichBlockKind {
  paragraph,
  heading,
  preformatted,
  footer,
  divider,
  mathematicalExpression,
  anchor,
  list,
  blockQuotation,
  pullQuotation,
  collage,
  slideshow,
  table,
  details,
  map,
  animation,
  audio,
  photo,
  video,
  voiceNote,
  thinking,
  document,
}

class _RichTextBlock {
  _RichTextBlock(
    this.controller,
    this.focusNode,
    this.onTextChanged, {
    this.kind = _RichBlockKind.paragraph,
  }) : lastText = controller.text;

  final EmojiTextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onTextChanged;
  final _RichBlockKind kind;
  String lastText;
  int headingLevel = 0;
}

class _RichMathDraft {
  _RichMathDraft() : controller = TextEditingController(text: r'E = mc^2');

  final TextEditingController controller;

  void dispose() => controller.dispose();
}

class _RichGenericDraft {
  _RichGenericDraft({
    String primary = '',
    String secondary = '',
    String tertiary = '',
    this.number = 14,
  }) : primary = TextEditingController(text: primary),
       secondary = TextEditingController(text: secondary),
       tertiary = TextEditingController(text: tertiary),
       enabled = false;

  final TextEditingController primary;
  final TextEditingController secondary;
  final TextEditingController tertiary;
  int number;
  bool enabled;

  void dispose() {
    primary.dispose();
    secondary.dispose();
    tertiary.dispose();
  }
}

class _RichMediaGroupDraft {
  _RichMediaGroupDraft(this.kind) : caption = TextEditingController();

  final _RichBlockKind kind;
  final List<OutgoingAttachment> items = [];
  final TextEditingController caption;

  void dispose() => caption.dispose();
}

class _RichContentBlock {
  _RichContentBlock._({
    required this.kind,
    this.text,
    this.table,
    this.math,
    this.attachment,
    this.generic,
    this.mediaGroup,
  }) : id = _nextId++;

  factory _RichContentBlock.text(_RichTextBlock text, {_RichBlockKind? kind}) =>
      _RichContentBlock._(kind: kind ?? text.kind, text: text);

  factory _RichContentBlock.table(_RichTableDraft table) =>
      _RichContentBlock._(kind: _RichBlockKind.table, table: table);

  factory _RichContentBlock.math(_RichMathDraft math) => _RichContentBlock._(
    kind: _RichBlockKind.mathematicalExpression,
    math: math,
  );

  factory _RichContentBlock.attachment(
    OutgoingAttachment attachment, {
    _RichBlockKind? kind,
  }) => _RichContentBlock._(
    kind: kind ?? _kindForAttachment(attachment),
    attachment: attachment,
  );

  factory _RichContentBlock.generic(
    _RichBlockKind kind,
    _RichGenericDraft generic,
  ) => _RichContentBlock._(kind: kind, generic: generic);

  factory _RichContentBlock.mediaGroup(_RichMediaGroupDraft group) =>
      _RichContentBlock._(kind: group.kind, mediaGroup: group);

  static int _nextId = 1;

  static _RichBlockKind _kindForAttachment(OutgoingAttachment attachment) {
    return switch (attachment.kind) {
      OutgoingAttachmentKind.photo => _RichBlockKind.photo,
      OutgoingAttachmentKind.video => _RichBlockKind.video,
      OutgoingAttachmentKind.animation => _RichBlockKind.animation,
      OutgoingAttachmentKind.audio => _RichBlockKind.audio,
      OutgoingAttachmentKind.document => _RichBlockKind.document,
    };
  }

  final int id;
  final _RichBlockKind kind;

  final _RichTextBlock? text;
  final _RichTableDraft? table;
  final _RichMathDraft? math;
  final OutgoingAttachment? attachment;
  final _RichGenericDraft? generic;
  final _RichMediaGroupDraft? mediaGroup;
}

class _RichTextComposerViewState extends State<RichTextComposerView> {
  static const _maxAttachments = 50;
  static const _maxBlocks = 500;
  static const _maxTextCharacters = telegramRichMessageMaxCharacters;

  late final List<_RichContentBlock> _blocks;
  late _RichTextBlock _activeTextBlock;

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
    _RichBlockKind kind = _RichBlockKind.paragraph,
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

    block = _RichTextBlock(controller, focusNode, onTextChanged, kind: kind);
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
    block.generic?.dispose();
    block.mediaGroup?.dispose();
  }

  void _submit() {
    if (_blocks.length > _maxBlocks ||
        _documentTextCharacterCount() > _maxTextCharacters ||
        _attachmentCount > _maxAttachments) {
      showToast(
        context,
        AppStringKeys.richTextComposerLimitExceeded.l10n(context),
      );
      return;
    }
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
      final mediaGroup = block.mediaGroup;
      if (mediaGroup != null) {
        if (mediaGroup.items.isEmpty) continue;
        flushAttachments();
        final tag = mediaGroup.kind == _RichBlockKind.collage
            ? 'tg-collage'
            : 'tg-slideshow';
        htmlBuffer.write('<$tag>');
        for (final item in mediaGroup.items) {
          attachments.add(item);
          final id = 'mithka-rich-${segments.length}-${htmlFiles.length}';
          htmlFiles.add(RichMessageSendFile(id: id, attachment: item));
          htmlBuffer.write(_mediaBlockHtml(item, id));
        }
        final caption = mediaGroup.caption.text.trim();
        if (caption.isNotEmpty) {
          htmlBuffer.write(
            '<figcaption>${escapeRichHtml(caption)}</figcaption>',
          );
        }
        htmlBuffer.write('</$tag>');
        continue;
      }
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
        htmlBuffer.write(_mediaBlockHtml(attachment, id));
        continue;
      }
      flushAttachments();
      String text;
      List<Map<String, dynamic>> blockEntities = const [];
      if (block.text != null) {
        final formatted = block.text!.controller.toFormatted();
        text = formatted.$1;
        blockEntities = formatted.$2;
        htmlBuffer.write(_textBlockHtml(block.text!, text, blockEntities));
      } else if (block.math != null) {
        text = block.math!.controller.text.trim();
        if (text.isNotEmpty) {
          htmlBuffer.write(
            '<tg-math-block>${escapeRichHtml(text)}</tg-math-block>',
          );
        }
      } else if (block.table != null) {
        text = block.table?.toMarkdown() ?? '';
        htmlBuffer.write(block.table?.toHtml() ?? '');
      } else {
        text = block.generic?.primary.text.trim() ?? '';
        htmlBuffer.write(_genericBlockHtml(block));
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

  int _documentTextCharacterCount() {
    final text = StringBuffer();
    for (final block in _blocks) {
      text.write(block.text?.controller.text ?? '');
      text.write(block.math?.controller.text ?? '');
      final generic = block.generic;
      if (generic != null) {
        text
          ..write(generic.primary.text)
          ..write(generic.secondary.text)
          ..write(generic.tertiary.text);
      }
      final group = block.mediaGroup;
      if (group != null) text.write(group.caption.text);
      final table = block.table;
      if (table != null) {
        for (final row in table.cells) {
          for (final cell in row) {
            text.write(cell.text);
          }
        }
      }
    }
    return telegramUtf8CharacterCount(text.toString());
  }

  String _mediaBlockHtml(OutgoingAttachment attachment, String id) {
    return switch (attachment.kind) {
      OutgoingAttachmentKind.photo => '<img src="$id"/>',
      OutgoingAttachmentKind.video ||
      OutgoingAttachmentKind.animation => '<video src="$id"></video>',
      OutgoingAttachmentKind.audio => '<audio src="$id"></audio>',
      OutgoingAttachmentKind.document => '',
    };
  }

  String _textBlockHtml(
    _RichTextBlock block,
    String text,
    List<Map<String, dynamic>> entities,
  ) {
    if (text.trim().isEmpty) return '';
    final inline = formattedTextToRichInlineHtml(text, entities);
    return switch (block.kind) {
      _RichBlockKind.heading =>
        '<h${block.headingLevel.clamp(1, 6)}>$inline</h${block.headingLevel.clamp(1, 6)}>',
      _RichBlockKind.preformatted => '<pre>$inline</pre>',
      _RichBlockKind.footer => '<footer>$inline</footer>',
      _RichBlockKind.list => formattedTextToRichHtml(text, entities),
      _RichBlockKind.blockQuotation =>
        '<blockquote><p>$inline</p></blockquote>',
      _RichBlockKind.pullQuotation => '<aside>$inline</aside>',
      _RichBlockKind.thinking => '<tg-thinking>$inline</tg-thinking>',
      _ => '<p>$inline</p>',
    };
  }

  String _genericBlockHtml(_RichContentBlock block) {
    final draft = block.generic;
    if (draft == null) {
      return block.kind == _RichBlockKind.divider ? '<hr/>' : '';
    }
    final primary = escapeRichHtml(draft.primary.text.trim());
    final secondary = escapeRichHtml(draft.secondary.text.trim());
    return switch (block.kind) {
      _RichBlockKind.anchor => primary.isEmpty ? '' : '<a name="$primary"></a>',
      _RichBlockKind.details =>
        '<details${draft.enabled ? ' open' : ''}><summary>$primary</summary><p>$secondary</p></details>',
      _RichBlockKind.map =>
        '<tg-map lat="${draft.primary.text.trim()}" long="${draft.secondary.text.trim()}" zoom="${draft.number.clamp(13, 20)}"/>',
      _ => '',
    };
  }

  Map<String, dynamic> _shiftTextEntity(Map<String, dynamic> entity, int by) {
    return {
      ...entity,
      'offset': ((entity['offset'] as int?) ?? 0) + by,
      if (entity['type'] is Map<String, dynamic>)
        'type': Map<String, dynamic>.of(entity['type'] as Map<String, dynamic>),
    };
  }

  void _insertTable() {
    final tableNumber =
        _blocks.where((block) => block.table != null).length + 1;
    _insertStructuredBlock(
      _RichContentBlock.table(
        _RichTableDraft(
          title:
              '${AppStringKeys.richTextComposerInsertTable.l10n(context)} $tableNumber',
        ),
      ),
    );
  }

  void _insertMathBlock() {
    _insertStructuredBlock(_RichContentBlock.math(_RichMathDraft()));
  }

  void _insertStructuredBlock(_RichContentBlock block) {
    if (_blocks.length >= _maxBlocks) {
      _disposeBlock(block);
      return;
    }
    final active = _activeTextBlock;
    final index = _blocks.indexWhere((item) => item.text == active);
    void focusAfterFrame(_RichTextBlock? target) {
      if (target == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) target.focusNode.requestFocus();
      });
    }

    if (index < 0) {
      final insertedText = block.text;
      setState(() {
        _blocks.add(block);
        if (insertedText != null) _activeTextBlock = insertedText;
      });
      focusAfterFrame(insertedText);
      return;
    }
    final controller = active.controller;
    final text = controller.text;
    final selection = controller.selection;
    final start = selection.isValid
        ? math.min(selection.start, selection.end)
        : text.length;
    final end = selection.isValid
        ? math.max(selection.start, selection.end)
        : text.length;
    final before = text.substring(0, start);
    final after = text.substring(end);
    if (before.isEmpty && after.isEmpty) {
      final removed = _blocks[index];
      final insertedText = block.text;
      setState(() {
        _blocks[index] = block;
        if (insertedText != null) _activeTextBlock = insertedText;
      });
      _disposeBlock(removed);
      focusAfterFrame(insertedText);
      return;
    }
    if (start == 0 && end == 0) {
      final insertedText = block.text;
      setState(() {
        _blocks.insert(index, block);
        if (insertedText != null) _activeTextBlock = insertedText;
      });
      focusAfterFrame(insertedText);
      return;
    }
    if (start == text.length && end == text.length) {
      final insertedText = block.text;
      setState(() {
        _blocks.insert(index + 1, block);
        if (insertedText != null) _activeTextBlock = insertedText;
      });
      focusAfterFrame(insertedText);
      return;
    }
    controller.value = TextEditingValue(
      text: before,
      selection: TextSelection.collapsed(offset: before.length),
    );
    final nextText = after.isEmpty ? null : _createTextBlock(after);
    final insertedText = block.text;
    final focusTarget = insertedText ?? nextText;
    setState(() {
      _blocks.insert(index + 1, block);
      if (nextText != null) {
        _blocks.insert(index + 2, _RichContentBlock.text(nextText));
      }
      if (focusTarget != null) _activeTextBlock = focusTarget;
    });
    focusAfterFrame(focusTarget);
  }

  _RichContentBlock _newTextContentBlock(
    _RichBlockKind kind, {
    String text = '',
  }) {
    final block = _createTextBlock(text, kind: kind);
    if (kind == _RichBlockKind.heading) block.headingLevel = 1;
    return _RichContentBlock.text(block, kind: kind);
  }

  Future<void> _insertBlockKind(_RichBlockKind kind) async {
    switch (kind) {
      case _RichBlockKind.paragraph:
      case _RichBlockKind.heading:
      case _RichBlockKind.preformatted:
      case _RichBlockKind.footer:
      case _RichBlockKind.list:
      case _RichBlockKind.blockQuotation:
      case _RichBlockKind.pullQuotation:
      case _RichBlockKind.thinking:
        _insertStructuredBlock(
          _newTextContentBlock(
            kind,
            text: kind == _RichBlockKind.list ? '- ' : '',
          ),
        );
      case _RichBlockKind.divider:
        _insertStructuredBlock(
          _RichContentBlock.generic(kind, _RichGenericDraft()),
        );
      case _RichBlockKind.mathematicalExpression:
        _insertMathBlock();
      case _RichBlockKind.anchor:
        _insertStructuredBlock(
          _RichContentBlock.generic(
            kind,
            _RichGenericDraft(primary: 'section'),
          ),
        );
      case _RichBlockKind.table:
        _insertTable();
      case _RichBlockKind.details:
        _insertStructuredBlock(
          _RichContentBlock.generic(
            kind,
            _RichGenericDraft(primary: 'Details'),
          ),
        );
      case _RichBlockKind.map:
        final start = await resolveLocationPickerStart();
        if (!mounted) return;
        _insertStructuredBlock(
          _RichContentBlock.generic(
            kind,
            _RichGenericDraft(
              primary: start.latitude.toStringAsFixed(6),
              secondary: start.longitude.toStringAsFixed(6),
              number: 16,
            ),
          ),
        );
      case _RichBlockKind.collage:
      case _RichBlockKind.slideshow:
        final group = _RichMediaGroupDraft(kind);
        _insertStructuredBlock(_RichContentBlock.mediaGroup(group));
      case _RichBlockKind.photo:
      case _RichBlockKind.video:
        await _pickSingleVisualBlock(kind);
      case _RichBlockKind.animation:
      case _RichBlockKind.audio:
      case _RichBlockKind.voiceNote:
        await _pickSingleFileBlock(kind);
      case _RichBlockKind.document:
        await _pickFiles();
    }
  }

  Future<void> _pickSingleVisualBlock(_RichBlockKind kind) async {
    final picked = await AppAssetPicker.pickDetailed(
      context,
      type: kind == _RichBlockKind.photo
          ? AppAssetPickerType.image
          : AppAssetPickerType.video,
      maxAssets: 1,
    );
    if (!mounted || picked.assets.isEmpty) return;
    final attachment = _attachmentFromAppPickedAsset(picked.assets.first);
    _insertStructuredBlock(
      _RichContentBlock.attachment(attachment, kind: kind),
    );
  }

  Future<void> _pickSingleFileBlock(_RichBlockKind kind) async {
    final extensions = switch (kind) {
      _RichBlockKind.animation => const ['gif', 'webm', 'mp4'],
      _RichBlockKind.voiceNote => const ['ogg', 'opus', 'm4a'],
      _ => const ['mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg', 'opus'],
    };
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    if (!mounted || result == null || result.files.single.path == null) return;
    final attachmentKind = kind == _RichBlockKind.animation
        ? OutgoingAttachmentKind.animation
        : OutgoingAttachmentKind.audio;
    _insertStructuredBlock(
      _RichContentBlock.attachment(
        OutgoingAttachment(
          path: result.files.single.path!,
          kind: attachmentKind,
        ),
        kind: kind,
      ),
    );
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
                return ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.manual,
                  padding: EdgeInsets.only(bottom: 18 + keyboardInset),
                  itemCount: _blocks.length,
                  onReorderItem: _reorderBlock,
                  proxyDecorator: (child, index, animation) => Material(
                    type: MaterialType.transparency,
                    child: FadeTransition(
                      opacity: Tween<double>(begin: 0.82, end: 1).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                      child: child,
                    ),
                  ),
                  itemBuilder: (context, index) {
                    final block = _blocks[index];
                    return KeyedSubtree(
                      key: ValueKey(block.id),
                      child: _draggableBlock(c, constraints.maxHeight, index),
                    );
                  },
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

  void _reorderBlock(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    setState(() {
      final block = _blocks.removeAt(oldIndex);
      _blocks.insert(newIndex, block);
    });
  }

  void _moveBlock(int blockId, int offset) {
    final index = _blocks.indexWhere((block) => block.id == blockId);
    if (index < 0) return;
    final target = index + offset;
    if (target < 0 || target >= _blocks.length) return;
    setState(() {
      final block = _blocks.removeAt(index);
      _blocks.insert(target, block);
    });
  }

  void _removeBlockById(int blockId) {
    final index = _blocks.indexWhere((block) => block.id == blockId);
    if (index < 0) return;
    setState(() {
      final removed = _blocks.removeAt(index);
      _disposeBlock(removed);
      if (_blocks.isEmpty || !_blocks.any((block) => block.text != null)) {
        final text = _createTextBlock('');
        final insertionIndex = index.clamp(0, _blocks.length);
        _blocks.insert(insertionIndex, _RichContentBlock.text(text));
        _activeTextBlock = text;
      }
    });
  }

  Future<void> _showBlockActions(Offset anchor, int blockId) async {
    final index = _blocks.indexWhere((block) => block.id == blockId);
    if (index < 0) return;
    final action = await showGeneralDialog<_RichBlockAction>(
      context: context,
      barrierDismissible: true,
      barrierLabel: AppStringKeys.countryPickerCancel.l10n(context),
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (dialogContext, _, _) => _RichBlockActionMenu(
        anchor: anchor,
        canMoveUp: index > 0,
        canMoveDown: index < _blocks.length - 1,
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _RichBlockAction.moveUp:
        _moveBlock(blockId, -1);
      case _RichBlockAction.moveDown:
        _moveBlock(blockId, 1);
      case _RichBlockAction.delete:
        _removeBlockById(blockId);
    }
  }

  Widget _draggableBlock(AppColors c, double availableHeight, int index) {
    final blockId = _blocks[index].id;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReorderableDragStartListener(
          index: index,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) =>
                unawaited(_showBlockActions(details.globalPosition, blockId)),
            onLongPressStart: (details) =>
                unawaited(_showBlockActions(details.globalPosition, blockId)),
            child: Container(
              width: 30,
              constraints: const BoxConstraints(minHeight: 40),
              alignment: Alignment.topCenter,
              padding: const EdgeInsets.only(top: 11),
              child: AppIcon(
                HeroAppIcons.ellipsis,
                size: 17,
                color: c.textTertiary,
              ),
            ),
          ),
        ),
        Expanded(child: _contentBlock(c, availableHeight, index)),
      ],
    );
  }

  Widget _contentBlock(AppColors c, double availableHeight, int index) {
    final block = _blocks[index];
    final text = block.text;
    if (text != null) {
      return _textEditor(c, availableHeight, text, index);
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
    if (table == null) {
      final group = block.mediaGroup;
      if (group != null) return _mediaGroupEditor(c, index, group);
      final generic = block.generic;
      if (generic != null || block.kind == _RichBlockKind.divider) {
        return _genericBlockEditor(c, index, block);
      }
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 12, 2),
      child: _tableEditor(c, table),
    );
  }

  Widget _textEditor(
    AppColors c,
    double availableHeight,
    _RichTextBlock block,
    int index,
  ) {
    final baseStyle = TextStyle(
      fontSize: switch (block.kind) {
        _RichBlockKind.heading => 21,
        _RichBlockKind.footer => 14,
        _ => 16,
      },
      height: 1.3,
      color: block.kind == _RichBlockKind.footer
          ? c.textSecondary
          : c.textPrimary,
      fontStyle: block.kind == _RichBlockKind.pullQuotation
          ? FontStyle.italic
          : null,
      fontWeight: block.kind == _RichBlockKind.heading ? FontWeight.w600 : null,
    );
    final field = TextField(
      controller: block.controller,
      focusNode: block.focusNode,
      autofocus: block == _blocks.first.text,
      minLines: 1,
      maxLines: null,
      textAlign: block.kind == _RichBlockKind.pullQuotation
          ? TextAlign.center
          : TextAlign.start,
      textAlignVertical: TextAlignVertical.top,
      contextMenuBuilder: (context, editableTextState) =>
          _richTextContextMenu(context, editableTextState, index),
      style: block.kind == _RichBlockKind.preformatted
          ? context.watch<ThemeController>().codeTextStyle(baseStyle)
          : baseStyle,
      decoration: InputDecoration(
        contentPadding: EdgeInsets.fromLTRB(
          block.kind == _RichBlockKind.blockQuotation ? 10 : 4,
          8,
          block.kind == _RichBlockKind.blockQuotation ? 34 : 12,
          6,
        ),
        border: InputBorder.none,
        hintText: block.kind == _RichBlockKind.paragraph && !_hasAnyText
            ? widget.hintText.l10n(context)
            : block.kind.labelKey.l10n(context),
        hintStyle: TextStyle(color: c.textTertiary),
      ),
    );
    final editor = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 38,
        maxHeight: math.min(260, availableHeight),
      ),
      child: field,
    );
    return switch (block.kind) {
      _RichBlockKind.blockQuotation => Padding(
        padding: const EdgeInsets.fromLTRB(2, 2, 12, 2),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppTheme.brand.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(7),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: AppTheme.brand),
                Expanded(
                  child: Stack(
                    children: [
                      editor,
                      Positioned(
                        right: 8,
                        top: 3,
                        child: IgnorePointer(
                          child: Text(
                            '”',
                            style: TextStyle(
                              color: AppTheme.brand,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                          ),
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
      _RichBlockKind.preformatted => Padding(
        padding: const EdgeInsets.fromLTRB(2, 2, 12, 2),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.searchFill,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: c.divider, width: 0.5),
          ),
          child: editor,
        ),
      ),
      _RichBlockKind.pullQuotation => Padding(
        padding: const EdgeInsets.fromLTRB(4, 3, 12, 3),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.symmetric(
              horizontal: BorderSide(color: c.divider, width: 0.5),
            ),
          ),
          child: editor,
        ),
      ),
      _ => editor,
    };
  }

  Widget _richTextContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
    int blockIndex,
  ) {
    ContextMenuButtonItem? paste;
    final items = <ContextMenuButtonItem>[];
    for (final item in editableTextState.contextMenuButtonItems) {
      if (item.type == ContextMenuButtonType.paste) {
        paste = item;
      } else {
        items.add(item);
      }
    }
    final copyIndex = items.indexWhere(
      (item) => item.type == ContextMenuButtonType.copy,
    );
    var insertAt = copyIndex < 0 ? 0 : copyIndex + 1;
    if (paste != null) items.insert(insertAt++, paste);
    final selection = _blocks[blockIndex].text?.controller.selection;
    if (selection?.isValid == true && selection?.isCollapsed == false) {
      items.insert(
        insertAt++,
        ContextMenuButtonItem(
          label: AppStringKeys.composerFormat.l10n(context),
          onPressed: () => unawaited(
            _showRichInlineFormatMenu(editableTextState, blockIndex),
          ),
        ),
      );
    }
    items.insert(
      insertAt,
      ContextMenuButtonItem(
        label: AppStringKeys.richTextComposerInsert.l10n(context),
        onPressed: () =>
            unawaited(_showRichBlockInsertMenu(editableTextState, blockIndex)),
      ),
    );
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: items,
    );
  }

  Future<void> _showRichInlineFormatMenu(
    EditableTextState editableTextState,
    int blockIndex,
  ) async {
    if (blockIndex < 0 || blockIndex >= _blocks.length) return;
    final textBlock = _blocks[blockIndex].text;
    if (textBlock == null) return;
    _activeTextBlock = textBlock;
    final selection = textBlock.controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    final start = math.min(selection.start, selection.end);
    final end = math.max(selection.start, selection.end);
    final anchor = editableTextState.contextMenuAnchors.primaryAnchor;
    editableTextState.hideToolbar();
    final action = await showGeneralDialog<_RichInlineFormatAction>(
      context: context,
      barrierDismissible: true,
      barrierLabel: AppStringKeys.countryPickerCancel.l10n(context),
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (dialogContext, _, _) =>
          _RichInlineFormatMenu(anchor: anchor),
    );
    if (!mounted || action == null) return;
    textBlock.controller.selection = TextSelection(
      baseOffset: start,
      extentOffset: end,
    );
    if (action == _RichInlineFormatAction.link) {
      final url = await _showRichValueDialog(
        AppStringKeys.composerFormatLink,
        AppStringKeys.composerFormatLinkPlaceholder,
      );
      if (!mounted || url == null || url.trim().isEmpty) return;
      final parsed = Uri.tryParse(url.trim());
      textBlock.controller.applyEntityFormat(start, end, {
        '@type': 'textEntityTypeTextUrl',
        'url': parsed?.hasScheme == true ? url.trim() : 'https://${url.trim()}',
      });
    } else {
      textBlock.controller.toggleFormat(action.entityType);
    }
    textBlock.controller.selection = TextSelection(
      baseOffset: start,
      extentOffset: end,
    );
    textBlock.focusNode.requestFocus();
  }

  Future<void> _showRichBlockInsertMenu(
    EditableTextState editableTextState,
    int blockIndex,
  ) async {
    if (blockIndex < 0 || blockIndex >= _blocks.length) return;
    final textBlock = _blocks[blockIndex].text;
    if (textBlock != null) _activeTextBlock = textBlock;
    final anchor = editableTextState.contextMenuAnchors.primaryAnchor;
    editableTextState.hideToolbar();
    await _showRichBlockInsertMenuAt(anchor);
  }

  Future<void> _showRichBlockInsertMenuAt(Offset anchor) async {
    final kind = await showGeneralDialog<_RichBlockKind>(
      context: context,
      barrierDismissible: true,
      barrierLabel: AppStringKeys.countryPickerCancel.l10n(context),
      barrierColor: Colors.black.withValues(alpha: 0.18),
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (dialogContext, _, _) =>
          _RichBlockInsertMenu(anchor: anchor),
    );
    if (!mounted || kind == null) return;
    await _insertBlockKind(kind);
  }

  Future<String?> _showRichValueDialog(String title, String hint) {
    return showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: AppStringKeys.countryPickerCancel.l10n(context),
      barrierColor: Colors.black.withValues(alpha: 0.36),
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (dialogContext, _, _) =>
          _RichValueDialog(title: title, hint: hint),
    );
  }

  bool get _hasAnyText => _blocks.any(
    (block) => block.text?.controller.text.trim().isNotEmpty ?? false,
  );

  Widget _genericBlockEditor(AppColors c, int index, _RichContentBlock block) {
    if (block.kind == _RichBlockKind.map) {
      return _mapBlockEditor(c, index, block.generic!);
    }
    if (block.kind == _RichBlockKind.divider) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
        child: Row(
          children: [
            Expanded(child: Divider(color: c.divider)),
            _miniIconButton(
              c,
              icon: HeroAppIcons.trash,
              label: AppStringKeys.richTextComposerRemoveBlock.l10n(context),
              destructive: true,
              onTap: () => _removeStructuredBlock(index),
            ),
          ],
        ),
      );
    }
    final draft = block.generic!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 12, 2),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.divider, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    block.kind.labelKey.l10n(context),
                    style: AppTextStyle.callout(
                      c.textPrimary,
                      weight: AppTextWeight.semibold,
                    ),
                  ),
                ),
                _miniIconButton(
                  c,
                  icon: HeroAppIcons.trash,
                  label: AppStringKeys.richTextComposerRemoveBlock.l10n(
                    context,
                  ),
                  destructive: true,
                  onTap: () => _removeStructuredBlock(index),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (block.kind == _RichBlockKind.anchor)
              _compactBlockField(
                c,
                draft.primary,
                AppStringKeys.richTextComposerAnchorName,
              ),
            if (block.kind == _RichBlockKind.details) ...[
              _compactBlockField(
                c,
                draft.primary,
                AppStringKeys.richTextComposerDetailsSummary,
              ),
              const SizedBox(height: 6),
              _compactBlockField(
                c,
                draft.secondary,
                AppStringKeys.richTextComposerDetailsContent,
                maxLines: 4,
              ),
              const SizedBox(height: 6),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => draft.enabled = !draft.enabled),
                child: Row(
                  children: [
                    AppIcon(
                      draft.enabled
                          ? HeroAppIcons.circleCheck
                          : HeroAppIcons.circle,
                      size: 19,
                      color: draft.enabled ? AppTheme.brand : c.textTertiary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      AppStringKeys.richTextComposerDetailsOpen.l10n(context),
                      style: AppTextStyle.callout(c.textPrimary),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _editMapBlock(int index, _RichGenericDraft draft) async {
    final latitude =
        double.tryParse(draft.primary.text.trim()) ??
        defaultLocationPickerCenter.latitude;
    final longitude =
        double.tryParse(draft.secondary.text.trim()) ??
        defaultLocationPickerCenter.longitude;
    final picked = await Navigator.of(context).push<LocationPickerResult>(
      MaterialPageRoute(
        builder: (_) => LocationPickerView(
          initial: LatLng(latitude, longitude),
          initialZoom: draft.number.toDouble(),
          returnCamera: true,
        ),
      ),
    );
    if (!mounted || picked == null || index >= _blocks.length) return;
    setState(() {
      draft.primary.text = picked.center.latitude.toStringAsFixed(6);
      draft.secondary.text = picked.center.longitude.toStringAsFixed(6);
      draft.number = picked.zoom.round().clamp(13, 20);
    });
  }

  Widget _mapBlockEditor(AppColors c, int index, _RichGenericDraft draft) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 12, 2),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(_editMapBlock(index, draft)),
        child: Container(
          constraints: const BoxConstraints(minHeight: 68),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.divider, width: 0.5),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.brand.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: AppIcon(
                  HeroAppIcons.locationPin,
                  size: 22,
                  color: AppTheme.brand,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _RichBlockKind.map.labelKey.l10n(context),
                      style: AppTextStyle.callout(
                        c.textPrimary,
                        weight: AppTextWeight.semibold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${draft.primary.text}, ${draft.secondary.text} · '
                      '${AppStringKeys.richTextComposerMapZoom.l10n(context)} ${draft.number}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.caption(c.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AppIcon(
                HeroAppIcons.chevronRight,
                size: 16,
                color: c.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _compactBlockField(
    AppColors c,
    TextEditingController controller,
    String hint, {
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: c.searchFill,
        borderRadius: BorderRadius.circular(6),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        onChanged: (_) => setState(() {}),
        style: AppTextStyle.callout(c.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 9,
          ),
          hintText: hint.l10n(context),
          hintStyle: AppTextStyle.callout(c.textTertiary),
        ),
      ),
    );
  }

  Widget _mediaGroupEditor(AppColors c, int index, _RichMediaGroupDraft group) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 12, 2),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.divider, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    group.kind.labelKey.l10n(context),
                    style: AppTextStyle.callout(
                      c.textPrimary,
                      weight: AppTextWeight.semibold,
                    ),
                  ),
                ),
                _textMiniButton(
                  c,
                  '+',
                  _attachmentCount >= _maxAttachments
                      ? null
                      : () => unawaited(_pickMediaForGroup(index)),
                ),
                _miniIconButton(
                  c,
                  icon: HeroAppIcons.trash,
                  label: AppStringKeys.richTextComposerRemoveBlock.l10n(
                    context,
                  ),
                  destructive: true,
                  onTap: () => _removeStructuredBlock(index),
                ),
              ],
            ),
            if (group.items.isNotEmpty) ...[
              const SizedBox(height: 6),
              SizedBox(
                height: 74,
                child: ReorderableListView.builder(
                  scrollDirection: Axis.horizontal,
                  buildDefaultDragHandles: false,
                  itemCount: group.items.length,
                  onReorderItem: (oldIndex, newIndex) {
                    setState(() {
                      final item = group.items.removeAt(oldIndex);
                      group.items.insert(newIndex, item);
                    });
                  },
                  itemBuilder: (context, mediaIndex) {
                    final item = group.items[mediaIndex];
                    return ReorderableDragStartListener(
                      key: ValueKey('${item.path}-$mediaIndex'),
                      index: mediaIndex,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: _attachmentPreview(
                            c,
                            item,
                            width: 74,
                            height: 74,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 6),
            _compactBlockField(
              c,
              group.caption,
              AppStringKeys.imageEditCaptionInputPlaceholder,
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickMediaForGroup(int blockIndex) async {
    if (blockIndex < 0 || blockIndex >= _blocks.length) return;
    final group = _blocks[blockIndex].mediaGroup;
    if (group == null) return;
    final remaining = _maxAttachments - _attachmentCount;
    if (remaining <= 0) return;
    final picked = await AppAssetPicker.pickDetailed(
      context,
      type: AppAssetPickerType.imageAndVideo,
      maxAssets: remaining,
    );
    if (!mounted || picked.assets.isEmpty) return;
    setState(() {
      group.items.addAll(picked.assets.map(_attachmentFromAppPickedAsset));
    });
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

  Widget _tableEditor(AppColors c, _RichTableDraft table) {
    final tableHeight = (table.rowCount * 54.0 + 18).clamp(102.0, 300.0);
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
                  child: TextField(
                    key: const ValueKey('rich-table-title'),
                    controller: table.title,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => setState(() {}),
                    style: AppTextStyle.callout(
                      c.textPrimary,
                      weight: AppTextWeight.semibold,
                    ),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: AppStringKeys.richTextComposerInsertTable.l10n(
                        context,
                      ),
                    ),
                  ),
                ),
                _textMiniButton(c, '+R', () => setState(table.addRow)),
                const SizedBox(width: 4),
                _textMiniButton(
                  c,
                  '+C',
                  table.columnCount >= _RichTableDraft.maxColumns
                      ? null
                      : () => setState(table.addColumn),
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
    final cellStyle = table.styles[row][column];
    final isHeader = cellStyle.isHeader;
    final stripedFill = table.striped && row.isOdd;
    final borderSide = table.bordered
        ? BorderSide(color: c.divider)
        : BorderSide.none;
    return Container(
      width: 132,
      height: 54,
      decoration: BoxDecoration(
        color: isHeader
            ? AppTheme.brand.withValues(alpha: 0.1)
            : stripedFill
            ? c.searchFill
            : c.background,
        border: Border(
          right: borderSide,
          bottom: borderSide,
          left: column == 0 ? borderSide : BorderSide.none,
          top: row == 0 ? borderSide : BorderSide.none,
        ),
      ),
      child: TextField(
        key: ValueKey('rich-table-cell-$row-$column'),
        controller: table.cells[row][column],
        textInputAction: TextInputAction.next,
        textAlign: switch (cellStyle.horizontal) {
          _RichCellHorizontalAlignment.left => TextAlign.left,
          _RichCellHorizontalAlignment.center => TextAlign.center,
          _RichCellHorizontalAlignment.right => TextAlign.right,
        },
        textAlignVertical: switch (cellStyle.vertical) {
          _RichCellVerticalAlignment.top => TextAlignVertical.top,
          _RichCellVerticalAlignment.middle => TextAlignVertical.center,
          _RichCellVerticalAlignment.bottom => TextAlignVertical.bottom,
        },
        contextMenuBuilder: (context, editableTextState) {
          return _RichTableCellContextMenu(
            anchor: editableTextState.contextMenuAnchors.primaryAnchor,
            systemItems: editableTextState.contextMenuButtonItems,
            isHeader: cellStyle.isHeader,
            horizontal: cellStyle.horizontal,
            vertical: cellStyle.vertical,
            isBorderless: !table.bordered,
            isStriped: table.striped,
            canAddColumn: table.columnCount < _RichTableDraft.maxColumns,
            canRemoveRow: table.rowCount > 1,
            canRemoveColumn: table.columnCount > 1,
            onTableAction: (action) => _applyTableMenuAction(
              action,
              editableTextState,
              table,
              cellStyle,
              row,
              column,
            ),
          );
        },
        style: AppTextStyle.callout(
          c.textPrimary,
          weight: isHeader ? AppTextWeight.semibold : AppTextWeight.regular,
        ),
        decoration: const InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
      ),
    );
  }

  void _applyTableMenuAction(
    _RichTableMenuAction action,
    EditableTextState editableTextState,
    _RichTableDraft table,
    _RichTableCellStyle cellStyle,
    int row,
    int column,
  ) {
    editableTextState.hideToolbar();
    switch (action) {
      case _RichTableMenuAction.addRowAbove:
        setState(() => table.insertRow(row));
      case _RichTableMenuAction.addRowBelow:
        setState(() => table.insertRow(row + 1));
      case _RichTableMenuAction.addColumnLeft:
        setState(() => table.insertColumn(column));
      case _RichTableMenuAction.addColumnRight:
        setState(() => table.insertColumn(column + 1));
      case _RichTableMenuAction.toggleHeader:
        setState(() => cellStyle.isHeader = !cellStyle.isHeader);
      case _RichTableMenuAction.alignLeft:
        setState(
          () => cellStyle.horizontal = _RichCellHorizontalAlignment.left,
        );
      case _RichTableMenuAction.alignCenter:
        setState(
          () => cellStyle.horizontal = _RichCellHorizontalAlignment.center,
        );
      case _RichTableMenuAction.alignRight:
        setState(
          () => cellStyle.horizontal = _RichCellHorizontalAlignment.right,
        );
      case _RichTableMenuAction.alignTop:
        setState(() => cellStyle.vertical = _RichCellVerticalAlignment.top);
      case _RichTableMenuAction.alignMiddle:
        setState(() => cellStyle.vertical = _RichCellVerticalAlignment.middle);
      case _RichTableMenuAction.alignBottom:
        setState(() => cellStyle.vertical = _RichCellVerticalAlignment.bottom);
      case _RichTableMenuAction.toggleBorderless:
        setState(() => table.bordered = !table.bordered);
      case _RichTableMenuAction.toggleStriped:
        setState(() => table.striped = !table.striped);
      case _RichTableMenuAction.removeRow:
        setState(() => table.removeRowAt(row));
      case _RichTableMenuAction.removeColumn:
        setState(() => table.removeColumnAt(column));
      case _RichTableMenuAction.removeTable:
        _removeTable(table);
    }
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

  Widget _textMiniButton(AppColors c, String label, VoidCallback? onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 32, minHeight: 30),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          color: c.searchFill,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: AppTextStyle.caption(
            onTap == null ? c.textTertiary : c.textPrimary,
          ).copyWith(fontWeight: FontWeight.w600),
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
          _actionChip(
            c,
            'P',
            () => unawaited(_insertBlockKind(_RichBlockKind.paragraph)),
          ),
          _actionChip(
            c,
            'H',
            () => unawaited(_insertBlockKind(_RichBlockKind.heading)),
          ),
          _actionChip(
            c,
            '•',
            () => unawaited(_insertBlockKind(_RichBlockKind.list)),
          ),
          _iconButton(
            c,
            icon: HeroAppIcons.quoteLeft,
            label: _RichBlockKind.blockQuotation.labelKey.l10n(context),
            onTap: () =>
                unawaited(_insertBlockKind(_RichBlockKind.blockQuotation)),
          ),
          _iconButton(
            c,
            icon: HeroAppIcons.tableCells,
            label: AppStringKeys.richTextComposerInsertTable.l10n(context),
            onTap: () => unawaited(_insertBlockKind(_RichBlockKind.table)),
          ),
          _actionChip(
            c,
            '∑',
            () => unawaited(
              _insertBlockKind(_RichBlockKind.mathematicalExpression),
            ),
          ),
          _iconButton(
            c,
            icon: HeroAppIcons.locationPin,
            label: _RichBlockKind.map.labelKey.l10n(context),
            onTap: () => unawaited(_insertBlockKind(_RichBlockKind.map)),
          ),
          _toolbarInsertButton(c),
        ],
      ),
    );
  }

  Widget _toolbarInsertButton(AppColors c) {
    return Builder(
      builder: (buttonContext) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          final box = buttonContext.findRenderObject() as RenderBox?;
          if (box == null) return;
          final anchor = box.localToGlobal(Offset(box.size.width / 2, 0));
          unawaited(_showRichBlockInsertMenuAt(anchor));
        },
        child: Container(
          width: 48,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.searchFill,
            borderRadius: BorderRadius.circular(7),
          ),
          child: AppIcon(HeroAppIcons.ellipsis, size: 23, color: c.textPrimary),
        ),
      ),
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

  int get _attachmentCount => _blocks.fold<int>(0, (count, block) {
    if (block.attachment != null) return count + 1;
    return count + (block.mediaGroup?.items.length ?? 0);
  });

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
            _miniIconButton(
              c,
              icon: HeroAppIcons.trash,
              label: AppStringKeys.richTextComposerRemoveBlock.l10n(context),
              destructive: true,
              onTap: () => _removeStructuredBlock(blockIndex),
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
    final edited = await resolveAttachmentDimensions(
      item.copyWith(
        path: result.path,
        clearPreviewBytes: true,
        clearDimensions: true,
      ),
    );
    if (!mounted || index >= _blocks.length) return;
    setState(() {
      _blocks[index] = _RichContentBlock.attachment(
        edited,
        kind: _blocks[index].kind,
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
    return _attachmentFromPickedMedia(asset.file).copyWith(
      previewBytes: asset.thumbnailBytes,
      width: asset.width,
      height: asset.height,
    );
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

extension on _RichBlockKind {
  String get labelKey => switch (this) {
    _RichBlockKind.paragraph => AppStringKeys.richTextBlockParagraph,
    _RichBlockKind.heading => AppStringKeys.richTextBlockHeading,
    _RichBlockKind.preformatted => AppStringKeys.richTextBlockPreformatted,
    _RichBlockKind.footer => AppStringKeys.richTextBlockFooter,
    _RichBlockKind.divider => AppStringKeys.richTextBlockDivider,
    _RichBlockKind.mathematicalExpression =>
      AppStringKeys.richTextBlockMathematicalExpression,
    _RichBlockKind.anchor => AppStringKeys.richTextBlockAnchor,
    _RichBlockKind.list => AppStringKeys.richTextBlockList,
    _RichBlockKind.blockQuotation => AppStringKeys.richTextBlockBlockQuotation,
    _RichBlockKind.pullQuotation => AppStringKeys.richTextBlockPullQuotation,
    _RichBlockKind.collage => AppStringKeys.richTextBlockCollage,
    _RichBlockKind.slideshow => AppStringKeys.richTextBlockSlideshow,
    _RichBlockKind.table => AppStringKeys.richTextBlockTable,
    _RichBlockKind.details => AppStringKeys.richTextBlockDetails,
    _RichBlockKind.map => AppStringKeys.richTextBlockMap,
    _RichBlockKind.animation => AppStringKeys.richTextBlockAnimation,
    _RichBlockKind.audio => AppStringKeys.richTextBlockAudio,
    _RichBlockKind.photo => AppStringKeys.richTextBlockPhoto,
    _RichBlockKind.video => AppStringKeys.richTextBlockVideo,
    _RichBlockKind.voiceNote => AppStringKeys.richTextBlockVoiceNote,
    _RichBlockKind.thinking => AppStringKeys.richTextBlockThinking,
    _RichBlockKind.document => AppStringKeys.topicPostContentFile,
  };

  AppIconData get icon => switch (this) {
    _RichBlockKind.paragraph => HeroAppIcons.font,
    _RichBlockKind.heading => HeroAppIcons.hashtag,
    _RichBlockKind.preformatted => HeroAppIcons.code,
    _RichBlockKind.footer => HeroAppIcons.bars,
    _RichBlockKind.divider => HeroAppIcons.minus,
    _RichBlockKind.mathematicalExpression => HeroAppIcons.code,
    _RichBlockKind.anchor => HeroAppIcons.link,
    _RichBlockKind.list => HeroAppIcons.listCheck,
    _RichBlockKind.blockQuotation => HeroAppIcons.quoteLeft,
    _RichBlockKind.pullQuotation => HeroAppIcons.quoteLeft,
    _RichBlockKind.collage => HeroAppIcons.images,
    _RichBlockKind.slideshow => HeroAppIcons.tableColumns,
    _RichBlockKind.table => HeroAppIcons.tableCells,
    _RichBlockKind.details => HeroAppIcons.bars,
    _RichBlockKind.map => HeroAppIcons.locationPin,
    _RichBlockKind.animation => HeroAppIcons.gif,
    _RichBlockKind.audio => HeroAppIcons.music,
    _RichBlockKind.photo => HeroAppIcons.image,
    _RichBlockKind.video => HeroAppIcons.play,
    _RichBlockKind.voiceNote => HeroAppIcons.microphone,
    _RichBlockKind.thinking => HeroAppIcons.comments,
    _RichBlockKind.document => HeroAppIcons.file,
  };
}

class _RichTableCellContextMenu extends StatefulWidget {
  const _RichTableCellContextMenu({
    required this.anchor,
    required this.systemItems,
    required this.isHeader,
    required this.horizontal,
    required this.vertical,
    required this.isBorderless,
    required this.isStriped,
    required this.canAddColumn,
    required this.canRemoveRow,
    required this.canRemoveColumn,
    required this.onTableAction,
  });

  final Offset anchor;
  final List<ContextMenuButtonItem> systemItems;
  final bool isHeader;
  final _RichCellHorizontalAlignment horizontal;
  final _RichCellVerticalAlignment vertical;
  final bool isBorderless;
  final bool isStriped;
  final bool canAddColumn;
  final bool canRemoveRow;
  final bool canRemoveColumn;
  final ValueChanged<_RichTableMenuAction> onTableAction;

  @override
  State<_RichTableCellContextMenu> createState() =>
      _RichTableCellContextMenuState();
}

class _RichTableCellContextMenuState extends State<_RichTableCellContextMenu> {
  bool _showTableActions = false;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screen = media.size;
    final leftWidth = math.min(300.0, screen.width - 24);
    final twoPaneRightWidth = screen.width - 24 - leftWidth - 8;
    final wide = twoPaneRightWidth >= 280;
    final rightWidth = wide
        ? math.min(390.0, twoPaneRightWidth)
        : math.min(390.0, screen.width - 24);
    final totalWidth = _showTableActions && wide
        ? leftWidth + 8 + rightWidth
        : (_showTableActions ? rightWidth : leftWidth);
    final maxHeight = math.min(
      590.0,
      screen.height - media.padding.top - media.padding.bottom - 20,
    );
    final left = (widget.anchor.dx - totalWidth / 2)
        .clamp(12.0, math.max(12.0, screen.width - totalWidth - 12))
        .toDouble();
    final safeTop = media.padding.top + 8;
    final top = (widget.anchor.dy - 42)
        .clamp(safeTop, math.max(safeTop, screen.height - maxHeight - 12))
        .toDouble();

    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            width: totalWidth,
            height: maxHeight,
            child: TextFieldTapRegion(
              child: _showTableActions && !wide
                  ? _tableActionsPanel(showBack: true)
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: leftWidth, child: _systemPanel()),
                        if (_showTableActions) ...[
                          const SizedBox(width: 8),
                          SizedBox(
                            width: rightWidth,
                            child: _tableActionsPanel(),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _systemPanel() {
    return _RichContextMenuSurface(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _RichContextMenuRow(
            label: AppStringKeys.richTextTableChange.l10n(context),
            leading: AppIcon(
              HeroAppIcons.tableCells,
              size: 20,
              color: context.colors.textPrimary,
            ),
            trailing: AppIcon(
              HeroAppIcons.chevronRight,
              size: 18,
              color: context.colors.textSecondary,
            ),
            selected: _showTableActions,
            onTap: () => setState(() => _showTableActions = true),
          ),
          const _RichContextMenuDivider(),
          for (final item in widget.systemItems)
            if (AdaptiveTextSelectionToolbar.getButtonLabel(
              context,
              item,
            ).isNotEmpty)
              _RichContextMenuRow(
                label: AdaptiveTextSelectionToolbar.getButtonLabel(
                  context,
                  item,
                ),
                onTap: item.onPressed,
              ),
        ],
      ),
    );
  }

  Widget _tableActionsPanel({bool showBack = false}) {
    return _RichContextMenuSurface(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (showBack) ...[
            _RichContextMenuRow(
              label: AppStringKeys.richTextTableChange.l10n(context),
              leading: AppIcon(
                HeroAppIcons.chevronLeft,
                size: 18,
                color: context.colors.textPrimary,
              ),
              onTap: () => setState(() => _showTableActions = false),
            ),
            const _RichContextMenuDivider(),
          ],
          _tableActionRow(
            _RichTableMenuAction.addRowAbove,
            AppStringKeys.richTextTableAddRowAbove,
            const _RichTableInsertIcon(HeroAppIcons.arrowUp),
          ),
          _tableActionRow(
            _RichTableMenuAction.addRowBelow,
            AppStringKeys.richTextTableAddRowBelow,
            const _RichTableInsertIcon(HeroAppIcons.arrowDown),
          ),
          _tableActionRow(
            _RichTableMenuAction.addColumnLeft,
            AppStringKeys.richTextTableAddColumnLeft,
            const _RichTableInsertIcon(HeroAppIcons.arrowLeft),
            enabled: widget.canAddColumn,
          ),
          _tableActionRow(
            _RichTableMenuAction.addColumnRight,
            AppStringKeys.richTextTableAddColumnRight,
            const _RichTableInsertIcon(HeroAppIcons.arrowRight),
            enabled: widget.canAddColumn,
          ),
          const _RichContextMenuDivider(),
          _tableActionRow(
            _RichTableMenuAction.toggleHeader,
            AppStringKeys.richTextTableHeader,
            AppIcon(
              HeroAppIcons.tableCells,
              size: 21,
              color: context.colors.textPrimary,
            ),
            checked: widget.isHeader,
          ),
          const _RichContextMenuDivider(),
          _tableActionRow(
            _RichTableMenuAction.alignLeft,
            AppStringKeys.richTextTableAlignLeft,
            _menuIcon(HeroAppIcons.alignLeft),
            checked: widget.horizontal == _RichCellHorizontalAlignment.left,
          ),
          _tableActionRow(
            _RichTableMenuAction.alignCenter,
            AppStringKeys.richTextTableAlignCenter,
            _menuIcon(HeroAppIcons.alignCenter),
            checked: widget.horizontal == _RichCellHorizontalAlignment.center,
          ),
          _tableActionRow(
            _RichTableMenuAction.alignRight,
            AppStringKeys.richTextTableAlignRight,
            _menuIcon(HeroAppIcons.alignRight),
            checked: widget.horizontal == _RichCellHorizontalAlignment.right,
          ),
          const _RichContextMenuDivider(),
          _tableActionRow(
            _RichTableMenuAction.alignTop,
            AppStringKeys.richTextTableAlignTop,
            _menuIcon(HeroAppIcons.alignTop),
            checked: widget.vertical == _RichCellVerticalAlignment.top,
          ),
          _tableActionRow(
            _RichTableMenuAction.alignMiddle,
            AppStringKeys.richTextTableAlignMiddle,
            _menuIcon(HeroAppIcons.arrowsUpDown),
            checked: widget.vertical == _RichCellVerticalAlignment.middle,
          ),
          _tableActionRow(
            _RichTableMenuAction.alignBottom,
            AppStringKeys.richTextTableAlignBottom,
            _menuIcon(HeroAppIcons.alignBottom),
            checked: widget.vertical == _RichCellVerticalAlignment.bottom,
          ),
          const _RichContextMenuDivider(),
          _tableActionRow(
            _RichTableMenuAction.toggleBorderless,
            AppStringKeys.richTextTableBorderless,
            _menuIcon(HeroAppIcons.tableCells),
            checked: widget.isBorderless,
          ),
          _tableActionRow(
            _RichTableMenuAction.toggleStriped,
            AppStringKeys.richTextTableStriped,
            _menuIcon(HeroAppIcons.bars),
            checked: widget.isStriped,
          ),
          const _RichContextMenuDivider(),
          _tableActionRow(
            _RichTableMenuAction.removeRow,
            AppStringKeys.richTextComposerRemoveRow,
            _menuIcon(HeroAppIcons.trash),
            enabled: widget.canRemoveRow,
            destructive: true,
          ),
          _tableActionRow(
            _RichTableMenuAction.removeColumn,
            AppStringKeys.richTextComposerRemoveColumn,
            _menuIcon(HeroAppIcons.trash),
            enabled: widget.canRemoveColumn,
            destructive: true,
          ),
          _tableActionRow(
            _RichTableMenuAction.removeTable,
            AppStringKeys.richTextComposerRemoveTable,
            _menuIcon(HeroAppIcons.trash),
            destructive: true,
          ),
        ],
      ),
    );
  }

  Widget _menuIcon(AppIconData icon) =>
      AppIcon(icon, size: 21, color: context.colors.textPrimary);

  Widget _tableActionRow(
    _RichTableMenuAction action,
    String labelKey,
    Widget leading, {
    bool enabled = true,
    bool checked = false,
    bool destructive = false,
  }) {
    return _RichContextMenuRow(
      label: labelKey.l10n(context),
      leading: leading,
      trailing: checked
          ? AppIcon(HeroAppIcons.check, size: 20, color: AppTheme.brand)
          : null,
      enabled: enabled,
      destructive: destructive,
      onTap: enabled ? () => widget.onTableAction(action) : null,
    );
  }
}

class _RichContextMenuSurface extends StatelessWidget {
  const _RichContextMenuSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.divider, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _RichContextMenuRow extends StatelessWidget {
  const _RichContextMenuRow({
    required this.label,
    this.leading,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.selected = false,
    this.destructive = false,
  });

  final String label;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;
  final bool selected;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final active = enabled && onTap != null;
    final color = !active
        ? c.textTertiary
        : destructive
        ? const Color(0xFFFF5A52)
        : c.textPrimary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: active ? onTap : null,
      child: Container(
        height: 48,
        color: selected ? c.searchFill : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            if (leading case final leading?) ...[
              SizedBox(width: 26, child: Center(child: leading)),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 16,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            if (trailing case final trailing?) ...[
              const SizedBox(width: 10),
              trailing,
            ],
          ],
        ),
      ),
    );
  }
}

class _RichContextMenuDivider extends StatelessWidget {
  const _RichContextMenuDivider();

  @override
  Widget build(BuildContext context) => Container(
    height: 0.5,
    margin: const EdgeInsets.symmetric(vertical: 4),
    color: context.colors.divider,
  );
}

class _RichTableInsertIcon extends StatelessWidget {
  const _RichTableInsertIcon(this.direction);

  final AppIconData direction;

  @override
  Widget build(BuildContext context) {
    final color = context.colors.textPrimary;
    return SizedBox(
      width: 26,
      height: 26,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: AppIcon(direction, size: 21, color: color),
          ),
          Positioned(
            right: 0,
            bottom: -1,
            child: Text(
              '+',
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _RichInlineFormatAction {
  quote('textEntityTypeBlockQuote'),
  spoiler('textEntityTypeSpoiler'),
  bold('textEntityTypeBold'),
  italic('textEntityTypeItalic'),
  monospace('textEntityTypeCode'),
  link(''),
  strikethrough('textEntityTypeStrikethrough'),
  underline('textEntityTypeUnderline'),
  codeBlock('textEntityTypePre');

  const _RichInlineFormatAction(this.entityType);
  final String entityType;

  String get labelKey => switch (this) {
    quote => AppStringKeys.messageActionQuote,
    spoiler => AppStringKeys.richTextComposerFormatSpoiler,
    bold => AppStringKeys.richTextComposerFormatBold,
    italic => AppStringKeys.richTextComposerFormatItalic,
    monospace => AppStringKeys.composerFormatMonospace,
    link => AppStringKeys.composerFormatLink,
    strikethrough => AppStringKeys.richTextComposerFormatStrikethrough,
    underline => AppStringKeys.richTextComposerFormatUnderline,
    codeBlock => AppStringKeys.composerFormatCodeBlock,
  };
}

enum _RichBlockAction { moveUp, moveDown, delete }

class _RichBlockActionMenu extends StatelessWidget {
  const _RichBlockActionMenu({
    required this.anchor,
    required this.canMoveUp,
    required this.canMoveDown,
  });

  final Offset anchor;
  final bool canMoveUp;
  final bool canMoveDown;

  @override
  Widget build(BuildContext context) {
    return _RichAnchoredMenu(
      anchor: anchor,
      width: 184,
      maxHeight: 150,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RichMenuRow(
            label: AppStringKeys.richTextComposerMoveUp.l10n(context),
            onTap: canMoveUp
                ? () => Navigator.of(context).pop(_RichBlockAction.moveUp)
                : null,
          ),
          _RichMenuRow(
            label: AppStringKeys.richTextComposerMoveDown.l10n(context),
            onTap: canMoveDown
                ? () => Navigator.of(context).pop(_RichBlockAction.moveDown)
                : null,
          ),
          _RichMenuRow(
            label: AppStringKeys.richTextComposerRemoveBlock.l10n(context),
            destructive: true,
            onTap: () => Navigator.of(context).pop(_RichBlockAction.delete),
          ),
        ],
      ),
    );
  }
}

class _RichInlineFormatMenu extends StatelessWidget {
  const _RichInlineFormatMenu({required this.anchor});
  final Offset anchor;

  @override
  Widget build(BuildContext context) {
    return _RichAnchoredMenu(
      anchor: anchor,
      width: 232,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final action in _RichInlineFormatAction.values)
            _RichMenuRow(
              label: action.labelKey.l10n(context),
              onTap: () => Navigator.of(context).pop(action),
            ),
        ],
      ),
    );
  }
}

class _RichBlockInsertMenu extends StatelessWidget {
  const _RichBlockInsertMenu({required this.anchor});
  final Offset anchor;

  @override
  Widget build(BuildContext context) {
    final kinds = _RichBlockKind.values
        .where(
          (kind) =>
              kind != _RichBlockKind.document &&
              kind != _RichBlockKind.thinking,
        )
        .toList(growable: false);
    final menuWidth = math.min(360.0, MediaQuery.sizeOf(context).width - 24);
    return _RichAnchoredMenu(
      anchor: anchor,
      width: menuWidth,
      maxHeight: 520,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Text(
              AppStringKeys.richTextComposerInsert.l10n(context),
              style: AppTextStyle.callout(
                context.colors.textSecondary,
                weight: AppTextWeight.semibold,
              ),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Wrap(
                children: [
                  for (final kind in kinds)
                    SizedBox(
                      width: (menuWidth - 12) / 2,
                      child: _RichMenuRow(
                        icon: kind.icon,
                        label: kind.labelKey.l10n(context),
                        compact: true,
                        onTap: () => Navigator.of(context).pop(kind),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RichAnchoredMenu extends StatelessWidget {
  const _RichAnchoredMenu({
    required this.anchor,
    required this.width,
    required this.child,
    this.maxHeight = 440,
  });

  final Offset anchor;
  final double width;
  final double maxHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final media = MediaQuery.of(context);
    final screen = media.size;
    final left = (anchor.dx - width / 2)
        .clamp(12.0, math.max(12.0, screen.width - width - 12))
        .toDouble();
    final top = (anchor.dy - maxHeight - 10)
        .clamp(
          media.padding.top + 8,
          math.max(media.padding.top + 8, screen.height - maxHeight - 12),
        )
        .toDouble();
    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: width,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.divider, width: 0.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}

class _RichMenuRow extends StatelessWidget {
  const _RichMenuRow({
    required this.label,
    this.onTap,
    this.compact = false,
    this.destructive = false,
    this.icon,
  });
  final String label;
  final VoidCallback? onTap;
  final bool compact;
  final bool destructive;
  final AppIconData? icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: compact ? 48 : 44,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 18),
            child: Row(
              children: [
                if (icon case final icon?) ...[
                  AppIcon(
                    icon,
                    size: 18,
                    color: onTap == null
                        ? context.colors.textTertiary
                        : AppTheme.brand,
                  ),
                  const SizedBox(width: 9),
                ],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 14 : 16,
                      color: onTap == null
                          ? context.colors.textTertiary
                          : destructive
                          ? const Color(0xFFFF5A52)
                          : context.colors.textPrimary,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RichValueDialog extends StatefulWidget {
  const _RichValueDialog({required this.title, required this.hint});
  final String title;
  final String hint;

  @override
  State<_RichValueDialog> createState() => _RichValueDialogState();
}

class _RichValueDialogState extends State<_RichValueDialog> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Container(
        width: math.min(360, MediaQuery.sizeOf(context).width - 40),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title.l10n(context),
              style: AppTextStyle.title(c.textPrimary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: _submit,
              style: AppTextStyle.body(c.textPrimary),
              decoration: InputDecoration(
                filled: true,
                fillColor: c.searchFill,
                border: InputBorder.none,
                hintText: widget.hint.l10n(context),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _submit(controller.text),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    AppStringKeys.composerFormatApply.l10n(context),
                    style: AppTextStyle.callout(
                      AppTheme.brand,
                      weight: AppTextWeight.semibold,
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

  void _submit(String value) {
    if (value.trim().isEmpty) return;
    Navigator.of(context).pop(value.trim());
  }
}
