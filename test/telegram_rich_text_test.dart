import 'package:flutter/material.dart';
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
  testWidgets('links are colored without adding an underline', (tester) async {
    const text = 'site https://example.com manual';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TelegramRichText(
            text: text,
            entities: [
              MessageTextEntity(
                offset: 0,
                length: 4,
                type: 'textEntityTypeTextUrl',
                url: 'https://example.com/site',
              ),
              MessageTextEntity(
                offset: 25,
                length: 6,
                type: 'textEntityTypeUnderline',
              ),
            ],
          ),
        ),
      ),
    );

    final richText = tester.widget<RichText>(find.byType(RichText));
    final spans = _textSpans(richText.text).toList();
    final entityLink = spans.singleWhere((span) => span.text == 'site');
    final autoLink = spans.singleWhere(
      (span) => span.text == 'https://example.com',
    );
    final explicitUnderline = spans.singleWhere(
      (span) => span.text == 'manual',
    );

    expect(entityLink.style?.decoration, isNot(TextDecoration.underline));
    expect(autoLink.style?.decoration, isNot(TextDecoration.underline));
    expect(explicitUnderline.style?.decoration, TextDecoration.underline);
  });
}
