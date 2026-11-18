import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/theme/emoji_font_catalog.dart';

/// The MithkaX emoji font source round: the manifest comes from
/// dl.mintabyss.eu.org, entries carry sha256 + bytes, cached files verify by
/// content hash, and downloaded packs can be deleted from the cache.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const paths = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory temporary;
  late Directory cacheDir;
  late List<Uri> requested;
  late EmojiFontCatalog catalog;

  // A tiny valid-ish font body: contents only matter for the hash check.
  final appleBytes = List<int>.filled(1024, 7);

  Future<void> serveFonts(Map<String, List<int>> fonts) async {
    messenger.setMockMethodCallHandler(paths, (call) async => temporary.path);
    HttpOverrides.global = _FontHttpOverrides(fonts, requested.add);
  }

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('emoji_font_test');
    requested = [];
    catalog = EmojiFontCatalog.forTesting();
    await serveFonts({
      'https://dl.mintabyss.eu.org/emojifonts/apple.ttf': appleBytes,
      'https://dl.mintabyss.eu.org/emojifonts/twemoji.ttf': List.filled(512, 3),
    });
    cacheDir = Directory(
      '${temporary.path}/${EmojiFontCatalog.cacheDirectoryName}',
    );
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(paths, null);
    HttpOverrides.global = null;
    try {
      await temporary.delete(recursive: true);
    } catch (_) {}
  });

  List<EmojiFontManifestEntry> parse(String body) =>
      catalog.parseManifestForTesting(body);

  const manifestBody = '''
{
  "generated": "2026-11-18",
  "fonts": [
    {
      "key": "apple",
      "label": "Apple Color Emoji",
      "license": "Apple",
      "kind": "color",
      "format": "ttf",
      "url": "https://dl.mintabyss.eu.org/emojifonts/apple.ttf",
      "bytes": 1024
    },
    {
      "key": "twemoji",
      "label": "Twemoji",
      "license": "CC-BY-4.0",
      "kind": "color",
      "format": "ttf",
      "url": "https://dl.mintabyss.eu.org/emojifonts/twemoji.ttf"
    }
  ]
}
''';

  test('the MithkaX manifest parses with url/format/sha256/bytes', () {
    final entries = parse(manifestBody);
    expect(entries, hasLength(2));
    final apple = entryFor(entries, 'apple');
    expect(apple.url, 'https://dl.mintabyss.eu.org/emojifonts/apple.ttf');
    expect(apple.format, 'ttf');
    expect(apple.sizeBytes, 1024);
    expect(apple.extension, 'ttf');
  });

  test('the legacy iebb formats map still resolves', () {
    const body = '''
{
  "fonts": [
    {
      "key": "twemoji",
      "label": "Twemoji (jdecked)",
      "formats": {
        "sbix": "https://example.com/twemoji.ttf",
        "colrv0": "https://example.com/twemoji-colrv0.ttf"
      }
    }
  ]
}
''';
    final entries = parse(body);
    expect(entries.single.url, 'https://example.com/twemoji.ttf');
    expect(entries.single.format, 'sbix');
  });

  test('fluent rows are dropped from any manifest', () {
    const body = '''
{
  "fonts": [
    {"key": "fluent", "label": "Microsoft Fluent 3D", "url": "https://example.com/fluent.ttc"},
    {"key": "twemoji", "label": "Twemoji", "url": "https://example.com/twemoji.ttf"}
  ]
}
''';
    final entries = parse(body);
    expect(entries.map((e) => e.key), ['twemoji']);
  });

  test(
    'a hash-bearing entry verifies by sha256 and redownloads on mismatch',
    () async {
      final digest = crypto.sha256.convert(appleBytes).toString();
      final entries = parse(manifestBody);
      final raw = entryFor(entries, 'apple');
      final apple = EmojiFontManifestEntry(
        key: raw.key,
        label: raw.label,
        license: raw.license,
        kind: raw.kind,
        url: raw.url,
        format: raw.format,
        coveragePct: raw.coveragePct,
        emojiVersion: raw.emojiVersion,
        updated: raw.updated,
        sha256: digest,
      );

      await catalog.ensureFontDownloaded(apple);
      expect(requested, hasLength(1));

      // Corrupt the cached file: the hash no longer matches, so the next
      // ensure downloads again.
      final file = File('${cacheDir.path}/apple.ttf');
      await file.writeAsBytes(List.filled(16, 1), flush: true);
      await catalog.ensureFontDownloaded(apple);
      expect(requested, hasLength(2));
      expect(await file.length(), 1024);
    },
  );

  test('a hash-less entry falls back to the size index', () async {
    final entries = parse(manifestBody);
    final twemoji = entryFor(entries, 'twemoji');
    expect(twemoji.sha256, isNull);

    await catalog.ensureFontDownloaded(twemoji);
    final file = File('${cacheDir.path}/twemoji.ttf');
    expect(await file.length(), 512);

    await file.writeAsBytes(List.filled(8, 3), flush: true);
    await catalog.ensureFontDownloaded(twemoji);
    expect(requested.last.toString(), contains('twemoji.ttf'));
    expect(await file.length(), 512);
  });

  test(
    'deleteCachedFont removes the file and reports size correctly',
    () async {
      final entries = parse(manifestBody);
      final apple = entryFor(entries, 'apple');

      expect(await catalog.cachedFontSize('apple'), isNull);
      await catalog.ensureFontDownloaded(apple);
      expect(await catalog.cachedFontSize('apple'), 1024);

      expect(await catalog.deleteCachedFont('apple'), isTrue);
      expect(await catalog.cachedFontSize('apple'), isNull);
      expect(await File('${cacheDir.path}/apple.ttf').exists(), isFalse);
      // Second delete is a safe no-op.
      expect(await catalog.deleteCachedFont('apple'), isFalse);
      // System is never deletable.
      expect(await catalog.deleteCachedFont('system'), isFalse);
    },
  );
}

EmojiFontManifestEntry entryFor(
  List<EmojiFontManifestEntry> entries,
  String key,
) => entries.firstWhere((e) => e.key == key);

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
