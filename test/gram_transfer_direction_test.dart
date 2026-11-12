import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/tdlib/message_gram_transfer.dart';

const _meId = 7;
const _peerId = 42;

MessageGramTransfer _transfer({
  required int senderUserId,
  required int amount,
  String comment = '',
}) => MessageGramTransfer(
  senderUserId: senderUserId,
  transactionId: '',
  peerAddress: 'UQAbcdefghijklmnopqrstuvwxyz0123456789',
  amount: amount,
  comment: comment,
  isCommentEncrypted: false,
);

void main() {
  test('the message direction decides, not the sender or the amount', () {
    // TDLib has delivered a transfer the current user sent with a positive
    // amount and the recipient as its sender.
    final sent = _transfer(senderUserId: _peerId, amount: 100000000);
    expect(sent.isOutgoing(messageOutgoing: true), isTrue);
    expect(
      sent.state(messageOutgoing: true, isSending: false),
      GramTransferState.sending,
    );

    final received = _transfer(senderUserId: _meId, amount: -100000000);
    expect(received.isOutgoing(messageOutgoing: false), isFalse);
    expect(
      received.state(messageOutgoing: false, isSending: false),
      GramTransferState.received,
    );
  });
}
