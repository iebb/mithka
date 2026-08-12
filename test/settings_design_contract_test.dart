import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('all settings destinations reuse the shared page skeleton', () {
    const externalSettingsSurfaces = [
      'lib/chat/chat_theme_view.dart',
      'lib/chat/chat_wallpaper_color_view.dart',
      'lib/chat/chat_wallpaper_search_view.dart',
      'lib/chat/chat_wallpaper_view.dart',
      'lib/chat/global_chat_theme_view.dart',
      'lib/theme/global_theme_view.dart',
      'lib/theme/telegram_cloud_theme_view.dart',
    ];
    final files = <File>[
      ...Directory('lib/settings').listSync().whereType<File>().where(
        (file) => file.path.endsWith('_view.dart'),
      ),
      File('lib/security/local_app_lock_views.dart'),
      File('lib/pro/mithka_pro_view.dart'),
      for (final path in externalSettingsSurfaces) File(path),
    ];

    final rawScaffolds = <String, int>{};
    final directHeaders = <String>[];
    final detailIconTiles = <String>[];
    final builtInIcons = <String>[];
    for (final file in files) {
      final source = file.readAsStringSync();
      final relative = _relativePath(file);
      final scaffoldCount = RegExp(
        r'\breturn\s+Scaffold\(',
      ).allMatches(source).length;
      if (scaffoldCount > 0) rawScaffolds[relative] = scaffoldCount;
      if (RegExp(r'\bNavHeader\(').hasMatch(source)) {
        directHeaders.add(relative);
      }
      if (relative != 'lib/settings/settings_view.dart' &&
          RegExp(r'\bSettingsIconTile\(').hasMatch(source)) {
        detailIconTiles.add(relative);
      }
      if (RegExp(r'\b(?:Icons|CupertinoIcons)\.').hasMatch(source)) {
        builtInIcons.add(relative);
      }
    }

    expect(
      rawScaffolds,
      {'lib/settings/settings_view.dart': 1},
      reason:
          'Only the adaptive split container owns a raw Scaffold; every '
          'destination must use SettingsPageScaffold.',
    );
    expect(directHeaders, isEmpty);
    expect(detailIconTiles, isEmpty);
    expect(builtInIcons, isEmpty);

    for (final file in files) {
      final path = _relativePath(file);
      expect(
        file.readAsStringSync(),
        contains('SettingsPageScaffold('),
        reason: '$path must build destinations through the shared skeleton',
      );
    }
  });

  testWidgets('mobile and desktop use the same settings outer padding', (
    tester,
  ) async {
    Future<EdgeInsetsGeometry?> paddingFor(TargetPlatform platform) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(
        const MaterialApp(
          home: SettingsListView(children: [SizedBox(height: 1)]),
        ),
      );
      return tester.widget<ListView>(find.byType(ListView)).padding;
    }

    try {
      expect(await paddingFor(TargetPlatform.iOS), AppInsets.screen);
      expect(await paddingFor(TargetPlatform.macOS), AppInsets.screen);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('grouped cards own canonical divider alignment', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        home: const SettingsCard.rows(
          rows: [
            SettingsRow(title: 'First', showChevron: false),
            SettingsRow(title: 'Second', showChevron: false),
          ],
        ),
      ),
    );

    final divider = tester.widget<InsetDivider>(find.byType(InsetDivider));
    expect(divider.leadingInset, AppMetric.settingsIconDividerInset);
  });

  testWidgets('split root ignores the Settings window outer history', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          theme: ThemeData(extensions: [AppColors.light]),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SettingsSplitPaneScope(
                    child: SettingsPageScaffold(
                      title: 'Detail',
                      child: SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppIcon && widget.icon == HeroAppIcons.chevronLeft,
      ),
      findsNothing,
    );
  });

  testWidgets('shared settings search clears state as well as its controller', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final changes = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        home: Scaffold(
          body: SettingsSearchField(
            hintText: 'Search',
            controller: controller,
            onChanged: changes.add,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'theme');
    await tester.pump();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.icon == HeroAppIcons.xmark,
      ),
    );
    await tester.pump();

    expect(controller.text, isEmpty);
    expect(changes.last, isEmpty);
  });
}

String _relativePath(File file) {
  final prefix = '${Directory.current.path}${Platform.pathSeparator}';
  return file.absolute.path.replaceFirst(prefix, '');
}
