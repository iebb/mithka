//
//  The version reported to Telegram in setTdlibParameters must follow the
//  packaged app version (Settings › Devices shows it), not stay frozen at the
//  legacy "1.0" placeholder. The provider seam keeps td_client plugin-free;
//  the bootstrap seeds it from AppVersion once the platform channel answers.
//

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/tdlib/td_bindings.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_session_string.dart';
import 'package:shared_preferences/shared_preferences.dart';

Uint8List _syntheticAuthKey(int seed) {
  final key = Uint8List(TdSessionString.authKeyLength);
  for (var i = 0; i < key.length; i++) {
    key[i] = ((seed + i * 7) % 251) + 1;
  }
  return key;
}

String _syntheticSession({int userId = 777, int seed = 1}) =>
    TdSessionString.encode(
      TdSessionStringData(
        dcId: 2,
        apiId: 2496,
        testMode: false,
        authKey: _syntheticAuthKey(seed),
        userId: userId,
        isBot: false,
      ),
    );

/// Stands in for tdjson. Records every request the restore path sends and
/// writes a placeholder binlog where the real importer would.
class _ParameterRecordingBindings implements TdBindings {
  _ParameterRecordingBindings(this._client);

  final TdClient _client;
  final List<(int, Map<String, dynamic>)> sent = [];
  int _nextClientId = 100;

  List<Map<String, dynamic>> sentSetTdlibParameters() => [
    for (final (_, request) in sent)
      if (request['@type'] == 'setTdlibParameters') request,
  ];

  @override
  int createClientId() => _nextClientId++;

  @override
  void send(int clientId, String request) {
    final decoded = jsonDecode(request) as Map<String, dynamic>;
    sent.add((clientId, decoded));
    if (decoded['@type'] == 'close') {
      _client.debugCompleteClientClosed(clientId);
    }
  }

  @override
  void importSessionString(String sessionString, String destinationPath) {
    File(
      destinationPath,
    ).writeAsBytesSync(Uint8List.fromList(const [1, 2, 3, 4]));
  }

  @override
  bool get supportsSessionStringBackup => true;

  @override
  bool get supportsTransferBoost => false;

  @override
  String? receive(double timeout) => null;

  @override
  Object? receiveJson(double timeout) => null;

  @override
  String? execute(String request) => null;

  @override
  String exportSessionString(
    String sourcePath, {
    required int apiId,
    required bool testMode,
    required int userId,
  }) => throw UnimplementedError();

  @override
  void configureTransferBoost({
    required int downloadChunkSize,
    required int downloadParallelism,
    required int uploadChunkSize,
    required int uploadParallelism,
  }) {}
}

void main() {
  tearDown(() => TdClient.applicationVersionProvider = null);

  test('restore reports the provided application version', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TdClient.applicationVersionProvider = () => '1.12.0';
    SharedPreferences.setMockInitialValues(const {
      // Usable custom credentials keep the placeholder Secrets out of the
      // parameters, so the assertions see only the seams under test.
      'mithka.api_credentials.enabled': true,
      'mithka.api_credentials.api_id': '2496',
      'mithka.api_credentials.api_hash': '0123456789abcdef0123456789abcdef',
    });
    final prefs = await SharedPreferences.getInstance();
    final supportDir = Directory.systemTemp.createTempSync('mithka_appver');
    addTearDown(() {
      if (supportDir.existsSync()) supportDir.deleteSync(recursive: true);
    });

    final client = TdClient.forTesting();
    final bindings = _ParameterRecordingBindings(client);
    // First getAuthorizationState answers WaitTdlibParameters — the state
    // that makes the restore loop send its setTdlibParameters — and stays
    // ready afterwards, reporting the session's user from getMe.
    final seenStates = <int>{};
    client.prepareForTesting(
      prefs: prefs,
      supportDir: supportDir.path,
      bindings: bindings,
      queryOverride: (request, clientId) async {
        switch (request['@type']) {
          case 'getAuthorizationState':
            return seenStates.add(clientId)
                ? const {'@type': 'authorizationStateWaitTdlibParameters'}
                : const {'@type': 'authorizationStateReady'};
          case 'getMe':
            return {'@type': 'user', 'id': 777, 'first_name': 'Synthetic'};
          default:
            return const {'@type': 'ok'};
        }
      },
    );

    final slot = await client.restoreSessionSlot(_syntheticSession());
    expect(slot, 1);

    final parameters = bindings.sentSetTdlibParameters();
    expect(parameters, isNotEmpty);
    for (final request in parameters) {
      expect(request['application_version'], '1.12.0');
    }
  });

  test('without a provider the legacy placeholder stays the answer', () {
    final client = TdClient.forTesting();
    expect(client.debugApplicationVersionForTesting(), '1.0');
  });
}
