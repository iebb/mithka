import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('nightly sync runs once daily at midnight UTC', () {
    final workflow = File(
      '.github/workflows/sync-nightly.yml',
    ).readAsStringSync();

    expect(RegExp(r"cron: '0 0 \* \* \*'").allMatches(workflow), hasLength(1));
    expect(workflow, isNot(contains("cron: '0 0,12 * * *'")));
  });
}
