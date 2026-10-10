import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../tdlib/td_models.dart';

/// 盘古之白 — the space that splits full-width CJK text from half-width text.
///
/// Mixed Chinese/English reads badly when the two scripts touch, so a single
/// ASCII space goes between a CJK character and a half-width Latin letter or
/// digit. The same rule serves both directions of a chat: incoming messages are
/// re-spaced for display only, outgoing messages are re-spaced before TDLib
/// sees them.
///
/// Every insertion is recorded as a UTF-16 offset in the *source* string, which
/// is what TDLib entity ranges use (and what Dart `String` indices are), so
/// entities can be shifted onto the new text. Ranges whose content the protocol
/// or a tap handler reads back verbatim — code, links, mentions, hashtags,
/// custom emoji — are never modified inside; formatting ranges such as bold or
/// spoiler are, because they only style the text they cover.
class PanguSpacing {
  PanguSpacing._();

  /// Entity kinds that stay byte-identical: their text is a link target, a
  /// command, a searchable token, a monospace run, or a custom emoji fallback.
  static const Set<String> protectedEntityTypes = {
    'textEntityTypeUnknown',
    'textEntityTypeMention',
    'textEntityTypeMentionName',
    'textEntityTypeHashtag',
    'textEntityTypeCashtag',
    'textEntityTypeBotCommand',
    'textEntityTypeUrl',
    'textEntityTypeTextUrl',
    'textEntityTypeEmailAddress',
    'textEntityTypePhoneNumber',
    'textEntityTypeBankCardNumber',
    'textEntityTypeCode',
    'textEntityTypePre',
    'textEntityTypePreCode',
    'textEntityTypeCustomEmoji',
    'textEntityTypeMediaTimestamp',
    'textEntityTypeMathematicalExpression',
  };

  /// Spaced [text] plus the offsets it was spaced at.
  ///
  /// [protectedRanges] are UTF-16 ranges in [text]; an insertion landing
  /// strictly inside one is skipped, while one landing exactly on its edges is
  /// kept — the space then sits outside the protected run, next to it.
  static PanguText transformText(
    String text, {
    List<PanguProtectedRange> protectedRanges = const [],
  }) {
    final length = text.length;
    if (length < 2) return PanguText(text, const []);
    final guarded = _mergeRanges(protectedRanges, length);
    final inserted = <int>[];
    final buffer = StringBuffer();
    var copied = 0;
    for (var index = 1; index < length; index++) {
      if (!_needsSpace(text, index)) continue;
      if (_isGuarded(index, guarded)) continue;
      inserted.add(index);
      buffer
        ..write(text.substring(copied, index))
        ..write(' ');
      copied = index;
    }
    if (inserted.isEmpty) return PanguText(text, const []);
    buffer.write(text.substring(copied));
    return PanguText(buffer.toString(), inserted);
  }

  /// The ranges of [entities] whose content must survive untouched.
  static List<PanguProtectedRange> protectedRangesFor(
    Iterable<MessageTextEntity> entities,
  ) {
    final ranges = <PanguProtectedRange>[];
    for (final entity in entities) {
      if (!protectedEntityTypes.contains(entity.type)) continue;
      if (entity.length <= 0) continue;
      ranges.add(PanguProtectedRange(entity.offset, entity.end));
    }
    return ranges;
  }

