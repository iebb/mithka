part of 'rich_text_composer_view.dart';

class _RichTableDraft {
  _RichTableDraft({int rows = 3, int columns = 3, String title = ''})
    : title = TextEditingController(text: title),
      cells = List.generate(
        rows,
        (row) => List.generate(
          columns,
          (column) => _cellController(row == 0 ? 'Column ${column + 1}' : ''),
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
  final List<List<EmojiTextEditingController>> cells;
  final List<List<_RichTableCellStyle>> styles;
  bool bordered = true;
  bool striped = true;
  int? activeRow;
  int? activeColumn;

  int get rowCount => cells.length;
  int get columnCount => cells.isEmpty ? 0 : cells.first.length;
  _RichTableCellStyle? get activeCellStyle {
    final row = activeRow;
    final column = activeColumn;
    if (row == null ||
        column == null ||
        row < 0 ||
        row >= rowCount ||
        column < 0 ||
        column >= columnCount) {
      return null;
    }
    return styles[row][column];
  }

  void activateCell(int row, int column) {
    if (row < 0 || row >= rowCount || column < 0 || column >= columnCount) {
      return;
    }
    activeRow = row;
    activeColumn = column;
  }

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
    final currentActiveRow = activeRow;
    if (currentActiveRow != null && safeIndex <= currentActiveRow) {
      activeRow = currentActiveRow + 1;
    }
    cells.insert(
      safeIndex,
      List.generate(columnCount, (_) => _cellController()),
    );
    styles.insert(
      safeIndex,
      List.generate(columnCount, (_) => _RichTableCellStyle()),
    );
  }

  void removeRowAt(int index) {
    if (rowCount <= 1 || index < 0 || index >= rowCount) return;
    if (activeRow == index) {
      activeRow = null;
      activeColumn = null;
    } else {
      final currentActiveRow = activeRow;
      if (currentActiveRow != null && index < currentActiveRow) {
        activeRow = currentActiveRow - 1;
      }
    }
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
    final currentActiveColumn = activeColumn;
    if (currentActiveColumn != null && safeIndex <= currentActiveColumn) {
      activeColumn = currentActiveColumn + 1;
    }
    for (var row = 0; row < cells.length; row++) {
      cells[row].insert(
        safeIndex,
        _cellController(row == 0 ? 'Column ${oldColumnCount + 1}' : ''),
      );
      styles[row].insert(safeIndex, _RichTableCellStyle(isHeader: row == 0));
    }
  }

  void removeColumnAt(int index) {
    if (columnCount <= 1 || index < 0 || index >= columnCount) return;
    if (activeColumn == index) {
      activeRow = null;
      activeColumn = null;
    } else {
      final currentActiveColumn = activeColumn;
      if (currentActiveColumn != null && index < currentActiveColumn) {
        activeColumn = currentActiveColumn - 1;
      }
    }
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
        final formatted = cell.toFormatted();
        buffer
          ..write(
            '<$tag align="${style.horizontal.name}" '
            'valign="${style.vertical.name}">',
          )
          ..write(formattedTextToRichInlineHtml(formatted.$1, formatted.$2))
          ..write('</$tag>');
      }
      buffer.write('</tr>');
    }
    buffer.write('</table>');
    return buffer.toString();
  }

  Map<String, dynamic> toInputPageBlock() {
    final tableTitle = title.text.trim();
    return {
      '@type': 'inputPageBlockTable',
      'caption': formattedTextToRichText(tableTitle, const []),
      'cells': [
        for (var rowIndex = 0; rowIndex < cells.length; rowIndex++)
          [
            for (
              var columnIndex = 0;
              columnIndex < cells[rowIndex].length;
              columnIndex++
            )
              _inputCell(rowIndex, columnIndex),
          ],
      ],
      'is_bordered': bordered,
      'is_striped': striped,
    };
  }

  Map<String, dynamic> _inputCell(int row, int column) {
    final formatted = cells[row][column].toFormatted();
    final style = styles[row][column];
    return {
      '@type': 'pageBlockTableCell',
      'text': formattedTextToRichText(formatted.$1, formatted.$2),
      'is_header': style.isHeader,
      'colspan': 1,
      'rowspan': 1,
      'align': {
        '@type': switch (style.horizontal) {
          _RichCellHorizontalAlignment.left =>
            'pageBlockHorizontalAlignmentLeft',
          _RichCellHorizontalAlignment.center =>
            'pageBlockHorizontalAlignmentCenter',
          _RichCellHorizontalAlignment.right =>
            'pageBlockHorizontalAlignmentRight',
        },
      },
      'valign': {
        '@type': switch (style.vertical) {
          _RichCellVerticalAlignment.top => 'pageBlockVerticalAlignmentTop',
          _RichCellVerticalAlignment.middle =>
            'pageBlockVerticalAlignmentMiddle',
          _RichCellVerticalAlignment.bottom =>
            'pageBlockVerticalAlignmentBottom',
        },
      },
    };
  }

  static String _escapeCell(String value) {
    return value
        .replaceAll('\n', ' ')
        .replaceAll('\r', ' ')
        .replaceAll('|', r'\|')
        .trim();
  }

  static EmojiTextEditingController _cellController([String text = '']) =>
      EmojiTextEditingController()..text = text;

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
  buttonRow,
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

enum _RichButtonAlignment { left, center, right }

enum _RichButtonStyle { standard, primary, success, danger }

class _RichButtonDraft {
  _RichButtonDraft({String label = '', String url = ''})
    : label = TextEditingController(text: label),
      url = TextEditingController(text: url);

  final TextEditingController label;
  final TextEditingController url;
  _RichButtonStyle style = _RichButtonStyle.primary;

  void dispose() {
    label.dispose();
    url.dispose();
  }
}

class _RichButtonRowDraft {
  _RichButtonRowDraft({required String defaultLabel})
    : buttons = [_RichButtonDraft(label: defaultLabel)];

  final List<_RichButtonDraft> buttons;
  _RichButtonAlignment alignment = _RichButtonAlignment.left;

  void dispose() {
    for (final button in buttons) {
      button.dispose();
    }
  }
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
    this.buttonRow,
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

  factory _RichContentBlock.buttonRow(_RichButtonRowDraft row) =>
      _RichContentBlock._(kind: _RichBlockKind.buttonRow, buttonRow: row);

  static int _nextId = 1;

  static _RichBlockKind _kindForAttachment(OutgoingAttachment attachment) {
    return switch (attachment.kind) {
      OutgoingAttachmentKind.photo => _RichBlockKind.photo,
      OutgoingAttachmentKind.video => _RichBlockKind.video,
      OutgoingAttachmentKind.animation => _RichBlockKind.animation,
      OutgoingAttachmentKind.audio => _RichBlockKind.audio,
      OutgoingAttachmentKind.voiceNote => _RichBlockKind.voiceNote,
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
  final _RichButtonRowDraft? buttonRow;
}
