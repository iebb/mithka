import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/custom_emoji.dart';
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

  testWidgets('custom emoji stays hidden until its spoiler is revealed', (
    tester,
  ) async {
    const text = '🙂';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TelegramRichText(
            text: text,
            entities: [
              MessageTextEntity(
                offset: 0,
                length: 2,
                type: 'textEntityTypeSpoiler',
              ),
              MessageTextEntity(
                offset: 0,
                length: 2,
                type: 'textEntityTypeCustomEmoji',
                customEmojiId: 123,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(CustomEmojiView), findsNothing);
    final richText = tester.widget<RichText>(find.byType(RichText));
    final spoiler = _textSpans(
      richText.text,
    ).singleWhere((span) => span.text == text);
    (spoiler.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pump();

    expect(find.byType(CustomEmojiView), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('selection copies a custom emoji fallback as message text', (
    tester,
  ) async {
    const text = 'A🙂B';
    final selectionKey = GlobalKey<SelectionAreaState>();
    String? selectedText;
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            key: selectionKey,
            onSelectionChanged: (content) {
              selectedText = content?.plainText;
            },
            child: const TelegramRichText(
              text: text,
              entities: [
                MessageTextEntity(
                  offset: 1,
                  length: 2,
                  type: 'textEntityTypeCustomEmoji',
                  customEmojiId: 456,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    selectionKey.currentState!.selectableRegion.selectAll(
      SelectionChangedCause.keyboard,
    );
    await tester.pump();
    expect(selectedText, text);

    Actions.invoke(
      tester.element(find.byType(TelegramRichText)),
      CopySelectionTextIntent.copy,
    );
    await tester.pump();
    expect(copiedText, text);
    await tester.pump(const Duration(milliseconds: 50));
  });
}
