import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('video playback keeps TDLib file operations on the source account', () {
    final chat = File('lib/chat/chat_view.dart').readAsStringSync();
    final player = File('lib/chat/video_player_view.dart').readAsStringSync();
    final files = File('lib/tdlib/td_image_loader.dart').readAsStringSync();
    final desktop = File(
      'lib/app/desktop_video_window.dart',
    ).readAsStringSync();

    expect(chat, contains('accountSlot: _sessionKey.accountSlot'));
    expect(player, contains('accountSlot: item.accountSlot'));
    expect(
      player,
      contains('tdVideoStreamQueryForAccount(widget.accountSlot)'),
    );
    expect(player, contains('accountSlot: widget.accountSlot'));
    expect(files, contains('.subscribeAll()'));
    expect(files, contains('.queryForSlot('));
    expect(desktop, contains('mediaKey = (accountSlot: accountSlot'));
    expect(
      desktop,
      contains('query: tdVideoStreamQueryForAccount(accountSlot)'),
    );
  });
}
