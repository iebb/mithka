//
//  gram_js_session.dart
//
//  GramJS string sessions: `"1" + base64(dc id, address length, address, port,
//  256-byte auth key)`. Unlike the packed TDLib string, a GramJS session names
//  the endpoint it should dial and carries neither an api id nor a user id, so
//  importing one fills the api id in locally and leaves the account to TDLib.
//

import 'dart:convert';
import 'dart:typed_data';

import 'td_session_string.dart';

/// Endpoint a GramJS client dials for a Telegram DC.
class GramJsEndpoint {
  const GramJsEndpoint(this.address, this.port);

  final String address;
  final int port;

  /// Production DCs, the only ones Mithka authorizes against.
  static const Map<int, GramJsEndpoint> production = <int, GramJsEndpoint>{
    1: GramJsEndpoint('149.154.175.53', 443),
    2: GramJsEndpoint('149.154.167.51', 443),
    3: GramJsEndpoint('149.154.175.100', 443),
    4: GramJsEndpoint('149.154.167.91', 443),
    5: GramJsEndpoint('91.108.56.130', 443),
  };

  /// Test DCs, kept so a test-mode string is not exported with a production
  /// endpoint it could never authenticate against.
  static const Map<int, GramJsEndpoint> test = <int, GramJsEndpoint>{
    1: GramJsEndpoint('149.154.175.10', 443),
    2: GramJsEndpoint('149.154.167.40', 443),
    3: GramJsEndpoint('149.154.175.117', 443),
  };

  /// Returns the endpoint for [dcId], or null when Telegram has no such DC.
  static GramJsEndpoint? forDc(int dcId, {bool testMode = false}) =>
      (testMode ? test : production)[dcId];
}

/// User id packed into a [TdSessionString] whose account is not known yet.
///
/// GramJS sessions store only an endpoint and an auth key, while tdjson's
/// importer refuses a zero user id and always writes `my_id` to the binlog.
/// TDLib's `UserManager::load_my_id` keeps a stored id only inside `UserId`'s
/// 1..2^40-1 range, retrying first with the leading five characters dropped (a
/// leftover "userId" prefix), and `AuthManager` resolves an unknown id with
/// `users.getUsers(inputUserSelf)` before it reports the session as ready and
/// persists the real one. 1e18 is outside that range and every character after
/// its first five is a zero, so both reads fail and the imported session fills
/// in its own account on first connect.
const int tdSessionUnknownUserId = 1000000000000000000;

/// A decoded GramJS string session.
class GramJsSession {
  const GramJsSession({
    required this.dcId,
    required this.serverAddress,
    required this.port,
    required this.authKey,
  });

  final int dcId;
  final String serverAddress;
  final int port;
  final Uint8List authKey;

  /// Version byte every GramJS string session starts with.
  static const String version = '1';

  /// GramJS writes the address length as an int16 and reads anything above
  /// this as a raw IPv6 endpoint, which Mithka has no use for.
  static const int maxAddressLength = 100;

  static final RegExp _hostCharacters = RegExp(r'^[A-Za-z0-9._:\[\]-]+$');

  /// Decodes [session], rejecting payloads Mithka cannot import.
  ///
  /// Throws a [FormatException] describing the first invalid field.
  static GramJsSession parse(String session) {
    final normalized = session.trim();
    if (normalized.isEmpty) {
      throw const FormatException('GramJS session string is empty');
    }
    if (!normalized.startsWith(version)) {
      throw FormatException(
        'GramJS session string has version ${normalized.substring(0, 1)}, expected $version',
      );
    }

    final Uint8List payload;
    try {
      payload = _decodeBase64(normalized.substring(version.length));
    } on FormatException catch (error) {
      throw FormatException('GramJS session string is not valid base64', error);
    }

    final dcId = payload.isEmpty ? 0 : payload[0];
    if (dcId == 0) {
      throw const FormatException('GramJS session string has invalid DC id');
    }
    if (payload.length < 5) {
      throw FormatException(
        'GramJS session string decoded size is ${payload.length}, expected at least 5',
      );
    }
    final addressLength = ByteData.sublistView(payload, 1, 3).getInt16(0);
    if (addressLength < 1 || addressLength > maxAddressLength) {
      throw FormatException(
        'GramJS session string has an unsupported server address length $addressLength',
      );
    }
    final addressEnd = 3 + addressLength;
    final authKeyOffset = addressEnd + 2;
    if (payload.length != authKeyOffset + TdSessionString.authKeyLength) {
      throw FormatException(
        'GramJS session string decoded size is ${payload.length}, expected ${authKeyOffset + TdSessionString.authKeyLength}',
      );
    }

    final String serverAddress;
    try {
      serverAddress = utf8.decode(
        Uint8List.sublistView(payload, 3, addressEnd),
      );
    } on FormatException {
      throw const FormatException(
        'GramJS session string has a malformed server address',
      );
    }
    if (!_hostCharacters.hasMatch(serverAddress)) {
      throw const FormatException(
        'GramJS session string has an unsupported server address',
      );
    }

    final port = ByteData.sublistView(
      payload,
      addressEnd,
      authKeyOffset,
    ).getInt16(0);
    if (port <= 0) {
      throw const FormatException('GramJS session string has invalid port');
    }

    final authKey = Uint8List.sublistView(
      payload,
      authKeyOffset,
      payload.length,
    );
    if (authKey.every((byte) => byte == 0)) {
      throw const FormatException(
        'GramJS session string has an empty auth key',
      );
    }

    return GramJsSession(
      dcId: dcId,
      serverAddress: serverAddress,
      port: port,
      authKey: Uint8List.fromList(authKey),
    );
  }