  /// The tokens TDLib's own detector would claim in [text], as ranges to
  /// protect.
  ///
  /// An outgoing message carries only the entities its composer made, so a plain
  /// caption reaches the spacing pass unannotated — and TDLib adds `Url`,
  /// `Mention`, `Hashtag` and the rest afterwards (`find_entities` in
  /// td/telegram/MessageEntity.cpp). Spacing inside one of those changes what
  /// the token means rather than how it reads: `https://example.com/中文abc`
  /// becomes a different URL, and `#中文tag` becomes a hashtag and a word.
  ///
  /// Detecting more than TDLib would is safe — it only costs a space that was
  /// not inserted, never a moved entity — so the patterns stay broad. Hosts are
  /// ASCII, because a unicode label would let an ordinary CJK sentence with a
  /// full stop in it swallow the words around it; a path is not, because that is
  /// where the CJK a link can legitimately carry lives.
  @visibleForTesting
  static List<PanguProtectedRange> detectedRangesFor(String text) {
    if (text.length < 2) return const [];
    final ranges = <PanguProtectedRange>[];
    for (final pattern in _detectedTokenPatterns) {
      for (final match in pattern.allMatches(text)) {
        final end = _tokenEnd(text, match.start, match.end);
        if (end > match.start) {
          ranges.add(PanguProtectedRange(match.start, end));
        }
      }
    }
    return ranges;
  }

  /// Spaced [text] for a surface that has no entity list to trust: a caption or
  /// a draft, where the only ranges worth protecting are the ones TDLib would
  /// detect in the raw text.
  static PanguText transformUnannotated(String text) =>
      transformText(text, protectedRanges: detectedRangesFor(text));

  /// Spaced text and the entities moved onto it, for rendering a message.
  ///
  /// Returns the arguments unchanged — same list identity — when nothing was
  /// inserted, so callers can keep their own span caches.
  static PanguDisplay display(String text, List<MessageTextEntity> entities) {
    final transform = transformText(
      text,
      protectedRanges: protectedRangesFor(entities),
    );
    if (!transform.changed) {
      return PanguDisplay(text, entities, const []);
    }
    return PanguDisplay(
      transform.text,
      shiftEntities(entities, transform.insertedOffsets),
      transform.insertedOffsets,
    );
  }

  /// Moves [entities] onto text that gained a space at each of
  /// [insertedOffsets]. An entity starting where a space landed moves past it,
  /// so the space stays outside the entity; one ending there keeps its end, so
  /// the space lands after it.
  static List<MessageTextEntity> shiftEntities(
    List<MessageTextEntity> entities,
    List<int> insertedOffsets,
  ) {
    if (entities.isEmpty || insertedOffsets.isEmpty) return entities;
    final shifted = <MessageTextEntity>[];
    for (final entity in entities) {
      final start =
          entity.offset + _countAtMost(insertedOffsets, entity.offset);
      final end = entity.end + _countBefore(insertedOffsets, entity.end);
      shifted.add(
        MessageTextEntity(
          offset: start,
          length: end > start ? end - start : 0,
          type: entity.type,
          url: entity.url,
          userId: entity.userId,
          customEmojiId: entity.customEmojiId,
          language: entity.language,
          button: entity.button,
          typeData: entity.typeData,
        ),
      );
    }
    return shifted;
  }

  /// Spaced caption or body for a message about to be sent, with its TDLib
  /// `textEntity` payloads moved onto the new text.
  ///
  /// [entities] is the JSON list the composer already produced, so offsets stay
  /// valid for `formattedText` and mention detection still sees the final text.
  static ({String text, List<Map<String, dynamic>> entities}) outgoing(
    String text,
    List<Map<String, dynamic>> entities,
  ) {
    final ranges = <PanguProtectedRange>[
      // The composer's entities, plus whatever TDLib will detect in the text
      // itself once it is sent — a caption typed by hand has no link entities.
      ...detectedRangesFor(text),
    ];
    for (final entity in entities) {
      final type = entity['type'];
      final name = type is Map ? type['@type'] : null;
      if (name is! String || !protectedEntityTypes.contains(name)) continue;
      final offset = _readOffset(entity['offset']);
      final length = _readOffset(entity['length']);
      if (length <= 0) continue;
      ranges.add(PanguProtectedRange(offset, offset + length));
    }
    final transform = transformText(text, protectedRanges: ranges);
    if (!transform.changed) return (text: text, entities: entities);
    return (
      text: transform.text,
      entities: [
        for (final entity in entities) _shiftTdEntity(entity, transform),
      ],
    );
  }

