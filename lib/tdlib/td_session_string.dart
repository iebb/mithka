//
//  td_session_string.dart
//
//  The packed session string the patched tdjson exports and imports:
//  `>BI?256sQ?` — dc id, api id, test mode, 256-byte auth key, user id and the
//  bot flag — encoded as unpadded base64url. Pyrogram reads the same layout
//  from a string session, so an account can move between the two.
//

import 'dart:convert';
import 'dart:typed_data';

/// Fields of a decoded [TdSessionString].
class TdSessionStringData {
  const TdSessionStringData({
    required this.dcId,
    required this.apiId,
    required this.testMode,
    required this.authKey,
    required this.userId,
    required this.isBot,
  });

  final int dcId;
  final int apiId;
  final bool testMode;
  final Uint8List authKey;
  final int userId;
  final bool isBot;
}

/// Packs and validates [TdSessionStringData].
abstract final class TdSessionString {
  /// Size of the packed payload: 1 + 4 + 1 + 256 + 8 + 1.
  static const int rawLength = 271;

  /// Telegram auth keys are always 256 bytes.
  static const int authKeyLength = 256;

  static const int _authKeyOffset = 6;
  static const int _userIdOffset = 262;

  /// Decodes [sessionString], rejecting payloads the importer cannot use.
  ///
  /// Throws a [FormatException] describing the first invalid field.
  static TdSessionStringData decode(String sessionString) {
    final normalized = sessionString.trim();
    if (normalized.isEmpty) {
      throw const FormatException('TDLib session string is empty');
    }

    final Uint8List bytes;
    try {
      bytes = base64Url.decode(base64Url.normalize(normalized));
    } on FormatException catch (error) {
      throw FormatException(
        'TDLib session string is not valid base64url',
        error,
      );
    }

    if (bytes.length != rawLength) {
      throw FormatException(
        'TDLib session string decoded size is ${bytes.length}, expected $rawLength',
      );
    }

    final dcId = bytes[0];
    final apiId = ByteData.sublistView(bytes, 1, 5).getUint32(0);
    final testMode = bytes[5] != 0;
    final authKey = Uint8List.sublistView(
      bytes,
      _authKeyOffset,
      _authKeyOffset + authKeyLength,
    );
    final userId = ByteData.sublistView(
      bytes,
      _userIdOffset,
      _userIdOffset + 8,
    ).getUint64(0);
    final isBot = bytes[270] != 0;

    if (dcId == 0) {
      throw const FormatException('TDLib session string has invalid DC id');
    }
    if (apiId == 0) {
      throw const FormatException('TDLib session string has invalid API id');
    }
    if (userId == 0) {
      throw const FormatException('TDLib session string has invalid user id');
    }
    if (authKey.every((byte) => byte == 0)) {
      throw const FormatException('TDLib session string has an empty auth key');
    }

    return TdSessionStringData(
      dcId: dcId,
      apiId: apiId,
      testMode: testMode,
      authKey: Uint8List.fromList(authKey),
      userId: userId,
      isBot: isBot,
    );
  }

  /// Packs [data] into the string tdjson's importer accepts.
  static String encode(TdSessionStringData data) {
    if (data.authKey.length != authKeyLength) {
      throw ArgumentError.value(
        data.authKey.length,
        'data.authKey',
        'must hold $authKeyLength bytes',
      );
    }
    final packed = Uint8List(rawLength);
    final view = ByteData.sublistView(packed);
    packed[0] = data.dcId;
    view.setUint32(1, data.apiId);
    packed[5] = data.testMode ? 1 : 0;
    packed.setRange(
      _authKeyOffset,
      _authKeyOffset + authKeyLength,
      data.authKey,
    );
    view.setUint64(_userIdOffset, data.userId);
    packed[270] = data.isBot ? 1 : 0;
    return base64Url.encode(packed).replaceAll('=', '');
  }
}
