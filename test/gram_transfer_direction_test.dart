import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/details_card.dart';
import 'package:mithka/chat/gram_transfer_sheet.dart';
import 'package:mithka/chat/message_gram_envelope.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/message_gram_transfer.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

Future<void> _pumpSheet(
  WidgetTester tester,
  MessageGramTransfer transfer, {
  required bool outgoing,
}) async {
  SharedPreferences.setMockInitialValues({});
  final theme = ThemeController(await SharedPreferences.getInstance());
  addTearDown(theme.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: GramTransferSheet(
            transfer: transfer,
            state: transfer.state(messageOutgoing: outgoing, isSending: false),
            outgoing: transfer.isOutgoing(messageOutgoing: outgoing),
            date: 0,
            me: const GramTransferParty(name: 'Me'),
            meId: _meId,
            sender: outgoing ? null : const GramTransferParty(name: 'Hualin'),
            chatPeer: const GramTransferParty(name: 'Hualin'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Map<String, String?> _parties(WidgetTester tester) => {
  for (final row in tester.widgetList<DetailsRow>(find.byType(DetailsRow)))
    row.label: row.semanticValue,
};

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

  test('without a message direction the amount sign decides', () {
    expect(
      _transfer(senderUserId: 0, amount: -1).isOutgoing(messageOutgoing: null),
      isTrue,
    );
    expect(
      _transfer(senderUserId: 0, amount: 1).isOutgoing(messageOutgoing: null),
      isFalse,
    );
  });

  testWidgets('an outgoing positive transfer is from me to the peer', (
    tester,
  ) async {
    await _pumpSheet(
      tester,
      _transfer(senderUserId: _peerId, amount: 100000000),
      outgoing: true,
    );
    expect(_parties(tester), containsPair('From', 'Me'));
    expect(_parties(tester), containsPair('To', 'Hualin'));
    expect(find.text('Transfer to Hualin'), findsOneWidget);
  });

  testWidgets('an incoming transfer is from the peer to me', (tester) async {
    await _pumpSheet(
      tester,
      _transfer(senderUserId: _peerId, amount: 100000000, comment: 'Tea'),
      outgoing: false,
    );
    expect(_parties(tester), containsPair('From', 'Hualin'));
    expect(_parties(tester), containsPair('To', 'Me'));
    expect(find.text('Transfer from Hualin'), findsOneWidget);
  });
}
