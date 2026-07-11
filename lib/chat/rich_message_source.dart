import 'outgoing_attachment.dart';

class RichMessageSendSegment {
  const RichMessageSendSegment.html(this.html, {this.richFiles = const []})
    : attachments = const [];
  const RichMessageSendSegment.attachments(this.attachments)
    : html = '',
      richFiles = const [];

  final String html;
  final List<RichMessageSendFile> richFiles;
  final List<OutgoingAttachment> attachments;

  bool get isHtml => html.trim().isNotEmpty;
}

class RichMessageSendFile {
  const RichMessageSendFile({required this.id, required this.attachment});

  final String id;
  final OutgoingAttachment attachment;
}

String formattedTextToRichHtml(
  String text,
  List<Map<String, dynamic>> entities, {
  int headingLevel = 0,
}) {
  if (text.trim().isEmpty) return '';
  if (headingLevel > 0) {
    final level = headingLevel.clamp(1, 6);
    return '<h$level>${_inlineHtml(text.trim(), entities, 0)}</h$level>';
  }

  final lines = text.split('\n');
  final buffer = StringBuffer();
  String? openList;
  var offset = 0;

  void closeList() {
    if (openList == null) return;
    buffer.write('</$openList>');
    openList = null;
  }

  for (final line in lines) {
    final task = RegExp(r'^\s*-\s*\[([ xX])\]\s*(.*)$').firstMatch(line);
    final unordered = RegExp(r'^\s*[-*+]\s+(.*)$').firstMatch(line);
    final ordered = RegExp(r'^\s*\d+[.)]\s+(.*)$').firstMatch(line);
    String? listType;
    String content = line;
    String prefix = '';
    var contentOffset = offset;
    if (task != null) {
      listType = 'ul';
      content = task.group(2) ?? '';
      contentOffset += line.indexOf(content);
      prefix =
          '<input type="checkbox"${task.group(1)!.toLowerCase() == 'x' ? ' checked' : ''}>';
    } else if (unordered != null) {
      listType = 'ul';
      content = unordered.group(1) ?? '';
      contentOffset += line.indexOf(content);
    } else if (ordered != null) {
      listType = 'ol';
      content = ordered.group(1) ?? '';
      contentOffset += line.indexOf(content);
    }

    if (listType != null) {
      if (openList != listType) {
        closeList();
        openList = listType;
        buffer.write('<$listType>');
      }
      buffer
        ..write('<li>')
        ..write(prefix)
        ..write(_inlineHtml(content, entities, contentOffset))
        ..write('</li>');
    } else {
      closeList();
      if (line.trim().isNotEmpty) {
        buffer
          ..write('<p>')
          ..write(_inlineHtml(line, entities, offset))
          ..write('</p>');
      }
    }
    offset += line.length + 1;
  }
  closeList();
  return buffer.toString();
}

String _inlineHtml(
  String text,
  List<Map<String, dynamic>> entities,
  int sourceOffset,
) {
  if (text.isEmpty) return '';
  final endOffset = sourceOffset + text.length;
  final valid = entities.where((entity) {
    final offset = entity['offset'];
    final length = entity['length'];
    return offset is int &&
        length is int &&
        length > 0 &&
        offset < endOffset &&
        offset + length > sourceOffset;
  }).toList();
  final cuts = <int>{sourceOffset, endOffset};
  for (final entity in valid) {
    final start = (entity['offset'] as int).clamp(sourceOffset, endOffset);
    final end = ((entity['offset'] as int) + (entity['length'] as int)).clamp(
      sourceOffset,
      endOffset,
    );
    cuts
      ..add(start)
      ..add(end);
  }
  final ordered = cuts.toList()..sort();
  final buffer = StringBuffer();
  for (var index = 0; index < ordered.length - 1; index++) {
    final start = ordered[index];
    final end = ordered[index + 1];
    if (start >= end) continue;
    final active =
        valid.where((entity) {
            final entityStart = entity['offset'] as int;
            final entityEnd = entityStart + (entity['length'] as int);
            return entityStart < end && entityEnd > start;
          }).toList()
          ..sort((a, b) => _entityPriority(a).compareTo(_entityPriority(b)));
    var segment = _escapeHtml(
      text.substring(start - sourceOffset, end - sourceOffset),
    );
    for (final entity in active.reversed) {
      segment = _wrapEntity(segment, entity);
    }
    buffer.write(segment);
  }
  return buffer.toString();
}

int _entityPriority(Map<String, dynamic> entity) {
  final type = entity['type'];
  final name = type is Map ? type['@type'] as String? : null;
  return switch (name) {
    'textEntityTypeTextUrl' || 'textEntityTypeMentionName' => 0,
    'textEntityTypeBold' => 1,
    'textEntityTypeItalic' => 2,
    'textEntityTypeUnderline' => 3,
    'textEntityTypeStrikethrough' => 4,
    'textEntityTypeSpoiler' => 5,
    'textEntityTypeCode' || 'textEntityTypePre' || 'textEntityTypePreCode' => 6,
    _ => 7,
  };
}

String _wrapEntity(String value, Map<String, dynamic> entity) {
  final rawType = entity['type'];
  if (rawType is! Map) return value;
  final type = rawType['@type'] as String?;
  return switch (type) {
    'textEntityTypeBold' => '<b>$value</b>',
    'textEntityTypeItalic' => '<i>$value</i>',
    'textEntityTypeUnderline' => '<u>$value</u>',
    'textEntityTypeStrikethrough' => '<s>$value</s>',
    'textEntityTypeSpoiler' => '<tg-spoiler>$value</tg-spoiler>',
    'textEntityTypeCode' => '<code>$value</code>',
    'textEntityTypePre' || 'textEntityTypePreCode' => '<pre>$value</pre>',
    'textEntityTypeMarked' => '<mark>$value</mark>',
    'textEntityTypeSubscript' => '<sub>$value</sub>',
    'textEntityTypeSuperscript' => '<sup>$value</sup>',
    'textEntityTypeBlockQuote' ||
    'textEntityTypeExpandableBlockQuote' => '<blockquote>$value</blockquote>',
    'textEntityTypeMathematicalExpression' => '<tg-math>$value</tg-math>',
    'textEntityTypeTextUrl' =>
      '<a href="${_escapeAttribute('${rawType['url'] ?? ''}')}">$value</a>',
    'textEntityTypeMentionName' =>
      '<a href="tg://user?id=${_escapeAttribute('${rawType['user_id'] ?? ''}')}">$value</a>',
    'textEntityTypeCustomEmoji' =>
      '<tg-emoji emoji-id="${_escapeAttribute('${rawType['custom_emoji_id'] ?? ''}')}">$value</tg-emoji>',
    _ => value,
  };
}

String escapeRichHtml(String value) => _escapeHtml(value);

String _escapeHtml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String _escapeAttribute(String value) => _escapeHtml(value);
