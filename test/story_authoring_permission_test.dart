import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/moments/story_authoring_view.dart';
import 'package:mithka/moments/story_camera_view.dart';
import 'package:mithka/moments/story_service.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('publish controls stay hidden when stories are not permitted', (
    tester,
  ) async {
    await _pumpAuthoring(tester, canPost: false);

    expect(find.byKey(const ValueKey('story-publish-dock')), findsNothing);
    expect(find.text('下一步'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('eligible accounts can advance to story publishing', (
    tester,
  ) async {
    await _pumpAuthoring(tester, canPost: true);

    expect(find.byKey(const ValueKey('story-publish-dock')), findsOneWidget);
    expect(find.text('下一步'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('camera opens only after the user selects it', (tester) async {
    await _pumpAuthoring(tester, canPost: true, initialMediaPath: null);

    expect(find.text('选择照片或视频'), findsOneWidget);
    expect(find.byType(StoryCameraView), findsNothing);

    await tester.tap(find.text('相机'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(StoryCameraView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpAuthoring(
  WidgetTester tester, {
  required bool canPost,
  String? initialMediaPath = '/tmp/story-permission-test.mp4',
}) async {
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
        home: StoryAuthoringView(
          initialMediaPath: initialMediaPath,
          service: _PermissionStoryService(allowed: canPost),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _PermissionStoryService extends StoryService {
  _PermissionStoryService({required this.allowed})
    : super(query: (_) async => {'@type': 'ok'});

  final bool allowed;

  @override
  Future<bool> isPremium() async => false;

  @override
  Future<int> savedMessagesChatId() async => 10;

  @override
  Future<List<int>> chatsToPost() async => const [];

  @override
  Future<Map<String, dynamic>> canPost(int chatId) async => {
    '@type': allowed
        ? 'canPostStoryResultOk'
        : 'canPostStoryResultPremiumNeeded',
  };

  @override
  Future<Map<String, dynamic>> albums(int chatId) async => {
    '@type': 'storyAlbums',
    'albums': const [],
  };
}
