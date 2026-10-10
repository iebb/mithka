import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/tdlib/gram_js_session.dart';
import 'package:mithka/tdlib/td_session_string.dart';

void main() {
  const apiId = 34216039;
  const userId = 7041948142;
  final authKey = _authKey(7);

  test('a rendered GramJS session uses the layout GramJS writes', () {
    final session = GramJsSession(
      dcId: 4,
      serverAddress: '149.154.167.91',
      port: 443,
      authKey: authKey,
    );

    final payload = BytesBuilder();
    payload.addByte(4);
    payload.add([0x00, 0x0e]);
    payload.add(utf8.encode('149.154.167.91'));
    payload.add([0x01, 0xbb]);
    payload.add(authKey);

    expect(session.render(), '1${base64.encode(payload.toBytes())}');
  });

  test('a GramJS session survives a render and parse round trip', () {
    final session = GramJsSession(
      dcId: 2,
      serverAddress: '149.154.167.51',
      port: 443,
      authKey: authKey,
    );

    final parsed = GramJsSession.parse(session.render());

    expect(parsed.dcId, 2);
    expect(parsed.serverAddress, '149.154.167.51');
    expect(parsed.port, 443);
    expect(parsed.authKey, authKey);
  });

  test('parsing accepts unpadded and url-safe base64 payloads', () {
    final rendered = GramJsSession(
      dcId: 5,
      serverAddress: '91.108.56.130',
      port: 443,
      authKey: authKey,
    ).render();
    final payloadText = rendered.substring(1);

    final unpadded = payloadText.replaceAll('=', '');
    final urlSafe = unpadded.replaceAll('+', '-').replaceAll('/', '_');

    for (final variant in [unpadded, urlSafe]) {
      final parsed = GramJsSession.parse('1$variant');
      expect(parsed.dcId, 5);
      expect(parsed.authKey, authKey);
    }
  });

  test('parsing rejects payloads Mithka cannot import', () {
    final rendered = GramJsSession(
      dcId: 2,
      serverAddress: '149.154.167.51',
      port: 443,
      authKey: authKey,
    ).render();
    final payload = base64.decode(rendered.substring(1));

    String encode(List<int> bytes) => '1${base64.encode(bytes)}';

    expect(() => GramJsSession.parse(''), throwsFormatException);
    expect(
      () => GramJsSession.parse('2${rendered.substring(1)}'),
      throwsFormatException,
    );
    expect(() => GramJsSession.parse('1not base64!'), throwsFormatException);
    expect(
      () => GramJsSession.parse(encode(payload.sublist(0, 20))),
      throwsFormatException,
    );
    // Zero DC id.
    expect(
      () => GramJsSession.parse(encode([0, ...payload.sublist(1)])),
      throwsFormatException,
    );
    // Raw IPv6 endpoint, which GramJS marks with a length above 100.
    expect(
      () => GramJsSession.parse(encode([2, 0, 101, ...payload.sublist(3)])),
      throwsFormatException,
    );
    // Zero port.
    final zeroPort = Uint8List.fromList(payload);
    zeroPort[17] = 0;
    zeroPort[18] = 0;
    expect(() => GramJsSession.parse(encode(zeroPort)), throwsFormatException);
    // All-zero auth key.
    final zeroKey = Uint8List.fromList(payload);
    for (var i = zeroKey.length - 256; i < zeroKey.length; i++) {
      zeroKey[i] = 0;
    }
    expect(() => GramJsSession.parse(encode(zeroKey)), throwsFormatException);
    expect(GramJsSession.tryParse(rendered.replaceAll('1', 'x')), isNull);
  });

  test('a packed TDLib session exports to its DC endpoint', () {
    final packed = _tdSession(dcId: 2, authKey: authKey);

    final parsed = GramJsSession.parse(
      gramJsSessionFromTdSessionString(packed),
    );

    expect(parsed.dcId, 2);
    expect(parsed.serverAddress, GramJsEndpoint.production[2]!.address);
    expect(parsed.port, GramJsEndpoint.production[2]!.port);
    expect(parsed.authKey, authKey);
  });

  test('a test-mode TDLib session keeps the test endpoint', () {
    final packed = _tdSession(dcId: 1, testMode: true, authKey: authKey);

    final parsed = GramJsSession.parse(
      gramJsSessionFromTdSessionString(packed),
    );

    expect(parsed.serverAddress, GramJsEndpoint.test[1]!.address);
  });

  test('a DC GramJS cannot dial is refused', () {
    expect(
      () => gramJsSessionFromTdSessionString(_tdSession(dcId: 9)),
      throwsStateError,
    );
  });

  test('a GramJS session packs into the layout tdjson imports', () {
    final session = GramJsSession(
      dcId: 4,
      serverAddress: '149.154.167.91',
      port: 443,
      authKey: authKey,
    );

    final packed = tdSessionStringFromGramJsSession(session, apiId: apiId);
    final decoded = TdSessionString.decode(packed);

    expect(decoded.dcId, 4);
    expect(decoded.apiId, apiId);
    expect(decoded.authKey, authKey);
    expect(decoded.testMode, isFalse);
    expect(decoded.isBot, isFalse);
    expect(decoded.userId, tdSessionUnknownUserId);
    expect(
      () => tdSessionStringFromGramJsSession(session, apiId: 0),
      throwsArgumentError,
    );
  });

  test('the reserved user id stays unknown to TDLib', () {
    // UserManager::load_my_id keeps a stored id only inside UserId's
    // 1..2^40-1 range, and retries with the first five characters dropped
    // before giving up, so both reads have to fail for TDLib to resolve the
    // account itself.
    const maxTdlibUserId = (1 << 40) - 1;

    expect(tdSessionUnknownUserId, greaterThan(0));
    expect(tdSessionUnknownUserId, greaterThan(maxTdlibUserId));
    expect(
      int.parse('$tdSessionUnknownUserId'.substring(5)),
      lessThanOrEqualTo(0),
    );
  });

  test('session formats are told apart', () {
    final packed = _tdSession(dcId: 2, authKey: authKey);
    final gramJs = GramJsSession(
      dcId: 2,
      serverAddress: '149.154.167.51',
      port: 443,
      authKey: authKey,
    ).render();

    expect(detectSessionStringFormat(packed), SessionStringFormat.pyrogram);
    expect(detectSessionStringFormat(gramJs), SessionStringFormat.gramJs);
    expect(
      detectSessionStringFormat('  $gramJs  '),
      SessionStringFormat.gramJs,
    );
    expect(detectSessionStringFormat(''), SessionStringFormat.unknown);
    expect(
      detectSessionStringFormat('1not a session'),
      SessionStringFormat.unknown,
    );
  });

  test('a packed session is never read as GramJS', () {
    // API id 0x000a6463 makes the packed layout read as a ten-character
    // address, so the payload size matches a GramJS session exactly. The
    // test-mode byte that follows is never a host character, which is what
    // keeps the two layouts apart.
    final packed = _tdSession(dcId: 2, apiId: 0x000a6463, authKey: authKey);
    final decoded = TdSessionString.decode(packed);

    expect(decoded.apiId, 0x000a6463);
    expect(GramJsSession.tryParse(packed), isNull);
    expect(detectSessionStringFormat(packed), SessionStringFormat.pyrogram);
  });

  test('a GramJS session that looks packed stays GramJS', () {
    // A ten-character address gives the GramJS payload the packed size, and
    // every packed field check passes on it too.
    final session = GramJsSession(
      dcId: 2,
      serverAddress: '10.0.0.123',
      port: 443,
      authKey: authKey,
    );
    final rendered = session.render();
    final payload = base64.decode(rendered.substring(1));

    expect(payload, hasLength(TdSessionString.rawLength));
    expect(
      TdSessionString.decode(
        base64Url.encode(payload).replaceAll('=', ''),
      ).dcId,
      2,
    );
    expect(detectSessionStringFormat(rendered), SessionStringFormat.gramJs);
  });

  test('a packed TDLib session round trips through base64url', () {
    final packed = _tdSession(dcId: 3, authKey: authKey, isBot: true);

    final decoded = TdSessionString.decode(packed);

    expect(
      base64Url.decode(base64Url.normalize(packed)),
      hasLength(TdSessionString.rawLength),
    );
    expect(decoded.dcId, 3);
    expect(decoded.apiId, apiId);
    expect(decoded.userId, userId);
    expect(decoded.isBot, isTrue);
    expect(TdSessionString.encode(decoded), packed);
  });

  test('a packed TDLib session rejects the fields tdjson rejects', () {
    expect(() => TdSessionString.decode(''), throwsFormatException);
    expect(
      () => TdSessionString.decode(base64Url.encode(Uint8List(270))),
      throwsFormatException,
    );
    expect(
      () => TdSessionString.decode(_tdSession(dcId: 0)),
      throwsFormatException,
    );
    expect(
      () => TdSessionString.decode(_tdSession(apiId: 0)),
      throwsFormatException,
    );
    expect(
      () => TdSessionString.decode(_tdSession(userId: 0)),
      throwsFormatException,
    );
    expect(
      () => TdSessionString.decode(_tdSession(authKey: Uint8List(256))),
      throwsFormatException,
    );
    expect(
      () => TdSessionString.encode(
        TdSessionStringData(
          dcId: 2,
          apiId: apiId,
          testMode: false,
          authKey: Uint8List(255),
          userId: userId,
          isBot: false,
        ),
      ),
      throwsArgumentError,
    );
  });
}

Uint8List _authKey(int seed) => Uint8List.fromList(
  List<int>.generate(256, (index) => (index + seed) % 251 + 1),
);

String _tdSession({
  int dcId = 4,
  int apiId = 34216039,
  bool testMode = false,
  Uint8List? authKey,
  int userId = 7041948142,
  bool isBot = false,
}) => TdSessionString.encode(
  TdSessionStringData(
    dcId: dcId,
    apiId: apiId,
    testMode: testMode,
    authKey: authKey ?? _authKey(3),
    userId: userId,
    isBot: isBot,
  ),
);
