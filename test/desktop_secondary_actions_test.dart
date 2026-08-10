import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'desktop secondary click exposes actions that remain long-pressable',
    () {
      final topics = File(
        'lib/chat/channel_direct_messages_view.dart',
      ).readAsStringSync();
      final login = File('lib/auth/login_view.dart').readAsStringSync();

      expect(topics, contains('onSecondaryTap: onLongPress'));
      expect(login, contains('onSecondaryTap: enabled ? _disableProxy : null'));
    },
  );
}
