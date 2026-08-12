import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/tdlib/td_client.dart';

void main() {
  group('TDLib account leases', () {
    test('source client cleanup waits for the final detached owner', () {
      final book = TdAccountLeaseBook()
        ..retain(4)
        ..retain(4);

      expect(book.countFor(4), 2);
      expect(book.requestClose(4), isFalse);
      expect(book.requestDelete(4), isFalse);

      final first = book.release(4);
      expect(first.closeClient, isFalse);
      expect(first.deleteData, isFalse);
      expect(book.countFor(4), 1);

      final last = book.release(4);
      expect(last.closeClient, isTrue);
      expect(last.deleteData, isTrue);
      expect(book.countFor(4), 0);
    });

    test('an unleased account can close and delete immediately', () {
      final book = TdAccountLeaseBook();

      expect(book.requestClose(8), isTrue);
      expect(book.requestDelete(8), isTrue);
      expect(book.release(8).closeClient, isFalse);
    });

    test('foreground switching does not close background clients', () {
      final source = File('lib/tdlib/td_client.dart').readAsStringSync();
      final setActiveStart = source.indexOf('  void setActive(int slot)');
      final removeSlotStart = source.indexOf('  void removeSlot(int slot)');
      final setActive = source.substring(setActiveStart, removeSlotStart);

      expect(setActive, isNot(contains("'@type': 'close'")));
      expect(setActive, contains('_activeClientId = cid'));
      expect(source, contains('retainAccountSlot(int accountSlot)'));
    });
  });
}
