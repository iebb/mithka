//
//  rich_message_document_test.dart
//
//  Files attached to a rich channel post arrive as `pageBlockDocument` blocks.
//  Mithka had no case for them, so a post that Telegram shows as three files
//  above a collapsible screenshot appeared with the files missing entirely.
//

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/messages/message_bubble.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _text(String text) => {
  '@type': 'richTextPlain',
  'text': text,
};

Map<String, dynamic> _caption([String text = '']) => {
  '@type': 'pageBlockCaption',
  'text': _text(text),
  'credit': _text(''),
};

Map<String, dynamic> _document(int id, String name, int size) => {
  '@type': 'pageBlockDocument',
  'document': {
    '@type': 'document',
    'file_name': name,
    'mime_type': 'application/octet-stream',
    'document': {
      '@type': 'file',
      'id': id,
      'size': size,
      'expected_size': size,
      'local': {'@type': 'localFile', 'path': ''},
      'remote': {'@type': 'remoteFile', 'id': 'r$id', 'unique_id': 'u$id'},
    },
  },
  'caption': _caption(),
};

/// The shape of the reported post: three files, then a closed details block
/// with a screenshot inside, then an expandable quote.
Map<String, dynamic> _post() => {
  '@type': 'message',
  'id': 42 << 20,
  'chat_id': -1001234,
  'date': 1700000000,
  'is_outgoing': false,
  'is_channel_post': true,
  'sender_id': {'@type': 'messageSenderChat', 'chat_id': -1001234},
  'content': {
    '@type': 'messageRichMessage',
    'message': {
      '@type': 'richMessage',
      'is_rtl': false,
      'is_full': true,
      'blocks': [
        _document(901, 'telecom_1.2_rootless.deb', 367821),
        _document(902, 'telecom_1.2_hidden.deb', 367821),
        {
          ..._document(903, 'telecom_13.5.ipa', 391747174),
          'caption': _caption('shared by a member'),
        },
        {
          '@type': 'pageBlockDetails',
          'header': _text('Screenshot preview, tap to view'),
          'is_open': false,
          'blocks': [
            {
              '@type': 'pageBlockParagraph',
              'text': _text('inside the details'),
            },
          ],
        },
        {
          '@type': 'pageBlockExpandableBlockQuote',
          'blocks': [
            {
              '@type': 'pageBlockParagraph',
              'text': _text('an expandable quote'),
            },
          ],
          'credit': _text(''),
        },
      ],
    },
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('document and expandable quote blocks are parsed', () {
    final message = TDParse.message(_post())!;
    final kinds = message.richBlocks.map((block) => block.kind).toList();
    expect(kinds, [
      RichMessageBlockKind.document,
      RichMessageBlockKind.document,
      RichMessageBlockKind.document,
      RichMessageBlockKind.details,
      RichMessageBlockKind.blockQuote,
    ]);
    final ipa = message.richBlocks[2];
    expect(ipa.document?.fileName, 'telecom_13.5.ipa');
    expect(ipa.document?.ext, 'IPA');
    expect(ipa.document?.size, 391747174);
    expect(ipa.document?.file?.id, 903);
    expect(ipa.caption, 'shared by a member');
    expect(message.richBlocks[4].children.single.text, 'an expandable quote');
  });

  test('a captionless file is still named in the plain text', () {
    final text = TDParse.messageText(_post()['content']);
    expect(text, contains('telecom_1.2_rootless.deb'));
    expect(text, contains('shared by a member'));
  });

  testWidgets('the files render as one card above the details block', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);
    final message = TDParse.message(_post())!;

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: SingleChildScrollView(
              child: MessageBubble(
                message: message,
                peerTitle: 'Channel',
                isGroup: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    for (final name in [
      'telecom_1.2_rootless.deb',
      'telecom_1.2_hidden.deb',
      'telecom_13.5.ipa',
    ]) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(find.text('374 MB'), findsOneWidget);
    expect(find.text('359 KB'), findsNWidgets(2));
    expect(find.text('shared by a member', findRichText: true), findsOneWidget);

    // One card holds all three consecutive files.
    final card = find.byKey(const ValueKey('rich-message-block-0-document'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('telecom_13.5.ipa')),
      findsOneWidget,
    );

    // The files sit above the details block, as in the post.
    expect(
      tester.getTopLeft(find.text('telecom_13.5.ipa')).dy,
      lessThan(
        tester
            .getTopLeft(
              find.text('Screenshot preview, tap to view', findRichText: true),
            )
            .dy,
      ),
    );
    expect(
      find.text('an expandable quote', findRichText: true),
      findsOneWidget,
    );
  });
}
