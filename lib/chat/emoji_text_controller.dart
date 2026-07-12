//
//  emoji_text_controller.dart
//
//  A TextEditingController that supports inline Telegram custom (premium) emoji
//  inside the composer. Each inserted custom emoji is stored as a private-use
//  placeholder code unit (U+E000+); buildTextSpan renders those as inline
//  animated emoji, and toFormatted() converts the field to TDLib formattedText
//  (replacing each placeholder with its fallback emoji + a
//  textEntityTypeCustomEmoji entity at the correct UTF-16 offset).
//

import 'package:flutter/material.dart';

import 'custom_emoji.dart';

typedef _Emoji = ({int id, String fallback});

class _ComposerTextEntity {
  _ComposerTextEntity({
    required this.offset,
    required this.length,
    required Map<String, dynamic> type,
  }) : type = Map<String, dynamic>.of(type);

  int offset;
  int length;
  final Map<String, dynamic> type;

  String get typeName => type['@type'] as String? ?? '';

  int get end => offset + length;

  _ComposerTextEntity copyWith({int? offset, int? length}) {
    return _ComposerTextEntity(
      offset: offset ?? this.offset,
      length: length ?? this.length,
      type: type,
    );
  }

  Map<String, dynamic> toTdJson(int offset, int length) => {
    '@type': 'textEntity',
    'offset': offset,
    'length': length,
    'type': Map<String, dynamic>.of(type),
  };
}

class EmojiTextEditingController extends TextEditingController {
  final Map<int, _Emoji> _byCode = {}; // PUA code unit -> emoji
  final Map<int, int> _codeForId = {}; // custom_emoji_id -> PUA code unit
  final List<_ComposerTextEntity> _entities = [];
  int _next = 0xE000; // BMP Private Use Area (single UTF-16 unit each)
  String _lastText = '';

  @override
  set value(TextEditingValue newValue) {
    _shiftEntitiesForEdit(_lastText, newValue.text);
    _lastText = newValue.text;
    super.value = newValue;
  }

