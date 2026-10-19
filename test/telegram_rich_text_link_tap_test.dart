import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/telegram_rich_text.dart';
import 'package:mithka/tdlib/td_models.dart';

Iterable<TextSpan> _textSpans(InlineSpan span) sync* {
  if (span is! TextSpan) return;
  yield span;
  for (final child in span.children ?? const <InlineSpan>[]) {
    yield* _textSpans(child);
  }
}

void main() {
  const username = '@duck_user';
  const mention = MessageTextEntity(
    offset: 0,
    length: 10,
    type: 'textEntityTypeMention',
  );
  Future<void> pumpUsername(
    WidgetTester tester,
    ValueChanged<String>? callback, {
    bool quoted = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TelegramRichText(
          key: const ValueKey('username-cache'),
          text: username,
          entities: quoted
              ? const [
                  mention,
                  MessageTextEntity(
                    offset: 0,
                    length: 10,
                    type: 'textEntityTypeBlockQuote',
                  ),
                ]
              : const [mention],
          onUsernameTap: callback,
          quoteBackgroundColor: quoted ? const Color(0xFFE0E0E0) : null,
        ),
      ),
    ),
  );
  Future<void> tapUsername(WidgetTester tester) async {
    final finder = find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText() == username,
    );
    final paragraph = tester.renderObject<RenderParagraph>(finder);
    final box = paragraph
        .getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 10),
        )
        .first
        .toRect();
    await tester.tapAt(paragraph.localToGlobal(box.center));
  }

  testWidgets('typed mention cache uses the current callback after rebuilds', (
    tester,
  ) async {
    final calls = <String>[];
    await pumpUsername(tester, null);
    await pumpUsername(tester, (name) => calls.add('first:$name'));
    await tapUsername(tester);
    await pumpUsername(tester, (name) => calls.add('second:$name'));
    await tapUsername(tester);
    expect(calls, ['first:duck_user', 'second:duck_user']);
  });

  testWidgets('quoted typed mention forwards its username callback', (
    tester,
  ) async {
    final calls = <String>[];
    await pumpUsername(tester, calls.add, quoted: true);
    await tapUsername(tester);
    expect(calls, ['duck_user']);
  });

  // The bio loads after the page mounts: an empty bio renders first, the
  // fetched full info replaces it in place. Every frame in between must leave
  // the link's recognizer attached.
  testWidgets('link stays tappable across the empty-to-loaded bio swap', (
    tester,
  ) async {
    const bio = 'read https://t.me/mithka first';
    // This probe verifies recognizer attachment. Production tap routing is
    // exercised separately with a recording TDLib proxy.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TelegramRichText(key: ValueKey('bio'), text: ''),
              SizedBox.shrink(),
            ],
          ),
        ),
      ),
    );

    // Swap in the loaded bio the way the profile page does.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TelegramRichText(key: ValueKey('bio'), text: bio),
              SizedBox.shrink(),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final richText = tester.widget<RichText>(find.byType(RichText).first);
    final spans = _textSpans(richText.text).toList();
    final linkSpan = spans
        .where((s) => s.text == 'https://t.me/mithka')
        .toList();
    expect(linkSpan, isNotEmpty, reason: 'bio link span must exist after load');
    expect(
      linkSpan.single.recognizer,
      isA<TapGestureRecognizer>(),
      reason: 'the visible bio link must carry its tap recognizer',
    );
  });

  testWidgets('link recognizer survives repeated rebuilds with same text', (
    tester,
  ) async {
    const bio = 'read https://t.me/mithka first';

    Widget host() => const MaterialApp(
      home: Scaffold(
        body: TelegramRichText(key: ValueKey('bio'), text: bio),
      ),
    );

    await tester.pumpWidget(host());
    await tester.pumpWidget(host());
    await tester.pumpWidget(host());
    await tester.pump();

    final richText = tester.widget<RichText>(find.byType(RichText).first);
    final linkSpan = _textSpans(
      richText.text,
    ).where((s) => s.text == 'https://t.me/mithka').toList();
    expect(linkSpan, isNotEmpty);
    expect(
      linkSpan.single.recognizer,
      isA<TapGestureRecognizer>(),
      reason: 'memoized spans keep the same recognizer; it must stay attached',
    );
  });

  testWidgets(
    'mention span resolves even when TDLib entity arrives with a pangu-shifted text',
    (tester) async {
      // Pangu inserts spaces for CJK-latin boundaries. Entities shift onto the
      // spaced text; if they shifted wrong, the span would cover the wrong
      // characters and the visible link would not carry the recognizer.
      const bio = '看 https://t.me/mithka 看看';
      const entities = [
        MessageTextEntity(offset: 2, length: 19, type: 'textEntityTypeUrl'),
      ];
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TelegramRichText(text: bio, entities: entities),
          ),
        ),
      );

      final richText = tester.widget<RichText>(find.byType(RichText).first);
      final spans = _textSpans(richText.text).toList();
      final linkSpans = spans
          .where((s) => (s.text ?? '').contains('t.me/mithka'))
          .toList();
      for (final span in linkSpans) {
        expect(
          span.recognizer,
          isA<TapGestureRecognizer>(),
          reason: 'every visible piece of the link must stay tappable',
        );
      }
      expect(linkSpans, isNotEmpty);
    },
  );
}