  /// Decodes [session], or returns null when it is not a GramJS session.
  static GramJsSession? tryParse(String session) {
    try {
      return parse(session);
    } on FormatException {
      return null;
    }
  }

  /// Renders this session the way GramJS' `StringSession.save` does.
  String render() {
    final addressBytes = utf8.encode(serverAddress);
    if (addressBytes.isEmpty || addressBytes.length > maxAddressLength) {
      throw StateError(
        'GramJS server address has an unsupported length ${addressBytes.length}',
      );
    }
    final payload = Uint8List(
      5 + addressBytes.length + TdSessionString.authKeyLength,
    );
    final view = ByteData.sublistView(payload);
    final addressEnd = 3 + addressBytes.length;
    payload[0] = dcId;
    view.setInt16(1, addressBytes.length);
    payload.setRange(3, addressEnd, addressBytes);
    view.setInt16(addressEnd, port);
    payload.setRange(addressEnd + 2, payload.length, authKey);
    return '$version${base64.encode(payload)}';
  }

  /// Node's base64 reader accepts both alphabets and missing padding, so do
  /// the same for strings pasted from any GramJS build.
  static Uint8List _decodeBase64(String text) {
    var normalized = text.replaceAll('-', '+').replaceAll('_', '/');
    final remainder = normalized.length % 4;
    if (remainder != 0) {
      normalized += '=' * (4 - remainder);
    }
    return base64.decode(normalized);
  }
}

/// Renders the packed TDLib session [tdSessionString] as a GramJS session.
///
/// Throws a [FormatException] for an invalid packed session and a [StateError]
/// when its DC has no endpoint GramJS could dial.
String gramJsSessionFromTdSessionString(String tdSessionString) {
  final data = TdSessionString.decode(tdSessionString);
  final endpoint = GramJsEndpoint.forDc(data.dcId, testMode: data.testMode);
  if (endpoint == null) {
    throw StateError('GramJS sessions have no endpoint for DC ${data.dcId}');
  }
  return GramJsSession(
    dcId: data.dcId,
    serverAddress: endpoint.address,
    port: endpoint.port,
    authKey: data.authKey,
  ).render();
}

/// Packs a GramJS session for tdjson's importer.
///
/// [apiId] is the local Telegram api id: GramJS keeps it beside the session
/// instead of inside it, and the importer only rejects a zero value. The packed
/// user id is [tdSessionUnknownUserId], which TDLib replaces with the real
/// account as soon as the imported session connects.
String tdSessionStringFromGramJsSession(
  GramJsSession session, {
  required int apiId,
}) {
  if (apiId <= 0) {
    throw ArgumentError.value(apiId, 'apiId', 'must be positive');
  }
  return TdSessionString.encode(
    TdSessionStringData(
      dcId: session.dcId,
      apiId: apiId,
      testMode: false,
      authKey: session.authKey,
      userId: tdSessionUnknownUserId,
      isBot: false,
    ),
  );
}

/// Session string flavours the account backup import accepts.
enum SessionStringFormat {
  /// The packed TDLib layout Pyrogram also uses.
  pyrogram,

  /// A GramJS `StringSession`.
  gramJs,

  /// Neither, so importing would only fail inside TDLib.
  unknown,
}

/// Tells the two supported session strings apart.
///
/// Both layouts can decode from the same bytes, so the GramJS version prefix
/// decides: a packed TDLib string only starts with it for a DC id Telegram
/// never hands out.
SessionStringFormat detectSessionStringFormat(String sessionString) {
  final normalized = sessionString.trim();
  if (normalized.isEmpty) return SessionStringFormat.unknown;
  final parsesAsGramJs = GramJsSession.tryParse(normalized) != null;
  if (parsesAsGramJs && normalized.startsWith(GramJsSession.version)) {
    return SessionStringFormat.gramJs;
  }
  try {
    TdSessionString.decode(normalized);
    return SessionStringFormat.pyrogram;
  } on FormatException {
    // Not the packed layout, so a GramJS session is the only candidate left.
    if (parsesAsGramJs) return SessionStringFormat.gramJs;
  }
  return SessionStringFormat.unknown;
}