  /// Inserts a custom emoji at the current selection.
  void insertCustomEmoji(int id, String fallback) {
    var code = _codeForId[id];
    if (code == null) {
      code = _next++;
      _codeForId[id] = code;
      _byCode[code] = (id: id, fallback: fallback.isEmpty ? '🙂' : fallback);
    }
    final ch = String.fromCharCode(code);
    final sel = selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final newText = text.replaceRange(start, end, ch);
    value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + ch.length),
    );
  }

  /// Inserts plain text (e.g. a standard unicode emoji) at the selection.
  void insertText(String s) {
    insertFormattedText(s);
  }

  /// Replaces [start]..[end] with an ID-backed Telegram user mention.
  void insertTextMention({
    required int start,
    required int end,
    required String label,
    required int userId,
  }) {
    if (start < 0 || end < start || end > text.length || userId <= 0) return;
    final mention = '@${label.trim()}';
    if (mention.length <= 1) return;
    final replaceEnd = end < text.length && _isWhitespace(text[end])
        ? end + 1
        : end;
    final newText = text.replaceRange(start, replaceEnd, '$mention ');
    _replaceEntityRange(start, replaceEnd, mention.length + 1);
    _entities.add(
      _ComposerTextEntity(
        offset: start,
        length: mention.length,
        type: {'@type': 'textEntityTypeMentionName', 'user_id': userId},
      ),
    );
    _lastText = newText;
    super.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + mention.length + 1),
    );
    notifyListeners();
  }

  bool _isWhitespace(String value) => value.trim().isEmpty;

  /// Inserts text at the selection and optionally applies one entity over it.
  void insertFormattedText(String s, {String? type}) {
    final sel = selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final newText = text.replaceRange(start, end, s);
    _replaceEntityRange(start, end, s.length);
    _lastText = newText;
    super.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + s.length),
    );
    if (type != null && s.isNotEmpty) {
      _entities.add(
        _ComposerTextEntity(
          offset: start,
          length: s.length,
          type: {'@type': type},
        ),
      );
      _mergeEntities(type);
    }
    notifyListeners();
  }

  bool get hasContent => text.trim().isNotEmpty;

  void setFormattedText(String source, List<Map<String, dynamic>> entities) {
    _byCode.clear();
    _codeForId.clear();
    _entities.clear();
    _next = 0xE000;

    final customByOffset = <int, Map<String, dynamic>>{};
    for (final entity in entities) {
      final type = entity['type'];
      if (type is! Map || type['@type'] != 'textEntityTypeCustomEmoji') {
        continue;
      }
      final offset = entity['offset'];
      final length = entity['length'];
      if (offset is int && length is int && offset >= 0 && length > 0) {
        customByOffset[offset] = entity;
      }
    }

    final output = StringBuffer();
    final mappedOffsets = List<int>.filled(source.length + 1, 0);
    var sourceOffset = 0;
    while (sourceOffset < source.length) {
      mappedOffsets[sourceOffset] = output.length;
      final custom = customByOffset[sourceOffset];
      final customLength = custom?['length'];
      final customType = custom?['type'];
      if (custom != null &&
          customLength is int &&
          customType is Map &&
          sourceOffset + customLength <= source.length) {
        final rawId = customType['custom_emoji_id'];
        final id = rawId is int ? rawId : int.tryParse('$rawId');
        if (id != null) {
          final code = _next++;
          final fallback = source.substring(
            sourceOffset,
            sourceOffset + customLength,
          );
          _byCode[code] = (id: id, fallback: fallback);
          _codeForId[id] = code;
          output.writeCharCode(code);
          for (var i = 1; i <= customLength; i++) {
            mappedOffsets[sourceOffset + i] = output.length;
          }
          sourceOffset += customLength;
          continue;
        }
      }
      output.writeCharCode(source.codeUnitAt(sourceOffset));
      sourceOffset++;
      mappedOffsets[sourceOffset] = output.length;
    }

    final editorText = output.toString();
    for (final entity in entities) {
      final rawType = entity['type'];
      final offset = entity['offset'];
      final length = entity['length'];
      if (rawType is! Map || offset is! int || length is! int) continue;
      if (rawType['@type'] == 'textEntityTypeCustomEmoji') continue;
      final end = offset + length;
      if (offset < 0 || length <= 0 || end > source.length) continue;
      final mappedStart = mappedOffsets[offset];
      final mappedEnd = mappedOffsets[end];
      if (mappedEnd <= mappedStart) continue;
      _entities.add(
        _ComposerTextEntity(
          offset: mappedStart,
          length: mappedEnd - mappedStart,
          type: Map<String, dynamic>.from(rawType),
        ),
      );
    }
    _lastText = editorText;
    super.value = TextEditingValue(
      text: editorText,
      selection: TextSelection.collapsed(offset: editorText.length),
    );
    notifyListeners();
  }

  bool get hasSelection {
    final sel = selection;
    return sel.isValid && !sel.isCollapsed;
  }

  bool selectionHasFormat(String type) {
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed) return false;
    final start = sel.start < sel.end ? sel.start : sel.end;
    final end = sel.start < sel.end ? sel.end : sel.start;
    return _rangeFullyCovered(type, start, end);
  }

  void toggleFormat(String type) {
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed) return;
    final start = sel.start < sel.end ? sel.start : sel.end;
    final end = sel.start < sel.end ? sel.end : sel.start;
    if (start < 0 || end > text.length || start >= end) return;

    if (_rangeFullyCovered(type, start, end)) {
      _removeFormat(type, start, end);
    } else {
      _entities.add(
        _ComposerTextEntity(
          offset: start,
          length: end - start,
          type: {'@type': type},
        ),
      );
      _mergeEntities(type);
    }
    notifyListeners();
  }

  void formatRange(int start, int end, String type) {
    if (start < 0 || end > text.length || start >= end) return;
    _entities.add(
      _ComposerTextEntity(
        offset: start,
        length: end - start,
        type: {'@type': type},
      ),
    );
    _mergeEntities(type);
    notifyListeners();
  }

  void applyEntityFormat(int start, int end, Map<String, dynamic> type) {
    if (start < 0 || end > text.length || start >= end) return;
    final typeName = type['@type'] as String?;
    if (typeName == null || typeName.isEmpty) return;
    _removeFormat(typeName, start, end);
    _entities.add(
      _ComposerTextEntity(offset: start, length: end - start, type: type),
    );
    if (type.length == 1) _mergeEntities(typeName);
    notifyListeners();
  }

  void clearFormatting() {
    if (_entities.isEmpty) return;
    _entities.clear();
    notifyListeners();
  }

  /// Converts the field to (plainText, entities) for inputMessageText.
  (String, List<Map<String, dynamic>>) toFormatted() {
    final buf = StringBuffer();
    final entities = <Map<String, dynamic>>[];
    final outputOffsets = List<int>.filled(text.length + 1, 0);
    var outLen = 0; // UTF-16 length written so far
    for (var i = 0; i < text.length; i++) {
      outputOffsets[i] = outLen;
      final unit = text.codeUnitAt(i);
      final emoji = _byCode[unit];
      if (emoji != null) {
        final fb = emoji.fallback;
        entities.add({
          '@type': 'textEntity',
          'offset': outLen,
          'length': fb.length,
          'type': {
            '@type': 'textEntityTypeCustomEmoji',
            'custom_emoji_id': emoji.id.toString(),
          },
        });
        buf.write(fb);
        outLen += fb.length;
      } else {
        buf.writeCharCode(unit);
        outLen += 1;
      }
    }
    outputOffsets[text.length] = outLen;
    for (final entity in _validEntities()) {
      final offset = outputOffsets[entity.offset];
      final end = outputOffsets[entity.end];
      if (end <= offset) continue;
      entities.add(entity.toTdJson(offset, end - offset));
    }
    return (buf.toString(), entities);
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final entities = _validEntities();
    if (_byCode.isEmpty && entities.isEmpty) {
      return TextSpan(style: style, text: text);
    }

    final cuts = <int>{0, text.length};
    for (var i = 0; i < text.length; i++) {
      if (_byCode.containsKey(text.codeUnitAt(i))) {
        cuts.add(i);
        cuts.add(i + 1);
      }
    }
    for (final entity in entities) {
      cuts.add(entity.offset);
      cuts.add(entity.end);
    }
    final orderedCuts = cuts.toList()..sort();

    final spans = <InlineSpan>[];
    for (var i = 0; i < orderedCuts.length - 1; i++) {
      final start = orderedCuts[i];
      final end = orderedCuts[i + 1];
      if (start >= end) continue;
      if (end == start + 1) {
        final emoji = _byCode[text.codeUnitAt(start)];
        if (emoji != null) {
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: CustomEmojiView(
                id: emoji.id,
                size: 22,
                color: style?.color,
              ),
            ),
          );
          continue;
        }
      }
      final active = entities
          .where((entity) => entity.offset < end && entity.end > start)
          .toList(growable: false);
      spans.add(
        TextSpan(
          text: text.substring(start, end),
          style: _entityStyle(active, style),
        ),
      );
    }
    return TextSpan(style: style, children: spans);
  }

  void _shiftEntitiesForEdit(String oldText, String newText) {
    if (oldText == newText || _entities.isEmpty) return;
    var prefix = 0;
    final shortest = oldText.length < newText.length
        ? oldText.length
        : newText.length;
    while (prefix < shortest &&
        oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
      prefix++;
    }

    var oldSuffix = oldText.length;
    var newSuffix = newText.length;
    while (oldSuffix > prefix &&
        newSuffix > prefix &&
        oldText.codeUnitAt(oldSuffix - 1) ==
            newText.codeUnitAt(newSuffix - 1)) {
      oldSuffix--;
      newSuffix--;
    }

    final delta = (newSuffix - prefix) - (oldSuffix - prefix);
    final next = <_ComposerTextEntity>[];
    for (final entity in _entities) {
      if (entity.end <= prefix) {
        next.add(entity);
      } else if (entity.offset >= oldSuffix) {
        next.add(entity.copyWith(offset: entity.offset + delta));
      } else {
        final nextOffset = entity.offset < prefix ? entity.offset : newSuffix;
        final nextEnd = entity.end > oldSuffix ? entity.end + delta : prefix;
        if (nextEnd > nextOffset) {
          next.add(
            entity.copyWith(offset: nextOffset, length: nextEnd - nextOffset),
          );
        }
      }
    }
    _entities
      ..clear()
      ..addAll(
        next.where(
          (entity) => entity.offset >= 0 && entity.end <= newText.length,
        ),
      );
    for (final type in _entities.map((entity) => entity.typeName).toSet()) {
      _mergeEntities(type);
    }
  }

  List<_ComposerTextEntity> _validEntities() {
    return _entities
        .where(
          (entity) =>
              entity.offset >= 0 &&
              entity.length > 0 &&
              entity.offset < text.length &&
              entity.end <= text.length,
        )
        .toList()
      ..sort((a, b) {
        final start = a.offset.compareTo(b.offset);
        return start != 0 ? start : b.length.compareTo(a.length);
      });
  }

  bool _rangeFullyCovered(String type, int start, int end) {
    final ranges =
        _entities
            .where(
              (entity) =>
                  entity.typeName == type &&
                  entity.offset < end &&
                  entity.end > start,
            )
            .map(
              (entity) => (
                start: entity.offset < start ? start : entity.offset,
                end: entity.end > end ? end : entity.end,
              ),
            )
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    var cursor = start;
    for (final range in ranges) {
      if (range.start > cursor) return false;
      if (range.end > cursor) cursor = range.end;
      if (cursor >= end) return true;
    }
    return false;
  }

  void _removeFormat(String type, int start, int end) {
    final next = <_ComposerTextEntity>[];
    for (final entity in _entities) {
      if (entity.typeName != type ||
          entity.end <= start ||
          entity.offset >= end) {
        next.add(entity);
        continue;
      }
      if (entity.offset < start) {
        next.add(entity.copyWith(length: start - entity.offset));
      }
      if (entity.end > end) {
        next.add(entity.copyWith(offset: end, length: entity.end - end));
      }
    }
    _entities
      ..clear()
      ..addAll(next);
  }

  void _replaceEntityRange(int start, int end, int insertedLength) {
    final delta = insertedLength - (end - start);
    final insertedEnd = start + insertedLength;
    final next = <_ComposerTextEntity>[];
    for (final entity in _entities) {
      if (entity.end <= start) {
        next.add(entity);
      } else if (entity.offset >= end) {
        next.add(entity.copyWith(offset: entity.offset + delta));
      } else {
        if (entity.offset < start) {
          next.add(entity.copyWith(length: start - entity.offset));
        }
        if (entity.end > end) {
          next.add(
            entity.copyWith(offset: insertedEnd, length: entity.end - end),
          );
        }
      }
    }
    _entities
      ..clear()
      ..addAll(next);
  }

  void _mergeEntities(String type) {
    final same = _entities.where((entity) => entity.typeName == type).toList()
      ..sort((a, b) => a.offset.compareTo(b.offset));
    final other = _entities.where((entity) => entity.typeName != type).toList();
    final merged = <_ComposerTextEntity>[];
    for (final entity in same) {
      if (merged.isEmpty || entity.offset > merged.last.end) {
        merged.add(entity);
      } else if (entity.end > merged.last.end) {
        merged.last.length = entity.end - merged.last.offset;
      }
    }
    _entities
      ..clear()
      ..addAll(other)
      ..addAll(merged);
  }

  TextStyle? _entityStyle(
    List<_ComposerTextEntity> active,
    TextStyle? baseStyle,
  ) {
    var style = baseStyle;
    final decorations = <TextDecoration>[];
    for (final entity in active) {
      switch (entity.typeName) {
        case 'textEntityTypeBold':
          style = (style ?? const TextStyle()).copyWith(
            fontWeight: FontWeight.w700,
          );
        case 'textEntityTypeItalic':
          style = (style ?? const TextStyle()).copyWith(
            fontStyle: FontStyle.italic,
          );
        case 'textEntityTypeUnderline':
          decorations.add(TextDecoration.underline);
        case 'textEntityTypeStrikethrough':
          decorations.add(TextDecoration.lineThrough);
        case 'textEntityTypeCode':
        case 'textEntityTypePre':
        case 'textEntityTypePreCode':
          style = (style ?? const TextStyle()).copyWith(
            fontFamily: 'monospace',
          );
        case 'textEntityTypeSpoiler':
          final color = style?.color ?? Colors.black;
          style = (style ?? const TextStyle()).copyWith(
            color: color.withValues(alpha: 0.08),
            backgroundColor: color.withValues(alpha: 0.28),
          );
        case 'textEntityTypeBlockQuote':
          style = (style ?? const TextStyle()).copyWith(
            backgroundColor: Colors.black.withValues(alpha: 0.06),
          );
      }
    }
    if (decorations.isNotEmpty) {
      style = (style ?? const TextStyle()).copyWith(
        decoration: TextDecoration.combine(decorations),
        decorationColor: style?.color,
      );
    }
    return style;
  }
}
