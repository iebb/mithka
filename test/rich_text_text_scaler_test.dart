import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/telegram_rich_text.dart';
import 'package:mithka/components/ui_components.dart';

Widget _withScaler(double scale, Widget child) => MediaQuery(
  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: child),
  ),
);

void main() {
  testWidgets('TelegramRichText honours the ambient text scaler', (
    tester,
  ) async {
    await tester.pumpWidget(
      _withScaler(1.5, const TelegramRichText(text: 'hello')),
    );

    final richText = tester.widget<RichText>(find.byType(RichText));
    expect(richText.textScaler.scale(16), 24);
  });

  testWidgets('ChatPreviewText honours the ambient text scaler', (
    tester,
  ) async {
    await tester.pumpWidget(
      _withScaler(2.0, const ChatPreviewText(message: 'hello')),
    );

    final richText = tester.widget<RichText>(find.byType(RichText));
    expect(richText.textScaler.scale(16), 32);
  });
}
