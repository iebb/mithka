import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/moments/story_management_view.dart';
import 'package:mithka/moments/story_service.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('story manager is a localized media grid, not settings rows', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1170, 2532);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);

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
          home: StoryManagementView(chatId: 10, service: _FakeStoryService()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('我的故事'), findsOneWidget);
    expect(find.text('活跃'), findsOneWidget);
    expect(find.text('归档'), findsOneWidget);
    expect(find.text('3 条活跃故事'), findsOneWidget);
    expect(find.byKey(const ValueKey('story-card-31')), findsOneWidget);
    expect(find.byKey(const ValueKey('story-card-32')), findsOneWidget);
    expect(find.byKey(const ValueKey('story-card-33')), findsOneWidget);
    expect(find.byKey(const ValueKey('story-album-7')), findsOneWidget);
    expect(find.byType(SettingsCard), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('归档'));
    await tester.pumpAndSettle();

    expect(find.text('已归档 1 个'), findsOneWidget);
    expect(find.byKey(const ValueKey('story-card-21')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeStoryService extends StoryService {
  _FakeStoryService() : super(query: (_) async => {'@type': 'ok'});

  static Map<String, dynamic> story(
    int id, {
    required String caption,
    bool video = false,
  }) => {
    '@type': 'story',
    'id': id,
    'date': DateTime(2026, 7, 18, 8).millisecondsSinceEpoch ~/ 1000,
    'expiration_date':
        DateTime.now().add(const Duration(hours: 9)).millisecondsSinceEpoch ~/
        1000,
    'caption': {
      '@type': 'formattedText',
      'text': caption,
      'entities': const [],
    },
    'content': video
        ? {
            '@type': 'storyContentVideo',
            'video': {
              '@type': 'storyVideo',
              'minithumbnail': null,
              'thumbnail': null,
            },
          }
        : {
            '@type': 'storyContentPhoto',
            'photo': {
              '@type': 'photo',
              'minithumbnail': null,
              'sizes': const [],
            },
          },
    'interaction_info': {'@type': 'storyInteractionInfo', 'view_count': id},
    'can_be_edited': true,
    'can_be_deleted': true,
  };

  @override
  Future<StoryCollectionResult> loadStoryCollection(
    int chatId, {
    required bool archived,
    int pageLimit = 100,
    int maximumPages = 100,
  }) async => archived
      ? StoryCollectionResult(
          stories: [story(21, caption: '夏日回忆')],
          pinnedStoryIds: const [],
        )
      : StoryCollectionResult(
          stories: [
            story(31, caption: '东京夜色'),
            story(32, caption: '海边', video: true),
            story(33, caption: ''),
          ],
          pinnedStoryIds: const [31],
        );

  @override
  Future<Map<String, dynamic>> albums(int chatId) async => {
    '@type': 'storyAlbums',
    'albums': [
      {'@type': 'storyAlbum', 'id': 7, 'name': '夏天'},
    ],
  };

  @override
  Future<Map<String, dynamic>> albumStories(
    int chatId,
    int albumId, {
    int offset = 0,
    int limit = 100,
  }) async => {
    '@type': 'stories',
    'stories': [story(31, caption: '东京夜色')],
  };
}
