import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/tdlib/td_client.dart';

void main() {
  test('hot restart closes every persisted native TDLib client', () {
    final sent = <(int, Map<String, dynamic>)>[];

    final closed = closeStaleDebugTdlibClients(
      [4, 5, 4, -1, 0],
      (clientId, request) =>
          sent.add((clientId, jsonDecode(request) as Map<String, dynamic>)),
    );

    expect(closed, [4, 5]);
    expect(sent.map((request) => request.$1), [4, 5]);
    expect(
      sent.map((request) => request.$2),
      everyElement(<String, dynamic>{'@type': 'close'}),
    );
  });
}
