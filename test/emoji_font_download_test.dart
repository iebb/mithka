import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/theme/emoji_font_catalog.dart';

/// The Apple font downloads on first use instead of shipping in the APK.
/// This suite drives the full cache lifecycle through the production code
/// paths (no FontLoader involvement — families only register on a real
/// engine, so every assertion reads the on-disk cache).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const paths = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory temporary;
  late Directory cacheDir;
  late List<Uri> requested;
  late EmojiFontCatalog catalog;

  Future<void> serveFonts(Map<String, List<int>> fonts) async {
    messenger.setMockMethodCallHandler(paths, (call) async => temporary.path);
    HttpOverrides.global = _FontHttpOverrides(fonts, requested.add);
  }

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('emoji_font_test');
    requested = [];
    catalog = EmojiFontCatalog.forTesting();
    await serveFonts({
      'https://raw.githubusercontent.com/GORAlexComp/AppleColorEmojiFont'
          '/main/fonts/AppleColorEmoji.ttf': List.filled(
        1024,
        7,
      ),
    });
    cacheDir = Directory(
      '${temporary.path}/${EmojiFontCatalog.cacheDirectoryName}',
    );
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(paths, null);
    HttpOverrides.global = null;
    debugDefaultTargetPlatformOverride = null;
    try {
      await temporary.delete(recursive: true);
    } catch (_) {}
  });

  test('loadAppleFont without download reports a missing cache file', () async {
    final family = await catalog.loadAppleFont();
    expect(family, isNull);
    expect(requested, isEmpty);
  });

  test('first use downloads the Apple font into the shared cache', () async {
    await catalog.ensureFontDownloaded(EmojiFontCatalog.appleEntry);

    final file = File('${cacheDir.path}/apple.ttf');
    expect(await file.exists(), isTrue);
    expect(await file.length(), 1024);
    expect(requested, hasLength(1));
    expect(requested.single.toString(), contains('AppleColorEmoji.ttf'));
    // The size index records the download for truncation checks.
    final index = File('${cacheDir.path}/sizes.json');
    expect(await index.exists(), isTrue);
  });

  test('a cached font is not downloaded again', () async {
    await catalog.ensureFontDownloaded(EmojiFontCatalog.appleEntry);
    await catalog.ensureFontDownloaded(EmojiFontCatalog.appleEntry);
    expect(requested, hasLength(1));
  });

  test('a truncated cache file is re-downloaded', () async {
    await catalog.ensureFontDownloaded(EmojiFontCatalog.appleEntry);
    final file = File('${cacheDir.path}/apple.ttf');
    await file.writeAsBytes(List.filled(10, 7), flush: true);
    await catalog.ensureFontDownloaded(EmojiFontCatalog.appleEntry);
    expect(requested, hasLength(2));
    expect(await file.length(), 1024);
  });
}

class _FontHttpOverrides extends HttpOverrides {
  _FontHttpOverrides(this._fonts, this._onRequest);

  final Map<String, List<int>> _fonts;
  final void Function(Uri) _onRequest;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _MockHttpClient(_fonts, _onRequest);
  }
}

class _MockHttpClient implements HttpClient {
  _MockHttpClient(this._fonts, this._onRequest);

  final Map<String, List<int>> _fonts;
  final void Function(Uri) _onRequest;

  Future<HttpClientRequest> _request(Uri url) async =>
      _MockHttpClientRequest(url, _fonts, _onRequest);

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _request(url);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) => _request(url);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MockHttpClientRequest implements HttpClientRequest {
  _MockHttpClientRequest(this.url, this._fonts, this._onRequest);

  final Uri url;
  final Map<String, List<int>> _fonts;
  final void Function(Uri) _onRequest;

  @override
  Future<HttpClientResponse> close() async => _respond();

  Future<HttpClientResponse> _respond() async {
    _onRequest(url);
    final body = _fonts[url.toString()];
    if (body == null) {
      return _MockHttpClientResponse(url, [], 404);
    }
    return _MockHttpClientResponse(url, body, 200);
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  Future<HttpClientResponse> get done async => _respond();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MockHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _MockHttpClientResponse(this.url, this.bytes, this.statusCode);

  final Uri url;
  final List<int> bytes;
  @override
  final int statusCode;

  @override
  int get contentLength => bytes.length;

  @override
  bool get isRedirect => false;

  @override
  HttpHeaders get headers => _MockHttpHeaders();

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

class _MockHttpHeaders implements HttpHeaders {
  @override
  List<String>? operator [](String name) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