  /// Maps a range of spaced text back onto the source text it was spaced from.
  ///
  /// A range that starts on an inserted space starts after it and one that ends
  /// on an inserted space ends before it, so quoting a spaced message quotes
  /// what the author wrote, never a space they did not type.
  static ({int start, int end}) reverseRange({
    required int start,
    required int end,
    required List<int> insertedOffsets,
    required int sourceLength,
  }) {
    final lower = start.clamp(0, sourceLength);
    final upper = end.clamp(lower, sourceLength);
    if (insertedOffsets.isEmpty) return (start: lower, end: upper);

    final displayLength = sourceLength + insertedOffsets.length;
    // Where each inserted space actually sits in the spaced string.
    final positions = <int>[
      for (var index = 0; index < insertedOffsets.length; index++)
        insertedOffsets[index] + index,
    ];
    final inserted = positions.toSet();

    int toSource(int displayIndex, {required bool isEnd}) {
      var cursor = displayIndex.clamp(0, displayLength);
      if (isEnd) {
        while (cursor > 0 && inserted.contains(cursor - 1)) {
          cursor--;
        }
      } else {
        while (cursor < displayLength && inserted.contains(cursor)) {
          cursor++;
        }
      }
      final before = positions.where((position) => position < cursor).length;
      return math.min(math.max(cursor - before, 0), sourceLength);
    }

    final sourceStart = toSource(start, isEnd: false);
    final sourceEnd = toSource(end, isEnd: true);
    return (start: sourceStart, end: math.max(sourceStart, sourceEnd));
  }

  /// Spacing gate for callers that hold the switches themselves, so the answer
  /// is the arguments untouched whenever 盘古之白 is off.
  static ({String text, List<Map<String, dynamic>> entities}) gated({
    required bool enabled,
    required String text,
    required List<Map<String, dynamic>> entities,
  }) => enabled ? outgoing(text, entities) : (text: text, entities: entities);

  static Map<String, dynamic> _shiftTdEntity(
    Map<String, dynamic> entity,
    PanguText transform,
  ) {
    final offset = _readOffset(entity['offset']);
    final length = _readOffset(entity['length']);
    final start = offset + _countAtMost(transform.insertedOffsets, offset);
    final end =
        offset +
        length +
        _countBefore(transform.insertedOffsets, offset + length);
    return {
      ...entity,
      'offset': start,
      'length': end > start ? end - start : 0,
    };
  }

  static int _readOffset(Object? value) => switch (value) {
    int() => value,
    num() => value.toInt(),
    _ => 0,
  };

  /// A URL with a scheme, then everything up to whitespace or one of the
  /// delimiters TDLib ends a path at (`is_url_path_symbol`).
  static final RegExp _schemedUrl = RegExp(
    r'[A-Za-z][A-Za-z0-9+.-]*://[^\s<>"\u00ab\u00bb]+',
  );

  /// A bare host with its optional user info, port and path. The host ends in an
  /// ASCII letter TLD so a version number, a filename or a CJK sentence with a
  /// full stop in it is not mistaken for one; the path is unrestricted, because
  /// that is where a link carries its CJK.
  static final RegExp _bareUrl = RegExp(
    r'(?:[A-Za-z0-9_~%+-]+@)?'
    r'(?:[A-Za-z0-9](?:[A-Za-z0-9_-]*[A-Za-z0-9])?\.)+'
    r'[A-Za-z]{2,}'
    r'(?::[0-9]{1,5})?'
    r'(?:[/?#][^\s<>"\u00ab\u00bb]*)?',
  );

