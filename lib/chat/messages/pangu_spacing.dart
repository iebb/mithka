import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../tdlib/td_models.dart';
import '../links_search/pangu_url_tlds.dart';

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
    final schemedRanges = <List<int>>[];
    final poisonedRanges = <List<int>>[];
    for (final pattern in _detectedTokenPatterns) {
      for (final match in pattern.allMatches(text)) {
        final end = _tokenEnd(text, match.start, match.end);
        if (end <= match.start) continue;
        // A scheme run whose first character follows an ASCII domain symbol
        // cannot start a URL: `中文.https://…` reports no entity at all
        // because fix_url cannot split the prefix off a domain. CJK does
        // not poison it — `看https://…` is a link per TDLib.
        if (pattern == _schemedUrl &&
            match.start > 0 &&
            _isAsciiHostChar(text.codeUnitAt(match.start - 1))) {
          // The whole run is one domain to match_urls: no part of it is a
          // link, the host inside included.
          poisonedRanges.add([match.start, end]);
          continue;
        }
        ranges.add(PanguProtectedRange(match.start, end));
        if (pattern == _schemedUrl) schemedRanges.add([match.start, end]);
      }
    }
    // The bare-URL scanner would re-claim the host inside a schemed URL;
    // its ranges are only for links without one, and the tail of a run a
    // poisoned scheme starts is not a link either.
    final urlRanges = <List<int>>[];
    for (final match in _detectedBareUrl(text)) {
      final end = _tokenEnd(text, match.start, match.end);
      if (end <= match.start) continue;
      final swallowed =
          schemedRanges.any((r) => match.start >= r[0] && match.end <= r[1]) ||
          poisonedRanges.any((r) => match.start >= r[0] && match.end <= r[1]);
      if (!swallowed) {
        ranges.add(PanguProtectedRange(match.start, end));
        urlRanges.add([match.start, end]);
      }
    }
    // A hashtag or mention pattern inside a URL range (`例子.com#frag`'s
    // fragment reads as a hashtag to the regex) is part of the link to
    // TDLib, not a separate token.
    ranges.removeWhere((range) {
      if (urlRanges.any((r) => range.start == r[0] && range.end == r[1])) {
        return false;
      }
      return urlRanges.any((r) => range.start >= r[0] && range.end <= r[1]);
    });
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
    r'[A-Za-z][A-Za-z0-9+.-]*://[^\s<>\"\u00ab\u00bb]+',
  );

  /// The parts of a URL without a scheme are not regular: TDLib's
  /// `match_urls` walks through domain symbols in both directions, so a
  /// host can carry CJK labels (`例子.com`), the last label must be one of
  /// [panguCommonTlds] (or punycode `xn--`), a pure-digit host is only an
  /// IPv4, and a port above 65535 is given back. [_detectedBareUrl] scans
  /// for those ranges by hand instead of trusting a narrower ASCII pattern,
  /// which protected only the ASCII suffix of a Unicode-host URL and let
  /// the spacing pass split the link.
  static Iterable<_TextMatch> _detectedBareUrl(String text) sync* {
    var index = 0;
    while (index < text.length) {
      final end = _bareUrlEnd(text, index);
      if (end > index) {
        yield _TextMatch(index, end);
        index = end;
        continue;
      }
      index++;
    }
  }

  /// The end of the bare URL starting at [index], or [index] when the text
  /// there is not one. Mirrors `fix_url`/`match_urls` in MessageEntity.cpp:
  /// an optional user-info run, then the host's domain symbols split on '.',
  /// its labels and TLD validated, then a port and a path taken when well
  /// formed.
  static int _bareUrlEnd(String text, int index) {
    // A scheme behind a domain symbol is not a link start: `中文.https://…`
    // leaves match_urls no place to begin, and TDLib reports no entity. The
    // scheme itself is handled by the regex list, so a run that contains one
    // only yields its pre-scheme prefix, which is never a valid host here.
    if (index > 0 && _schemeAt(text, index) != null) return index;
    // User info: `user@` (the password form `user:pass@` included) belongs
    // to the link, mirroring the email-style Url TDLib reports.
    final at = _userInfoAt(text, index);
    final hostStart = at == null ? index : at + 1;
    var hostEnd = hostStart;
    while (hostEnd < text.length && _isHostChar(text.codeUnitAt(hostEnd))) {
      hostEnd++;
    }
    if (hostEnd == hostStart) return index;
    // Trim sentence punctuation off the host's tail.
    var hostLast = hostEnd;
    while (hostLast > hostStart && _isGiveBack(text.codeUnitAt(hostLast - 1))) {
      hostLast--;
    }
    if (hostLast <= hostStart) return index;
    var hostText = text.substring(hostStart, hostLast);
    // A bare host may not end with a bare '.'; TDLib strips trailing dots
    // before validating the labels.
    while (hostText.endsWith('.')) {
      hostText = hostText.substring(0, hostText.length - 1);
    }
    if (!_isBareHost(hostText)) return index;
    var urlEnd = hostLast;
    // Port: ':' digits, value 1..65535; an invalid one is left off the
    // link, and the ':' stays sentence punctuation.
    if (urlEnd < text.length && text.codeUnitAt(urlEnd) == 0x3a) {
      final portEnd = _portEnd(text, urlEnd + 1);
      if (portEnd > urlEnd + 1) {
        urlEnd = portEnd;
      }
    }
    // Path: one of / ? #, then anything to a path delimiter.
    if (urlEnd < text.length &&
        (text.codeUnitAt(urlEnd) == 0x2f ||
            text.codeUnitAt(urlEnd) == 0x3f ||
            text.codeUnitAt(urlEnd) == 0x23)) {
      urlEnd++;
      while (urlEnd < text.length &&
          _isUrlPathSymbol(text.codeUnitAt(urlEnd))) {
        urlEnd++;
      }
    }
    while (urlEnd > index + 1 && _isGiveBack(text.codeUnitAt(urlEnd - 1))) {
      urlEnd--;
    }
    // A bare host never starts mid-word: the code unit before the run must
    // not be a domain symbol (match_urls' prefix rule). An email-shaped
    // link carries its own user info, which match_urls reads from the '@'
    // instead, so CJK before the user name does not poison it.
    if (at == null && index > 0 && _isHostChar(text.codeUnitAt(index - 1))) {
      return index;
    }
    return urlEnd;
  }

  /// The '@' ending a user-info run that starts at [index] and ends by
  /// [hostEnd], when the run is all user-info characters (letters, digits,
  /// and `. : _ % + -`), else null. TDLib's fix_url includes `user@` /
  /// `user:pass@` in the Url, and an email-shaped text is one whole Url.
  static int? _userInfoAt(String text, int index) {
    var end = index;
    while (end < text.length) {
      final unit = text.codeUnitAt(end);
      final isUserInfoChar =
          (unit >= 0x30 && unit <= 0x39) ||
          (unit >= 0x41 && unit <= 0x5a) ||
          (unit >= 0x61 && unit <= 0x7a) ||
          unit == 0x2e ||
          unit == 0x3a ||
          unit == 0x5f ||
          unit == 0x25 ||
          unit == 0x2b ||
          unit == 0x2d;
      if (!isUserInfoChar) break;
      end++;
    }
    if (end < text.length && text.codeUnitAt(end) == 0x40 && end > index) {
      return end;
    }
    return null;
  }

  /// The scheme at [index] when one starts there, else null.
  static String? _schemeAt(String text, int index) {
    if (index >= text.length) return null;
    var end = index;
    while (end < text.length) {
      final unit = text.codeUnitAt(end);
      final isSchemeChar =
          (unit >= 0x41 && unit <= 0x5a) ||
          (unit >= 0x61 && unit <= 0x7a) ||
          (end > index &&
              ((unit >= 0x30 && unit <= 0x39) ||
                  unit == 0x2b ||
                  unit == 0x2d ||
                  unit == 0x2e));
      if (!isSchemeChar) break;
      end++;
    }
    if (end > index + 2 &&
        end + 2 < text.length &&
        text.codeUnitAt(end) == 0x3a &&
        text.codeUnitAt(end + 1) == 0x2f &&
        text.codeUnitAt(end + 2) == 0x2f) {
      return text.substring(index, end);
    }
    return null;
  }

  /// An ASCII domain symbol: the characters that, before a scheme start,
  /// glue the two into one domain run and leave the scheme nowhere to begin.
  static bool _isAsciiHostChar(int unit) =>
      unit == 0x2e ||
      unit == 0x5f ||
      unit == 0x2d ||
      unit == 0x7e ||
      (unit >= 0x30 && unit <= 0x39) ||
      (unit >= 0x41 && unit <= 0x5a) ||
      (unit >= 0x61 && unit <= 0x7a);

  /// A character of a host run: TDLib's `is_domain_symbol` — ASCII
  /// `. alnum _ - ~`, or any non-separator unicode (which covers CJK).
  /// `@` and `:` are the user-info and port separators, handled by the
  /// caller, so they end a plain host run.
  static bool _isHostChar(int unit) {
    if (unit == 0x40 || unit == 0x3a) return false;
    if (unit < 0x80) {
      return unit == 0x2e ||
          unit == 0x5f ||
          unit == 0x2d ||
          unit == 0x7e ||
          (unit >= 0x30 && unit <= 0x39) ||
          (unit >= 0x41 && unit <= 0x5a) ||
          (unit >= 0x61 && unit <= 0x7a);
    }
    return !_isRuneSeparator(String.fromCharCode(unit).runes.first);
  }

  /// Unicode separators (Zs/Zl/Zp plus the control spaces TDLib rejects).
  static bool _isRuneSeparator(int rune) {
    if (rune == 0x20 || rune == 0x09 || rune == 0x0a || rune == 0x0d) {
      return true;
    }
    if ((rune >= 0x1c && rune <= 0x1f) || rune == 0x0b || rune == 0x0c) {
      return true;
    }
    if (rune == 0xa0 || rune == 0x1680) return true;
    if (rune >= 0x2000 && rune <= 0x200a) return true;
    if (rune == 0x2028 || rune == 0x2029 || rune == 0x202f || rune == 0x205f) {
      return true;
    }
    return rune == 0x3000 || rune == 0xfeff;
  }

  /// Path characters TDLib allows (`is_url_path_symbol`): anything that is
  /// not whitespace, `<> " « »`, a separator, or a control character.
  static bool _isUrlPathSymbol(int unit) {
    if (unit == 0x3c || unit == 0x3e || unit == 0x22) return false;
    if (unit == 0xab || unit == 0xbb) return false;
    if (unit <= 0x20 || unit == 0x7f) return false;
    if (unit < 0x80) return true;
    return !_isRuneSeparator(String.fromCharCode(unit).runes.first);
  }

  /// Where a valid port ends after its `:`, or the `:` itself when there is
  /// no port to take: digits only, value at most 65535, at most five
  /// significant digits.
  static int _portEnd(String text, int start) {
    var end = start;
    while (end < text.length &&
        text.codeUnitAt(end) >= 0x30 &&
        text.codeUnitAt(end) <= 0x39) {
      end++;
    }
    if (end == start) return start - 1;
    final port = int.tryParse(text.substring(start, end));
    // TDLib refuses a port of 0 (fix_url checks 1..65535).
    if (port == null || port > 65535 || port == 0) return start - 1;
    final significant = text
        .substring(start, end)
        .replaceFirst(RegExp(r'^0+'), '');
    if (significant.length > 5) return start - 1;
    return end;
  }

  /// Whether [host] is a host TDLib links without a scheme: two or more
  /// labels split on '.', each 1..63 characters with no trailing '-', the
  /// TLD is a common one (or punycode `xn--`), and a pure-digit host is
  /// only an IPv4.
  static bool _isBareHost(String host) {
    if (host.isEmpty) return false;
    var hostText = host;
    while (hostText.endsWith('.')) {
      hostText = hostText.substring(0, hostText.length - 1);
    }
    if (hostText.isEmpty) return false;
    final labels = hostText.split('.');
    if (labels.length < 2) return false;
    final allDigits = labels.every(
      (label) =>
          label.isNotEmpty && label.runes.every((r) => r >= 0x30 && r <= 0x39),
    );
    if (allDigits) return labels.length == 4;
    for (final label in labels) {
      // fix_url: every label is 1..63 characters and never ends in '-'.
      if (label.isEmpty || label.length > 63 || label.endsWith('-')) {
        return false;
      }
    }
    // TDLib's is_common_tld is case-insensitive for the ASCII TLDs
    // (`例子.COM/中文abc` is one Url, offset 0, probed against the pinned
    // tdjson), while a punycode TLD keeps its lowercase `xn--` prefix
    // (`例子.XN--ABC` is not a link; `例子.xn--abc` is).
    final tld = labels.last;
    if (tld.startsWith('xn--')) {
      // fix_url: the punycode TLD as a whole must exceed five bytes and hold
      // only ASCII letters and digits after the prefix.
      if (tld.length <= 5) return false;
      final body = tld.substring(4);
      if (body.isEmpty) return false;
      return body.runes.every(
        (r) =>
            (r >= 0x30 && r <= 0x39) ||
            (r >= 0x61 && r <= 0x7a) ||
            (r >= 0x41 && r <= 0x5a),
      );
    }
    if (tld.contains('-') || tld.contains('_')) return false;
    return panguCommonTlds.contains(tld.toLowerCase());
  }

  /// Sentence punctuation TDLib hands back from the end of a link.
  static bool _isGiveBack(int unit) =>
      unit == 0x2e ||
      unit == 0x3a ||
      unit == 0x3b ||
      unit == 0x2c ||
      unit == 0x28 ||
      unit == 0x27 ||
      unit == 0x3f ||
      unit == 0x21 ||
      unit == 0x60;

  static final List<RegExp> _detectedTokenPatterns = [
    _schemedUrl,
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

/// A [Match] over plain text offsets: the hand-written bare-URL scanner
/// yields these where a RegExp cannot express the shape. The pattern list
/// only reads `start` and `end`, so the group accessors stay trivial.
class _TextMatch implements Match {
  const _TextMatch(this.start, this.end);

  @override
  final int start;

  @override
  final int end;

  @override
  String operator [](int group) =>
      group == 0 ? '' : throw RangeError.index(group, this);

  @override
  String? group(int group) => group == 0 ? '' : null;

  @override
  List<String?> groups(List<int> groupIndices) => [
    for (final i in groupIndices) group(i),
  ];

  @override
  String get input => '';

  @override
  Pattern get pattern => '';

  @override
  int get groupCount => 0;
}
