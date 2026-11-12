import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/file_detail_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/data_storage_service.dart';
import 'package:mithka/settings/downloads_view.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _slot = 7;
late ThemeController _theme;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late StreamController<Map<String, dynamic>> updates;
  late _Backend backend;

  setUpAll(() {
    updates = StreamController<Map<String, dynamic>>.broadcast(sync: true);
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: _slot,
        query: (request) => backend.query(request),
        send: (request) async => backend.requests.add(request),
        updates: updates.stream,
      ),
    );
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(_theme.dispose);
    backend = _Backend();
  });
  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  test(
    'explicit downloads register message context on the owning account',
    () async {
      await DataStorageService(
        TdClient.shared,
        _slot,
      ).addDownload(fileId: 501, chatId: 101, messageId: 1);
      expect(backend.requests.single, {
        '@type': 'addFileToDownloads',
        'file_id': 501,
        'chat_id': 101,
        'message_id': 1,
        'priority': 32,
      });
      await expectLater(
        Future.sync(
          () => DataStorageService(
            TdClient.shared,
            _slot + 1,
          ).addDownload(fileId: 501, chatId: 101, messageId: 1),
        ),
        throwsStateError,
      );
      expect(backend.requests, hasLength(1));
    },
  );

  test(
    'pause stops managed and playback owners without deleting cache',
    () async {
      await DataStorageService(TdClient.shared, _slot).pauseDownload(501);
      expect(backend.requests, [
        {'@type': 'toggleDownloadIsPaused', 'file_id': 501, 'is_paused': true},
        {
          '@type': 'cancelDownloadFile',
          'file_id': 501,
          'only_if_pending': false,
        },
      ]);
    },
  );

  testWidgets(
    'estimated bytes and historical complete date do not mean complete',
    (tester) async {
      backend.files[501] = _file(501, bytes: 60, expected: 50);
      backend.downloadSearch = (_) async => _downloads([
        _task(501, backend.files[501]!, completeDate: 1700000000),
      ]);
      await tester.pumpWidget(_app(const DownloadsView()));
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('download-row-501'));
      expect(
        find.descendant(of: row, matching: find.text('clip.mp4')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('download-toggle-501')), findsOneWidget);
      expect(find.textContaining('60 B / 100 B'), findsOneWidget);

      updates.add({
        '@type': 'updateFile',
        'file': _file(501, bytes: 100, done: true),
      });
      await tester.pump();
      expect(find.byKey(const ValueKey('download-toggle-501')), findsNothing);
      expect(find.textContaining('Completed'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a delayed old search cannot replace the new query result', (
    tester,
  ) async {
    final old = Completer<Map<String, dynamic>>();
    backend.downloadSearch = (request) async {
      if (request['query'] == 'old') return old.future;
      return _downloads(
        request['query'] == 'new'
            ? [_task(502, _file(502))]
            : [_task(501, _file(501))],
      );
    };
    await tester.pumpWidget(_app(const DownloadsView()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'old');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), 'new');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    old.complete(_downloads([_task(501, _file(501))]));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('download-row-502')), findsOneWidget);
    expect(find.byKey(const ValueKey('download-row-501')), findsNothing);
  });

  testWidgets(
    'file detail cancellation waits for registration then pauses it',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      backend.addResult = pending;
      final doc = TDParse.message(
        _message(501, backend.files[501]!, video: false),
      )!.document!;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => GestureDetector(
              key: const ValueKey('open-file'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FileDetailView(
                    doc: doc,
                    chatId: 101,
                    messageId: 501,
                    accountSlot: _slot,
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open-file')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('file-detail-pause')));
      await tester.pump();
      expect(backend.calls('toggleDownloadIsPaused'), isEmpty);
      pending.complete(_file(501, active: true));
      await tester.pumpAndSettle();
      expect(backend.calls('addFileToDownloads'), hasLength(1));
      expect(backend.calls('toggleDownloadIsPaused').single['is_paused'], true);
      expect(backend.calls('cancelDownloadFile'), hasLength(1));
      expect(find.byType(FileDetailView), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('opening a complete document does not restart its task', (
    tester,
  ) async {
    backend.files[501] = _file(501, bytes: 100, done: true);
    final doc = TDParse.message(
      _message(501, backend.files[501]!, video: false),
    )!.document!;
    await tester.pumpWidget(
      _app(FileDetailView(doc: doc, chatId: 101, messageId: 501)),
    );
    await tester.pumpAndSettle();
    expect(backend.calls('addFileToDownloads'), isEmpty);
    expect(backend.calls('downloadFile'), isEmpty);
    expect(find.byKey(const ValueKey('file-detail-pause')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Widget _app(Widget home) => ChangeNotifierProvider.value(
  value: _theme,
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [AppLocalizations.delegate],
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(extensions: [AppColors.light]),
    home: home,
  ),
);

Map<String, dynamic> _file(
  int id, {
  int bytes = 0,
  int size = 100,
  int expected = 100,
  bool active = false,
  bool done = false,
}) => {
  '@type': 'file',
  'id': id,
  'size': size,
  'expected_size': expected,
  'local': {
    '@type': 'localFile',
    'path': done ? '/synthetic/test.mp4' : '',
    'downloaded_size': bytes,
    'downloaded_prefix_size': bytes,
    'is_downloading_active': active,
    'is_downloading_completed': done,
  },
};

Map<String, dynamic> _message(
  int id,
  Map<String, dynamic> file, {
  required bool video,
  int chatId = 101,
}) => {
  '@type': 'message',
  'id': id,
  'chat_id': chatId,
  'date': 1700000000 + id,
  'is_outgoing': false,
  'content': video
      ? {
          '@type': 'messageVideo',
          'caption': {
            '@type': 'formattedText',
            'text': 'Video $id',
            'entities': [],
          },
          'video': {
            '@type': 'video',
            'file_name': 'clip.mp4',
            'duration': 30,
            'width': 1280,
            'height': 720,
            'video': file,
          },
        }
      : {
          '@type': 'messageDocument',
          'caption': {'@type': 'formattedText', 'text': '', 'entities': []},
          'document': {
            '@type': 'document',
            'file_name': 'document-$id.pdf',
            'mime_type': 'application/pdf',
            'document': file,
          },
        },
};

Map<String, dynamic> _task(
  int id,
  Map<String, dynamic> file, {
  bool paused = false,
  int completeDate = 0,
}) => {
  '@type': 'fileDownload',
  'file_id': id,
  'message': _message(id, file, video: true),
  'is_paused': paused,
  'complete_date': completeDate,
};
Map<String, dynamic> _downloads(List<Map<String, dynamic>> tasks) => {
  '@type': 'foundFileDownloads',
  'files': tasks,
  'next_offset': '',
};

class _Backend {
  final requests = <Map<String, dynamic>>[];
  final files = <int, Map<String, dynamic>>{501: _file(501, active: true)};
  final mediaPages = <String, Map<String, dynamic>>{};
  TdError? pauseError;
  Completer<Map<String, dynamic>>? addResult;
  Future<Map<String, dynamic>> Function(Map<String, dynamic>)? downloadSearch;
  List<Map<String, dynamic>> calls(String type) =>
      requests.where((r) => r['@type'] == type).toList();

  Future<Map<String, dynamic>> query(Map<String, dynamic> request) async {
    requests.add(Map.of(request));
    final id = request['file_id'] as int? ?? 501;
    switch (request['@type']) {
      case 'searchFileDownloads':
        return downloadSearch?.call(request) ??
            _downloads([_task(501, files[501]!)]);
      case 'searchMessages':
        return mediaPages[request['offset']] ??
            {'@type': 'foundMessages', 'messages': [], 'next_offset': ''};
      case 'getFile':
        return files[id] ?? _file(id);
      case 'getChat':
        return {
          '@type': 'chat',
          'id': request['chat_id'],
          'title': 'Source chat',
        };
      case 'addFileToDownloads':
        if (addResult != null) return addResult!.future;
        final old = files[id]?['local'] as Map<String, dynamic>?;
        return files[id] = _file(
          id,
          bytes: old?['downloaded_size'] as int? ?? 0,
          active: true,
        );
      case 'toggleDownloadIsPaused':
        if (pauseError != null) throw pauseError!;
      case 'cancelDownloadFile':
        final local = files[id]?['local'] as Map<String, dynamic>?;
        if (local != null) local['is_downloading_active'] = false;
    }
    return {'@type': 'ok'};
  }
}