  static final List<RegExp> _detectedTokenPatterns = [
    _schemedUrl,
    _bareUrl,
    // A mention: Telegram usernames are ASCII, so a CJK tail is not part of it.
    RegExp(r'@[A-Za-z0-9_]{3,32}'),
    // A hashtag runs to 256 letters of any script (TDLib's `is_hashtag_letter`),
    // so `#中文tag` is one token and a space would make it two.
    RegExp(r'#[\p{L}\p{N}_]{1,256}', unicode: true),
    // A cashtag is ASCII letters, like the tickers it names.
    RegExp(r'\$[A-Za-z]{2,}'),
    // A bot command only opens a message or follows a space, so a path is not
    // read as one twice over. Its name is ASCII, like Telegram's own syntax.
    RegExp(r'(?:^|(?<=\s))/[A-Za-z0-9_]{2,}(?:@[A-Za-z0-9_]{3,})?'),
  ];

  /// Where a detected token really ends. TDLib strips the sentence punctuation a
  /// link picks up at its tail (`bad_path_end_chars`), and a space belongs after
  /// that punctuation rather than inside the protected range.
  static int _tokenEnd(String text, int start, int end) {
    var last = end;
    while (last > start + 1 &&
        _tokenTailChars.contains(text.codeUnitAt(last - 1))) {
      last--;
    }
    return last;
  }

  /// . : ; , ( ' ? ! and the backtick.
  static const Set<int> _tokenTailChars = {
    0x2e,
    0x3a,
    0x3b,
    0x2c,
    0x28,
    0x27,
    0x3f,
    0x21,
    0x60,
  };

  /// Whether a space belongs between the characters on either side of [index].
  static bool _needsSpace(String text, int index) {
    final left = _scriptEndingAt(text, index);
    if (left == _Script.other) return false;
    final right = _scriptStartingAt(text, index);
    if (right == _Script.other) return false;
    return left != right;
  }

  /// Script of the character whose last code unit sits at [index] - 1.
  ///
  /// Classified characters all live in the BMP, so anything reaching the
  /// supplementary planes is only inspected through its surrogate pair — an
  /// insertion can never land between the two halves.
  static _Script _scriptEndingAt(String text, int index) {
    final unit = text.codeUnitAt(index - 1);
    if (_isLowSurrogate(unit) &&
        index >= 2 &&
        _isHighSurrogate(text.codeUnitAt(index - 2))) {
      return _supplementaryScript(_codePoint(text.codeUnitAt(index - 2), unit));
    }
    return _bmpScript(unit);
  }

  /// Script of the character starting at [index].
  static _Script _scriptStartingAt(String text, int index) {
    final unit = text.codeUnitAt(index);
    if (_isHighSurrogate(unit) &&
        index + 1 < text.length &&
        _isLowSurrogate(text.codeUnitAt(index + 1))) {
      return _supplementaryScript(_codePoint(unit, text.codeUnitAt(index + 1)));
    }
    return _bmpScript(unit);
  }

  static _Script _bmpScript(int unit) {
    // Half-width digits and Latin letters.
    if ((unit >= 0x30 && unit <= 0x39) ||
        (unit >= 0x41 && unit <= 0x5A) ||
        (unit >= 0x61 && unit <= 0x7A)) {
      return _Script.latin;
    }
    if ((unit >= 0x3040 && unit <= 0x30FF) || // Hiragana, Katakana
        (unit >= 0x3400 && unit <= 0x4DBF) || // CJK extension A
        (unit >= 0x4E00 && unit <= 0x9FFF) || // CJK unified ideographs
        (unit >= 0xAC00 && unit <= 0xD7AF) || // Hangul syllables
        (unit >= 0xF900 && unit <= 0xFAFF) || // CJK compatibility ideographs
        (unit >= 0x1100 && unit <= 0x11FF) || // Hangul jamo
        (unit >= 0x3130 && unit <= 0x318F)) {
      // Hangul compatibility jamo
      return _Script.cjk;
    }
    return _Script.other;
  }

