import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/data_storage_service.dart';
import 'package:mithka/settings/storage_usage_view.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('normalizes TDLib fast and detailed storage reports', () {
    final snapshot = StorageSnapshot.fromTd(
      fast: const {
        '@type': 'storageStatisticsFast',
        'files_size': 1000,
        'file_count': 4,
        'database_size': 300,
        'language_pack_database_size': 100,
        'log_size': 50,
      },
      detailed: <String, dynamic>{
        '@type': 'storageStatistics',
        'size': 1000,
        'count': 4,
        'by_file_type': <Map<String, dynamic>>[
          <String, dynamic>{
            '@type': 'storageStatisticsByFileType',
            'file_type': <String, dynamic>{'@type': 'fileTypePhoto'},
            'size': 700,
            'count': 2,
          },
          <String, dynamic>{
            '@type': 'storageStatisticsByFileType',
            'file_type': <String, dynamic>{'@type': 'fileTypeVideo'},
            'size': 300,
            'count': 2,
          },
        ],
        'by_chat': <Map<String, dynamic>>[
          <String, dynamic>{
            '@type': 'storageStatisticsByChat',
            'chat_id': 7,
            'size': 1000,
            'count': 4,
            'by_file_type': <Map<String, dynamic>>[
              <String, dynamic>{
                '@type': 'storageStatisticsByFileType',
                'file_type': <String, dynamic>{'@type': 'fileTypePhoto'},
                'size': 700,
                'count': 2,
              },
            ],
          },
        ],
      },
    );

    expect(snapshot.cacheSize, 1000);
    expect(snapshot.otherManagedSize, 450);
    expect(snapshot.managedTotal, 1450);
    expect(snapshot.fileCount, 4);
    expect(snapshot.chats, hasLength(1));
    expect(snapshot.chats.single.chatId, 7);
  });

  testWidgets('desktop dashboard opens two-pane selectable manager', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({});
    final service = _FakeDataStorageService();
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);
    tester.view.physicalSize = const Size(1100, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: _testApp(StorageUsageView(service: service)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('storage-dashboard')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('storage-chats-files-card')),
      findsOneWidget,
    );
    expect(find.text('1.50 KB'), findsWidgets);

    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('storage-desktop-filters')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('storage-chat-7')), findsOneWidget);
    expect(find.text('Example chat'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('storage-chat-7')));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('explicit cache clearing confirms and uses optimizeStorage', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final service = _FakeDataStorageService();
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: _testApp(StorageUsageView(service: service)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clear cache'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Cached media will download again when needed. Messages, chat history, and account data will not be deleted.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Clear cache').last);
    await tester.pumpAndSettle();

    expect(service.optimizeCalls, hasLength(1));
    expect(service.optimizeCalls.single['size'], 0);
    expect(service.optimizeCalls.single['ttl'], 0);
    expect(service.optimizeCalls.single['immunity_delay'], 0);
    expect(service.optimizeCalls.single['file_types'], [
      {'@type': 'fileTypePhoto'},
      {'@type': 'fileTypeVideo'},
    ]);
    expect(service.optimizeCalls.single, isNot(contains('@type')));
  });
}

Widget _testApp(Widget home) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData(extensions: [AppColors.light]),
  home: home,
);

class _FakeDataStorageService extends DataStorageService {
  final List<Map<String, dynamic>> optimizeCalls = [];

  @override
  Future<Map<String, dynamic>> fastStorageStatistics() async => const {
    '@type': 'storageStatisticsFast',
    'files_size': 1536,
    'file_count': 3,
    'database_size': 512,
    'language_pack_database_size': 128,
    'log_size': 64,
  };

  @override
  Future<Map<String, dynamic>> storageStatistics({int chatLimit = 100}) async =>
      <String, dynamic>{
        '@type': 'storageStatistics',
        'size': 1536,
        'count': 3,
        'by_file_type': <Map<String, dynamic>>[
          <String, dynamic>{
            '@type': 'storageStatisticsByFileType',
            'file_type': <String, dynamic>{'@type': 'fileTypePhoto'},
            'size': 1024,
            'count': 2,
          },
          <String, dynamic>{
            '@type': 'storageStatisticsByFileType',
            'file_type': <String, dynamic>{'@type': 'fileTypeVideo'},
            'size': 512,
            'count': 1,
          },
        ],
        'by_chat': <Map<String, dynamic>>[
          <String, dynamic>{
            '@type': 'storageStatisticsByChat',
            'chat_id': 7,
            'size': 1536,
            'count': 3,
            'by_file_type': <Map<String, dynamic>>[
              <String, dynamic>{
                '@type': 'storageStatisticsByFileType',
                'file_type': <String, dynamic>{'@type': 'fileTypePhoto'},
                'size': 1024,
                'count': 2,
              },
              <String, dynamic>{
                '@type': 'storageStatisticsByFileType',
                'file_type': <String, dynamic>{'@type': 'fileTypeVideo'},
                'size': 512,
                'count': 1,
              },
            ],
          },
        ],
      };

  @override
  Future<Map<String, dynamic>> chat(int chatId) async => {
    '@type': 'chat',
    'id': chatId,
    'title': 'Example chat',
  };

  @override
  Future<Map<String, dynamic>> optimize({
    required int size,
    required int ttl,
    List<Map<String, dynamic>> fileTypes = const [],
    List<int> chatIds = const [],
    List<int> excludeChatIds = const [],
    bool returnDeletedStatistics = false,
    int count = 1000000000,
    int immunityDelay = 3600,
    int chatLimit = 100,
  }) async {
    optimizeCalls.add({
      'size': size,
      'ttl': ttl,
      'count': count,
      'immunity_delay': immunityDelay,
      'file_types': fileTypes,
      'chat_ids': chatIds,
      'exclude_chat_ids': excludeChatIds,
      'return_deleted_file_statistics': returnDeletedStatistics,
      'chat_limit': chatLimit,
    });
    return const {'@type': 'storageStatistics'};
  }
}
