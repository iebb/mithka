//
//  app_root_text_style_test.dart
//
//  A window's screens bring no text style of their own. A row that sets only
//  its size and colour — the desktop search window's message preview and date
//  — must draw at the app's regular weight, not Flutter's unstyled weight 900.
//

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/app_root_text_style.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ThemeController theme;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    theme = ThemeController(await SharedPreferences.getInstance());
  });
  tearDown(() => theme.dispose());

  TextStyle drawnStyle(WidgetTester tester, String text) => tester
      .widget<RichText>(
        find.descendant(of: find.text(text), matching: find.byType(RichText)),
      )
      .text
      .style!;

  Widget window({required bool rooted, required Widget home}) => MaterialApp(
    theme: ThemeData(extensions: [AppColors.light]),
    builder: (context, child) =>
        rooted ? AppRootTextStyle(theme: theme, child: child) : child!,
    home: home,
  );

  const preview = CupertinoPageScaffold(
    child: Text('preview', style: TextStyle(fontSize: 13)),
  );

  testWidgets('a row that omits its weight draws regular under the root', (
    tester,
  ) async {
    await tester.pumpWidget(window(rooted: false, home: preview));
    expect(
      drawnStyle(tester, 'preview').fontWeight,
      FontWeight.w900,
      reason: 'the unstyled fallback this root exists to replace',
    );

    await tester.pumpWidget(window(rooted: true, home: preview));
    final style = drawnStyle(tester, 'preview');
    expect(style.fontWeight, AppTextWeight.regular);
    expect(style.decoration, TextDecoration.none);
    expect(style.fontSize, 13);
    expect(style.color, AppColors.light.textPrimary);
  });

  testWidgets('a pushed route sits under the same root', (tester) async {
    await tester.pumpWidget(
      window(
        rooted: true,
        home: Builder(
          builder: (context) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    const CupertinoPageScaffold(child: Text('pushed')),
              ),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(100, 100));
    await tester.pumpAndSettle();

    final style = drawnStyle(tester, 'pushed');
    expect(style.fontWeight, AppTextWeight.regular);
    expect(style.fontSize, AppTextSize.body);
  });
}