  static _Script _supplementaryScript(int codePoint) {
    // CJK extension B and later, plus the compatibility supplement.
    if ((codePoint >= 0x20000 && codePoint <= 0x2FA1F) ||
        (codePoint >= 0x30000 && codePoint <= 0x323AF)) {
      return _Script.cjk;
    }
    return _Script.other;
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

  static bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

  static int _codePoint(int high, int low) =>
      0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00);

  /// Clamps, drops and merges [ranges] so a lookup only walks disjoint spans.
  static List<PanguProtectedRange> _mergeRanges(
    List<PanguProtectedRange> ranges,
    int textLength,
  ) {
    if (ranges.isEmpty) return const [];
    final clamped = <PanguProtectedRange>[];
    for (final range in ranges) {
      final start = range.start.clamp(0, textLength);
      final end = range.end.clamp(start, textLength);
      if (end > start) clamped.add(PanguProtectedRange(start, end));
    }
    if (clamped.isEmpty) return const [];
    clamped.sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      return byStart != 0 ? byStart : a.end.compareTo(b.end);
    });
    final merged = <PanguProtectedRange>[clamped.first];
    for (final range in clamped.skip(1)) {
      final last = merged.last;
      if (range.start <= last.end) {
        merged[merged.length - 1] = PanguProtectedRange(
          last.start,
          range.end > last.end ? range.end : last.end,
        );
      } else {
        merged.add(range);
      }
    }
    return merged;
  }

  /// Whether [index] falls strictly inside one of the merged [ranges].
  static bool _isGuarded(int index, List<PanguProtectedRange> ranges) {
    for (final range in ranges) {
      if (index <= range.start) return false;
      if (index < range.end) return true;
    }
    return false;
  }

  static int _countAtMost(List<int> offsets, int value) {
    var count = 0;
    for (final offset in offsets) {
      if (offset > value) break;
      count++;
    }
    return count;
  }

  static int _countBefore(List<int> offsets, int value) {
    var count = 0;
    for (final offset in offsets) {
      if (offset >= value) break;
      count++;
    }
    return count;
  }
}

/// A UTF-16 range in a source string whose interior a pangu pass must keep.
class PanguProtectedRange {
  const PanguProtectedRange(this.start, this.end);

  final int start;
  final int end;
}

/// Spaced text and where each space went, as offsets in the source string.
class PanguText {
  const PanguText(this.text, this.insertedOffsets);

  final String text;

  /// Ascending offsets in the source string, one per inserted space.
  final List<int> insertedOffsets;

  bool get changed => insertedOffsets.isNotEmpty;
}

/// A text and its entities after a display-side pangu pass.
class PanguDisplay {
  const PanguDisplay(this.text, this.entities, this.insertedOffsets);

  final String text;
  final List<MessageTextEntity> entities;
  final List<int> insertedOffsets;

  bool get changed => insertedOffsets.isNotEmpty;
}

/// Keeps one bubble's or one widget's pangu results across rebuilds.
///
/// The spacing itself is cheap, but a fresh entity list per build defeats the
/// span caches downstream, which compare by identity. Entries are keyed by text
/// and validated against the entity list they were built from, so a message
/// that swaps text (translation) or entities (edit) can never render a stale
/// pair. The map dies with the state that owns it.
class PanguDisplayMemo {
  final Map<String, _PanguMemoEntry> _entries = {};

  PanguDisplay resolve(String text, List<MessageTextEntity> entities) {
    final hit = _entries[text];
    if (hit != null && identical(hit.entities, entities)) return hit.display;
    final display = PanguSpacing.display(text, entities);
    _entries[text] = _PanguMemoEntry(entities, display);
    if (_entries.length > _capacity) _entries.remove(_entries.keys.first);
    return display;
  }

  void clear() => _entries.clear();

  static const int _capacity = 8;
}

class _PanguMemoEntry {
  const _PanguMemoEntry(this.entities, this.display);

  final List<MessageTextEntity> entities;
  final PanguDisplay display;
}

enum _Script { cjk, latin, other }
