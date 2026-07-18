import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/bot_button_presentation.dart';
import 'package:mithka/chat/custom_emoji.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  test('button palettes preserve Telegram semantic styles', () {
    const standard = (
      background: Color(0xFFFFFFFF),
      foreground: Color(0xFF111111),
      border: Color(0xFFCCCCCC),
    );

    final unchanged = botButtonPalette(
      MessageButtonStyle.standard,
      standard: standard,
      primary: const Color(0xFF007AFF),
    );
    final danger = botButtonPalette(
      MessageButtonStyle.danger,
      standard: standard,
      primary: const Color(0xFF007AFF),
    );
    final success = botButtonPalette(
      MessageButtonStyle.success,
      standard: standard,
      primary: const Color(0xFF007AFF),
    );

    expect(unchanged, standard);
    expect(danger.background, const Color(0xFFE25555));
    expect(danger.foreground, Colors.white);
    expect(success.background, const Color(0xFF2FAF69));
    expect(success.foreground, Colors.white);
  });

  testWidgets('button label renders Telegram custom emoji before its text', (
    tester,
  ) async {
    CustomEmojiCenter.shared.reset();
    addTearDown(CustomEmojiCenter.shared.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            child: BotButtonLabel(
              button: MessageButton(
                text: 'Continue',
                type: 'keyboardButtonTypeText',
                style: MessageButtonStyle.success,
                iconCustomEmojiId: 7766,
              ),
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(CustomEmojiView), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    final row = tester.widget<Row>(find.byType(Row));
    expect(row.children.first, isA<CustomEmojiView>());
  });
}
