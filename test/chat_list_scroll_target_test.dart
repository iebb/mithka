import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view.dart';

void main() {
  test('unread chat scroll target does not accumulate phantom separators', () {
    expect(
      chatListItemScrollOffset(
        itemIndex: 32,
        rowHeight: 72,
        maxScrollExtent: 10000,
      ),
      2304,
    );
  });

  test('unread chat scroll target stays within the list extent', () {
    expect(
      chatListItemScrollOffset(
        itemIndex: 32,
        rowHeight: 72,
        maxScrollExtent: 1800,
      ),
      1800,
    );
  });

  test(
    'unread chat scroll target includes a scrollable leading search item',
    () {
      expect(
        chatListItemScrollOffset(
          itemIndex: 4,
          rowHeight: 72,
          leadingExtent: 56,
          maxScrollExtent: 10000,
        ),
        344,
      );
    },
  );
}
