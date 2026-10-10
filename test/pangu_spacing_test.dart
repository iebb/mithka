import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/pangu_spacing.dart';
import 'package:mithka/tdlib/td_models.dart';

MessageTextEntity entity(int offset, int length, String type) =>
    MessageTextEntity(offset: offset, length: length, type: type);

Map<String, dynamic> tdEntity(int offset, int length, String type) => {
  '@type': 'textEntity',
  'offset': offset,
  'length': length,
  'type': {'@type': type},
};

void main() {
  group('script boundaries', () {
    test('spaces CJK followed by half-width letters', () {
      final transform = PanguSpacing.transformText('中文English');
      expect(transform.text, '中文 English');
      expect(transform.insertedOffsets, [2]);
    });

    test('spaces half-width letters followed by CJK', () {
      expect(PanguSpacing.transformText('English中文').text, 'English 中文');
    });

    test('spaces digits on both sides', () {
      final transform = PanguSpacing.transformText('共100人');
      expect(transform.text, '共 100 人');
      expect(transform.insertedOffsets, [1, 4]);
    });

    test('covers Japanese kana and Hangul', () {
      expect(PanguSpacing.transformText('カタカナabc').text, 'カタカナ abc');
      expect(PanguSpacing.transformText('ひらがなabc').text, 'ひらがな abc');
      expect(PanguSpacing.transformText('한국어abc').text, '한국어 abc');
      expect(PanguSpacing.transformText('abc한국어').text, 'abc 한국어');
    });

    test('covers ideographs beyond the BMP without splitting their pair', () {
      // 𠀀 is one code point stored as two UTF-16 units, so the space lands
      // at offset 2 and the pair stays intact.
      final transform = PanguSpacing.transformText('𠀀abc');
      expect(transform.text, '𠀀 abc');
      expect(transform.insertedOffsets, [2]);
      expect(PanguSpacing.transformText('abc𠀀').text, 'abc 𠀀');
    });

    test('leaves CJK next to CJK alone', () {
      final transform = PanguSpacing.transformText('中文日本語한국어');
      expect(transform.changed, isFalse);
      expect(transform.text, '中文日本語한국어');
    });

    test('leaves full-width letters alone', () {
      expect(PanguSpacing.transformText('中文ＡＢＣ１２３').changed, isFalse);
    });

    test('leaves punctuation and symbols alone', () {
      for (final text in [
        '中文，English',
        '中文。English',
        '中文,English',
        '中文.txt',
        '（中文）English',
      ]) {
        expect(PanguSpacing.transformText(text).text, text, reason: text);
      }
      // A letter still counts when a symbol follows it.
      expect(PanguSpacing.transformText('中文C++').text, '中文 C++');
    });

    test('keeps existing whitespace as the separator', () {
      for (final text in ['中文 English', '中文\nEnglish', '中文\tEnglish']) {
        expect(PanguSpacing.transformText(text).changed, isFalse);
      }
    });

    test('never doubles a space on a second pass', () {
      final once = PanguSpacing.transformText('中文English中文');
      final twice = PanguSpacing.transformText(once.text);
      expect(once.text, '中文 English 中文');
      expect(twice.changed, isFalse);
    });

    test('treats emoji as a neutral neighbour', () {
      expect(PanguSpacing.transformText('中文😀English').changed, isFalse);
      expect(PanguSpacing.transformText('中文👨‍👩‍👧abc').changed, isFalse);
    });

    test('spaces before a decomposed letter but never inside its cluster', () {
      // The space goes before the whole e + combining acute cluster…
      expect(PanguSpacing.transformText('中文e\u0301').text, '中文 e\u0301');
      // …and a cluster that ends in a combining mark is not a Latin neighbour.
      expect(PanguSpacing.transformText('e\u0301中文').changed, isFalse);
    });

    test('handles text too short to space', () {
      expect(PanguSpacing.transformText('').changed, isFalse);
      expect(PanguSpacing.transformText('中').changed, isFalse);
    });

    test('keeps every line of a multi-line message', () {
      final transform = PanguSpacing.transformText('第一行abc\n第二行def');
      expect(transform.text, '第一行 abc\n第二行 def');
      expect(transform.insertedOffsets, [3, 10]);
    });
  });

  group('protected ranges', () {
    test('keeps a code run intact but spaces around it', () {
      final transform = PanguSpacing.transformText(
        '中文code中文',
        protectedRanges: const [PanguProtectedRange(2, 6)],
      );
      expect(transform.text, '中文 code 中文');
      expect(transform.insertedOffsets, [2, 6]);
    });

    test('never spaces inside a protected run', () {
      const text = 'print("中文")';
      final transform = PanguSpacing.transformText(
        text,
        protectedRanges: const [PanguProtectedRange(0, 11)],
      );
      assert(text.length == 11);
      expect(transform.changed, isFalse);
      // Without the guard the same run gains a space at its leading boundary.
      expect(
        PanguSpacing.transformText('中文print("中文")').text,
        '中文 print("中文")',
      );
    });

    test('merges overlapping ranges', () {
      final transform = PanguSpacing.transformText(
        'a中文b英文c',
        protectedRanges: const [
          PanguProtectedRange(1, 4),
          PanguProtectedRange(3, 6),
        ],
      );
      expect(transform.text, 'a 中文b英文 c');
    });

    test('clamps ranges that reach past the text', () {
      final transform = PanguSpacing.transformText(
        '中文abc',
        protectedRanges: const [PanguProtectedRange(-4, 99)],
      );
      expect(transform.changed, isFalse);
    });

    test('protects entity kinds whose text is protocol data', () {
      final ranges = PanguSpacing.protectedRangesFor([
        entity(0, 3, 'textEntityTypeUrl'),
        entity(4, 2, 'textEntityTypeBold'),
        entity(7, 1, 'textEntityTypeCustomEmoji'),
        entity(9, 4, 'textEntityTypeHashtag'),
        entity(20, 2, 'textEntityTypeCode'),
        entity(30, 0, 'textEntityTypePre'),
      ]);
      expect(ranges.map((range) => (range.start, range.end)).toList(), [
        (0, 3),
        (7, 8),
        (9, 13),
        (20, 22),
      ]);
    });
  });

  group('display entities', () {
    test('moves a formatting entity onto the spaced text', () {
      final display = PanguSpacing.display('中文English', [
        entity(2, 7, 'textEntityTypeBold'),
      ]);
      expect(display.text, '中文 English');
      expect(display.entities.single.offset, 3);
      expect(display.entities.single.length, 7);
      expect(
        display.text.substring(
          display.entities.single.offset,
          display.entities.single.end,
        ),
        'English',
      );
    });

    test('grows an entity that spans an insertion', () {
      final display = PanguSpacing.display('中文English中文', [
        entity(0, 9, 'textEntityTypeItalic'),
      ]);
      expect(display.text, '中文 English 中文');
      expect(display.entities.single.offset, 0);
      expect(display.entities.single.length, 10);
      expect(
        display.text.substring(
          display.entities.single.offset,
          display.entities.single.end,
        ),
        '中文 English',
      );
    });

    test('keeps a hashtag together while spacing after it', () {
      final display = PanguSpacing.display('看#中文tag好', [
        entity(1, 6, 'textEntityTypeHashtag'),
      ]);
      expect(display.text, '看#中文tag 好');
      expect(display.entities.single.offset, 1);
      expect(display.entities.single.length, 6);
      expect(
        display.text.substring(
          display.entities.single.offset,
          display.entities.single.end,
        ),
        '#中文tag',
      );
    });

    test('keeps a custom emoji fallback and its id aligned', () {
      final display = PanguSpacing.display('中文abc🙂', [
        const MessageTextEntity(
          offset: 5,
          length: 2,
          type: 'textEntityTypeCustomEmoji',
          customEmojiId: 5,
        ),
      ]);
      expect(display.text, '中文 abc🙂');
      expect(display.entities.single.offset, 6);
      expect(display.entities.single.length, 2);
      expect(display.entities.single.customEmojiId, 5);
    });

    test('carries url, language and button payloads across the shift', () {
      const source = MessageTextEntity(
        offset: 2,
        length: 4,
        type: 'textEntityTypePreCode',
        language: 'go',
        url: 'https://example.com',
        userId: 7,
        typeData: {'language': 'go'},
      );
      final display = PanguSpacing.display('中文code中文', [source]);
      final shifted = display.entities.single;
      expect(shifted.offset, 3);
      expect(shifted.length, 4);
      expect(shifted.language, 'go');
      expect(shifted.url, 'https://example.com');
      expect(shifted.userId, 7);
      expect(shifted.typeData, const {'language': 'go'});
    });

    test('returns the same lists when nothing changes', () {
      final entities = [entity(0, 2, 'textEntityTypeBold')];
      final display = PanguSpacing.display('中文', entities);
      expect(display.changed, isFalse);
      expect(identical(display.entities, entities), isTrue);
    });

    test('tolerates an entity that reaches past the text', () {
      final display = PanguSpacing.display('中文abc', [
        entity(2, 90, 'textEntityTypeUrl'),
      ]);
      expect(display.text, '中文 abc');
      expect(display.entities.single.offset, 3);
      expect(display.entities.single.length, 90);
    });

    test('leaves a plain CJK message untouched', () {
      final entities = [entity(0, 2, 'textEntityTypeBold')];
      final display = PanguSpacing.display('你好世界', entities);
      expect(display.changed, isFalse);
      expect(identical(display.entities, entities), isTrue);
    });
  });

  group('outgoing payload', () {
    test('spaces the text and moves the TDLib entities', () {
      final result = PanguSpacing.outgoing('中文code中文', [
        tdEntity(2, 4, 'textEntityTypeCode'),
      ]);
      expect(result.text, '中文 code 中文');
      expect(result.entities.single['offset'], 3);
      expect(result.entities.single['length'], 4);
      expect(
        result.text.substring(
          result.entities.single['offset'] as int,
          (result.entities.single['offset'] as int) +
              (result.entities.single['length'] as int),
        ),
        'code',
      );
    });

    test('spaces a caption with a mention entity', () {
      final result = PanguSpacing.outgoing('中文@alice英文', [
        tdEntity(2, 6, 'textEntityTypeMentionName'),
      ]);
      expect(result.text, '中文@alice 英文');
      expect(result.entities.single['offset'], 2);
      expect(result.entities.single['length'], 6);
    });

    test('keeps formatting entity payloads verbatim apart from offsets', () {
      final source = tdEntity(2, 7, 'textEntityTypeBold')..['extra'] = 1;
      final result = PanguSpacing.outgoing('中文English', [source]);
      expect(result.entities.single['offset'], 3);
      expect(result.entities.single['length'], 7);
      expect(result.entities.single['extra'], 1);
      expect(result.entities.single['type'], {'@type': 'textEntityTypeBold'});
      expect(identical(result.entities.single, source), isFalse);
    });

    test('returns the same list when nothing changes', () {
      final entities = [tdEntity(0, 2, 'textEntityTypeBold')];
      final result = PanguSpacing.outgoing('中文', entities);
      expect(result.text, '中文');
      expect(identical(result.entities, entities), isTrue);
    });

    test('ignores a malformed entity payload', () {
      final result = PanguSpacing.outgoing('中文abc', [
        {'@type': 'textEntity'},
        {'@type': 'textEntity', 'offset': 'x', 'length': 'y', 'type': null},
      ]);
      expect(result.text, '中文 abc');
      expect(result.entities, hasLength(2));
    });
  });

  group('reverse mapping', () {
    // 中文English中文 spaced is 中文 English 中文, inserted at source offsets 2, 9.
    const source = '中文English中文';
    final display = PanguSpacing.transformText(source);

    int sourceStart(int start) => PanguSpacing.reverseRange(
      start: start,
      end: display.text.length,
      insertedOffsets: display.insertedOffsets,
      sourceLength: source.length,
    ).start;

    int sourceEnd(int end) => PanguSpacing.reverseRange(
      start: 0,
      end: end,
      insertedOffsets: display.insertedOffsets,
      sourceLength: source.length,
    ).end;

    test('the spaced string is what the ranges address', () {
      expect(display.text, '中文 English 中文');
      expect(display.insertedOffsets, [2, 9]);
    });

    test('a full selection maps back to the whole source', () {
      expect(sourceStart(0), 0);
      expect(sourceEnd(display.text.length), source.length);
    });

    test('a word selection maps onto the same word', () {
      final start = display.text.indexOf('English');
      expect(sourceStart(start), source.indexOf('English'));
      expect(sourceEnd(start + 7), source.indexOf('English') + 7);
    });

    test('an inserted space at either edge stays out of the range', () {
      // "中文 " quotes 中文…
      expect(source.substring(sourceStart(0), sourceEnd(3)), '中文');
      // …and " English" quotes English.
      expect(source.substring(sourceStart(2), sourceEnd(10)), 'English');
    });

    test('selecting only an inserted space maps to an empty range', () {
      final mapped = PanguSpacing.reverseRange(
        start: 2,
        end: 3,
        insertedOffsets: display.insertedOffsets,
        sourceLength: source.length,
      );
      expect(mapped.start, mapped.end);
    });

    test('no insertions is the identity', () {
      final mapped = PanguSpacing.reverseRange(
        start: 1,
        end: 4,
        insertedOffsets: const [],
        sourceLength: source.length,
      );
      expect(mapped, (start: 1, end: 4));
    });

    test('out-of-range input is clamped, never thrown', () {
      final mapped = PanguSpacing.reverseRange(
        start: -5,
        end: 999,
        insertedOffsets: display.insertedOffsets,
        sourceLength: source.length,
      );
      expect(mapped.start, 0);
      expect(mapped.end, source.length);
    });
  });

  group('memo', () {
    test('reuses one result for repeated builds', () {
      final memo = PanguDisplayMemo();
      final entities = [entity(2, 7, 'textEntityTypeBold')];
      final first = memo.resolve('中文English', entities);
      final second = memo.resolve('中文English', entities);
      expect(identical(first, second), isTrue);
      expect(identical(first.entities, second.entities), isTrue);
    });

    test('rebuilds when the entity list is a different one', () {
      final memo = PanguDisplayMemo();
      final first = memo.resolve('中文English', [
        entity(2, 7, 'textEntityTypeBold'),
      ]);
      final second = memo.resolve('中文English', [
        entity(2, 7, 'textEntityTypeBold'),
      ]);
      expect(identical(first, second), isFalse);
      expect(second.text, first.text);
    });

    test('keeps several texts of one bubble apart', () {
      final memo = PanguDisplayMemo();
      final captionEntities = [entity(0, 2, 'textEntityTypeBold')];
      final quoteEntities = [entity(0, 4, 'textEntityTypeItalic')];
      final caption = memo.resolve('中文abc', captionEntities);
      final quote = memo.resolve('引用quote', quoteEntities);
      expect(
        identical(memo.resolve('中文abc', captionEntities), caption),
        isTrue,
      );
      expect(identical(memo.resolve('引用quote', quoteEntities), quote), isTrue);
    });

    test('clear drops every entry', () {
      final memo = PanguDisplayMemo();
      final entities = [entity(2, 7, 'textEntityTypeBold')];
      final first = memo.resolve('中文English', entities);
      memo.clear();
      expect(identical(memo.resolve('中文English', entities), first), isFalse);
    });
  });

  group('detected tokens', () {
    List<String> spans(String text) => [
      for (final range in PanguSpacing.detectedRangesFor(text))
        text.substring(range.start, range.end),
    ];

    test('claims a link whose path mixes scripts', () {
      expect(
        spans('看https://example.com/中文abc'),
        contains('https://example.com/中文abc'),
      );
      expect(spans('example.com/中文abc'), contains('example.com/中文abc'));
    });

    test('claims a mention, a hashtag and an address', () {
      final found = spans('@user #中文tag 寄到mail@example.com');
      expect(found, containsAll(<String>['@user', '#中文tag']));
      expect(found, contains('mail@example.com'));
    });

    test('a mention stops where its username does', () {
      // Telegram usernames are ASCII, so the CJK after one is ordinary text and
      // still gets its space.
      expect(spans('中文@username中文'), contains('@username'));
    });

    test('a command stops at its name', () {
      expect(spans('/help中文'), contains('/help'));
    });

    test('gives back the sentence punctuation a link picks up', () {
      expect(
        spans('https://example.com/a. 然后'),
        contains('https://example.com/a'),
      );
    });

    test('leaves ordinary text alone', () {
      // A full stop between two CJK clauses is not a domain, and a version
      // number is not one either.
      expect(spans('今天用iPhone很开心.明天继续'), isEmpty);
      expect(spans('版本1.2.3发布'), isEmpty);
      expect(spans('没有链接'), isEmpty);
      expect(spans(''), isEmpty);
    });
  });
}
