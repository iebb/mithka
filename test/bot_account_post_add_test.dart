import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/account_store.dart';

void main() {
  test(
    'post-add cleanup cannot turn a committed bot login into failure',
    () async {
      await expectLater(
        guardBotAccountPostAddStep(
          () => throw const FileSystemException('transient cleanup failure'),
        ),
        completes,
      );
    },
  );

  test('post-add work still runs when it is healthy', () async {
    var ran = false;
    await guardBotAccountPostAddStep(() => ran = true);
    expect(ran, isTrue);
  });
}
