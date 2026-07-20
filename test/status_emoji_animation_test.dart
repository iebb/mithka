import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/custom_emoji.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('status emoji animation defaults on and persists its opt-out', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);

    expect(theme.animateStatusEmoji, isTrue);
    theme.animateStatusEmoji = false;
    expect(theme.animateStatusEmoji, isFalse);
    expect(ThemeController(prefs).animateStatusEmoji, isFalse);
  });

  test('disabled animated status emoji prefer static thumbnails', () {
    final thumbnail = TdFileRef(id: 2);

    for (final sticker in [
      CustomEmojiSticker(file: TdFileRef(id: 1), thumb: thumbnail, isTgs: true),
      CustomEmojiSticker(
        file: TdFileRef(id: 1),
        thumb: thumbnail,
        isWebm: true,
      ),
    ]) {
      expect(
        customEmojiPresentation(sticker, animate: false),
        CustomEmojiPresentation.staticThumbnail,
      );
    }
  });

  testWidgets('status surfaces follow the animation preference', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'animateStatusEmoji': false});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: theme,
        child: const MaterialApp(home: StatusEmojiView(id: 0)),
      ),
    );

    expect(
      tester.widget<CustomEmojiView>(find.byType(CustomEmojiView)).animate,
      isFalse,
    );

    theme.animateStatusEmoji = true;
    await tester.pump();
    expect(
      tester.widget<CustomEmojiView>(find.byType(CustomEmojiView)).animate,
      isTrue,
    );
  });
}
