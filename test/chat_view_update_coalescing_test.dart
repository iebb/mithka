import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view.dart';

void main() {
  test('net-zero hidden updates still reconcile transcript boundaries', () {
    expect(
      chatTranscriptBoundaryChanged(
        previousCount: 20,
        currentCount: 20,
        previousNewestMessageId: 120,
        currentNewestMessageId: 121,
        previousOldestMessageId: 80,
        currentOldestMessageId: 81,
        hasBufferedLiveMessages: true,
      ),
      isTrue,
    );
  });

  test('unchanged hidden transcript does not request redundant work', () {
    expect(
      chatTranscriptBoundaryChanged(
        previousCount: 20,
        currentCount: 20,
        previousNewestMessageId: 120,
        currentNewestMessageId: 120,
        previousOldestMessageId: 80,
        currentOldestMessageId: 80,
        hasBufferedLiveMessages: false,
      ),
      isFalse,
    );
  });
}
