import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/emoji_store.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/settings/quick_reaction_settings_view.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('selected quick reactions remain visible above the picker', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    EmojiStore.shared.reset();
    final theme = ThemeController(preferences);
    addTearDown(EmojiStore.shared.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: theme,
        child: MaterialApp(
          theme: ThemeData(extensions: [AppColors.dark]),
          home: const QuickReactionSettingsView(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('👍'), findsNWidgets(2));
    expect(find.byType(SettingsSectionHeader), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
