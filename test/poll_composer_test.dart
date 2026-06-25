import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/poll_composer_view.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'PollComposerView renders QQ-style composer (no Material dialog)',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      (String, List<String>)? result;
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => ThemeController(prefs),
          child: MaterialApp(
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(context)
                      .push<(String, List<String>)>(
                        MaterialPageRoute(
                          builder: (_) => const PollComposerView(),
                        ),
                      );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Full-page composer, not an AlertDialog.
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('发起投票'), findsOneWidget);
      expect(find.text('发送'), findsOneWidget);
      expect(find.text('添加选项'), findsOneWidget);
      expect(find.text('选项 1'), findsOneWidget);
      expect(find.text('选项 2'), findsOneWidget);

      // Add an option → a third row appears.
      await tester.tap(find.text('添加选项'));
      await tester.pumpAndSettle();
      expect(find.text('选项 3'), findsOneWidget);

      // Fill question + two options, send returns (question, options).
      await tester.enterText(find.byType(TextField).at(0), '晚饭吃什么');
      await tester.enterText(find.byType(TextField).at(1), '火锅');
      await tester.enterText(find.byType(TextField).at(2), '烧烤');
      await tester.pumpAndSettle();
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.$1, '晚饭吃什么');
      expect(result!.$2, ['火锅', '烧烤']);
    },
  );
}
