import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/appearance_view.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/emoji_font_catalog.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

/// The emoji font picker round: 系统默认 first / apple second / rest
/// alphabetical, downloaded packs show 已下载 · size, swipe-to-delete clears
/// the cached file.
void main() {
  setUpAll(() => L10nFixtures.load().install());
  TestWidgetsFlutterBinding.ensureInitialized();

  const paths = MethodChannel('plugins.flutter.io/path_provider');
  late Directory temporary;

  const manifestBody = '''
{
  "generated": "2026-11-18",
  "fonts": [
    {"key": "apple", "label": "Apple Color Emoji", "license": "Apple", "kind": "color", "format": "ttf", "url": "https://example.com/apple.ttf"},
    {"key": "twemoji", "label": "Twemoji", "license": "CC-BY-4.0", "kind": "color", "format": "ttf", "url": "https://example.com/twemoji.ttf"},
    {"key": "blobmoji", "label": "Blobmoji", "license": "OFL-1.1", "kind": "color", "format": "ttf", "url": "https://example.com/blobmoji.ttf"},
    {"key": "openmoji", "label": "OpenMoji", "license": "CC-BY-SA-4.0", "kind": "color", "format": "ttf", "url": "https://example.com/openmoji.ttf"}
  ]
}
''';

  setUpAll(() async {
    EmojiFontCatalog.debugSkipEngineFontLoad = true;
    temporary = await Directory.systemTemp.createTemp('emoji_picker_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (call) async => temporary.path);
  });

  tearDownAll(() async {
    EmojiFontCatalog.debugSkipEngineFontLoad = false;
    try {
      await temporary.delete(recursive: true);
    } catch (_) {}
  });

  late EmojiFontCatalog pickerCatalog;

  Future<List<EmojiFontManifestEntry>> manifest() async =>
      pickerCatalog.parseManifestForTesting(manifestBody);

  Future<void> pumpPicker(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs, emojiFontCatalog: pickerCatalog);
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppColors.light]),
          home: EmojiFontPickerView(manifestOverride: manifest()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('row order: system, apple, then alphabetical', (tester) async {
    pickerCatalog = EmojiFontCatalog.forTesting();
    await pumpPicker(tester);
    expect(find.text('System default'), findsOneWidget);
    final labels = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    final order = [
      for (final label in labels)
        if ([
          'System default',
          'Apple Color Emoji',
          'Blobmoji',
          'OpenMoji',
          'Twemoji',
        ].contains(label))
          label,
    ];
    expect(order, [
      'System default',
      'Apple Color Emoji',
      'Blobmoji',
      'OpenMoji',
      'Twemoji',
    ]);
  });

  testWidgets('download state captions flip after a download', (tester) async {
    pickerCatalog = EmojiFontCatalog.forTesting();
    HttpOverrides.global = _ManifestHttpOverrides({
      'https://example.com/apple.ttf': List.filled(63, 1).join(),
    });
    addTearDown(() => HttpOverrides.global = null);
    await pumpPicker(tester);
    final appleRow = find.text('Apple Color Emoji');
    expect(appleRow, findsOneWidget);
    final appleCenter = tester.getCenter(appleRow);
    await tester.tapAt(appleCenter);
    await tester.pump(const Duration(milliseconds: 200));
    // testWidgets runs fake-async: pump until the download lands on the real
    // event loop and the caption flips (voice-recording suite's pattern).
    for (var attempt = 0; attempt < 100; attempt++) {
      if (find.text('Downloaded · 63 B').evaluate().isNotEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('Downloaded · 63 B'), findsOneWidget);
  });
}

class _ManifestHttpOverrides extends HttpOverrides {
  _ManifestHttpOverrides(this._bodies);

  final Map<String, String> _bodies;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _ManifestHttpClient(_bodies);
}

class _ManifestHttpClient implements HttpClient {
  _ManifestHttpClient(this._bodies);

  final Map<String, String> _bodies;

  Future<HttpClientRequest> _request(Uri url) async =>
      _ManifestHttpClientRequest(url, _bodies);

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _request(url);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) => _request(url);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _ManifestHttpClientRequest implements HttpClientRequest {
  _ManifestHttpClientRequest(this.url, this._bodies);

  final Uri url;
  final Map<String, String> _bodies;

  @override
  Future<HttpClientResponse> close() async {
    final body = _bodies[url.toString()];
    final bytes = body == null ? <int>[] : body.codeUnits;
    return _ManifestHttpClientResponse(url, bytes, body == null ? 404 : 200);
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _ManifestHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _ManifestHttpClientResponse(this.url, this.bytes, this.statusCode);

  final Uri url;
  final List<int> bytes;
  @override
  final int statusCode;

  @override
  int get contentLength => bytes.length;

  @override
  bool get isRedirect => false;

  @override
  HttpHeaders get headers => _ManifestHttpHeaders();

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  bool get persistentConnection => true;

  @override
  String get reasonPhrase => 'OK';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(bytes).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

class _ManifestHttpHeaders implements HttpHeaders {
  @override
  List<String>? operator [](String name) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
