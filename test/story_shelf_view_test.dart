import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/moments/moments_view.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Moments shows a compact localized story rail', (tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1170, 2532);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    final model = MomentsViewModel()
      ..selfName = 'Natu'
      ..groups = [
        StoryGroup(
          chatId: 11,
          name: 'Alice',
          storyIds: const [3, 4],
          hasUnread: true,
          order: 30,
          date: 30,
        ),
        StoryGroup(
          chatId: 12,
          name: '小林',
          storyIds: const [8],
          hasUnread: true,
          order: 20,
          date: 20,
        ),
        StoryGroup(
          chatId: 13,
          name: 'Charlie',
          storyIds: const [9],
          hasUnread: false,
          order: 10,
          date: 10,
        ),
      ];
    addTearDown(model.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          locale: const Locale.fromSubtags(
            languageCode: 'zh',
            scriptCode: 'Hans',
          ),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(
            brightness: Brightness.light,
            extensions: [AppColors.light],
          ),
          home: Material(
            color: AppColors.light.groupedBackground,
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                height: 135,
                child: RepaintBoundary(
                  key: const ValueKey('storyShelfGolden'),
                  child: IgnorePointer(
                    child: StoryShelf(
                      model: model,
                      canPublish: true,
                      onCreate: () {},
                      onManage: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('故事'), findsOneWidget);
    expect(find.text('我的故事'), findsOneWidget);
    expect(find.text('发布故事'), findsNothing);
    expect(find.text('查看全部'), findsNothing);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('小林'), findsOneWidget);
    expect(find.text('Charlie'), findsOneWidget);
    expect(
      tester.getCenter(find.text('我的故事')).dx,
      lessThan(tester.getCenter(find.text('Alice')).dx),
    );
    expect(
      tester.getSize(find.byType(StoryShelf)).height,
      lessThanOrEqualTo(140),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('My Story and its add badge have separate destinations', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    final model = MomentsViewModel()..selfName = 'Natu';
    addTearDown(theme.dispose);
    addTearDown(model.dispose);
    var createCount = 0;
    var manageCount = 0;

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(extensions: [AppColors.light]),
          home: Material(
            child: StoryShelf(
              model: model,
              canPublish: true,
              onCreate: () => createCount++,
              onManage: () => manageCount++,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('story-create-badge')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('my-story-action')));
    await tester.pump();
    expect(manageCount, 1);
    expect(createCount, 0);

    await tester.tap(find.byKey(const ValueKey('story-create-badge')));
    await tester.pump();
    expect(manageCount, 1);
    expect(createCount, 1);

    model.ownGroup = StoryGroup(
      chatId: 10,
      name: 'Natu',
      storyIds: const [7],
      hasUnread: false,
      order: 1,
      date: 1,
    );
    model.notifyListeners();
    await tester.pump();

    expect(find.byKey(const ValueKey('story-create-badge')), findsOneWidget);
  });
}
