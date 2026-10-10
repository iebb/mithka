import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/message_text_quote.dart';
import 'package:mithka/chat/outgoing_attachment.dart';
import 'package:mithka/chat/pangu_spacing.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';

/// The text TDLib was asked to store, whether it rides a message body or a
/// media caption.
String outgoingText(Map<String, dynamic> request) {
  final content = (request['input_message_content'] as Map)
      .cast<String, dynamic>();
  final text = (content['text'] ?? content['caption']) as Map;
  return text['text'] as String;
}

List<Map<String, dynamic>> outgoingEntities(Map<String, dynamic> request) {
  final content = (request['input_message_content'] as Map)
      .cast<String, dynamic>();
  final text = (content['text'] ?? content['caption']) as Map;
  return (text['entities'] as List? ?? const [])
      .cast<Map>()
      .map((entity) => entity.cast<String, dynamic>())
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<Map<String, dynamic>> requests;

  setUpAll(() {
    // In-memory transport only: these tests never touch a Telegram account.
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          requests.add(request);
          if (request['@type'] == 'sendMessage' ||
              request['@type'] == 'sendMessageAlbum') {
            return {'@type': 'message', 'id': 99};
          }
          return {'@type': 'ok'};
        },
        send: (_) async {},
        updates: const Stream.empty(),
      ),
    );
  });
  tearDownAll(TdClient.shared.closeProxy);
  setUp(() => requests = []);

  ChatViewModel model({bool send = false, bool edit = false}) {
    final vm = ChatViewModel(chatId: 42, title: 'Pangu', markReadOnOpen: false)
      ..panguOnSend = send
      ..panguOnEdit = edit;
    addTearDown(vm.dispose);
    return vm;
  }

  Map<String, dynamic> sent([String type = 'sendMessage']) =>
      requests.where((request) => request['@type'] == type).single;

  test('a draft keeps its own spacing while the switch is off', () async {
    final vm = model()..setDraft('中文English');
    expect(await vm.send(), isTrue);
    expect(outgoingText(sent()), '中文English');
  });

  test('a spaced draft goes out with one space per boundary', () async {
    final vm = model(send: true)..setDraft('中文English中文100');
    expect(await vm.send(), isTrue);
    expect(outgoingText(sent()), '中文 English 中文 100');
  });

  test('formatted text moves its entities onto the spaced text', () async {
    final vm = model(send: true);
    final ok = await vm.sendFormatted('中文code中文', [
      {
        '@type': 'textEntity',
        'offset': 2,
        'length': 4,
        'type': {'@type': 'textEntityTypeCode'},
      },
    ]);
    expect(ok, isTrue);
    final request = sent();
    final text = outgoingText(request);
    expect(text, '中文 code 中文');
    final entities = outgoingEntities(request);
    expect(entities, hasLength(1));
    final offset = entities.single['offset'] as int;
    final length = entities.single['length'] as int;
    expect(offset, 3);
    expect(length, 4);
    expect(text.substring(offset, offset + length), 'code');
  });

  test('a formatting entity grows over an insertion inside it', () async {
    final vm = model(send: true);
    final ok = await vm.sendFormatted('中文English中文', [
      {
        '@type': 'textEntity',
        'offset': 0,
        'length': 9,
        'type': {'@type': 'textEntityTypeBold'},
      },
    ]);
    expect(ok, isTrue);
    final request = sent();
    final text = outgoingText(request);
    expect(text, '中文 English 中文');
    final entities = outgoingEntities(request);
    final offset = entities.single['offset'] as int;
    final length = entities.single['length'] as int;
    expect(offset, 0);
    expect(length, 10);
    expect(text.substring(offset, offset + length), '中文 English');
  });

  test('a media caption is spaced like a body', () async {
    final vm = model(send: true);
    await vm.sendAttachments(const [
      OutgoingAttachment(
        path: '/synthetic/a.jpg',
        kind: OutgoingAttachmentKind.photo,
      ),
    ], caption: '中文photo');
    expect(outgoingText(sent()), '中文 photo');
  });

  // A caption typed by hand carries no entities, so the only thing standing
  // between 盘古之白 and a rewritten link is the detector. TDLib adds the `Url`
  // entity after the message is sent, and a space inside it changes the target
  // rather than how it reads.
  test('a caption keeps a link whose path mixes scripts', () async {
    final vm = model(send: true);
    const caption = 'https://example.com/中文abc';
    await vm.sendAttachments(const [
      OutgoingAttachment(
        path: '/synthetic/a.jpg',
        kind: OutgoingAttachmentKind.photo,
      ),
    ], caption: caption);
    expect(outgoingText(sent()), caption);
  });

  test('a link keeps its query values and is spaced into the sentence', () async {
    final vm = model(send: true)..setDraft('看https://example.com/a?q=中文abc');
    expect(await vm.send(), isTrue);
    // The space before the link is outside it, so it stays. TDLib's path runs to
    // the next whitespace, so whatever follows the query is part of the link and
    // cannot be spaced off it.
    expect(outgoingText(sent()), '看 https://example.com/a?q=中文abc');
  });

  test('an address keeps its local part', () async {
    final vm = model(send: true)..setDraft('寄到mail@example.com谢谢');
    expect(await vm.send(), isTrue);
    expect(outgoingText(sent()), '寄到 mail@example.com 谢谢');
  });

  test('a mention is spaced around, never inside', () async {
    final vm = model(send: true)..setDraft('中文@username中文');
    expect(await vm.send(), isTrue);
    // `@` is not a half-width letter, so nothing lands in front of the mention;
    // the space after it sits on the token's edge, outside the protected range.
    expect(outgoingText(sent()), '中文@username 中文');
  });

  test('a hashtag keeps its whole token', () async {
    final vm = model(send: true)..setDraft('话题#中文tag结束');
    expect(await vm.send(), isTrue);
    // TDLib reads a hashtag to the end of its letters, whatever script they are
    // in, so spacing the CJK off the tag would make it two tokens.
    expect(outgoingText(sent()), '话题#中文tag结束');
  });

  test('a command is spaced after its name, not inside it', () async {
    final vm = model(send: true)..setDraft('/help中文');
    expect(await vm.send(), isTrue);
    expect(outgoingText(sent()), '/help 中文');
  });

  test(
    'a detected link and a formatting entity agree on the offsets',
    () async {
      final vm = model(send: true);
      const text = '中文https://example.com/中文abc';
      expect(
        await vm.sendFormatted(text, [
          {
            '@type': 'textEntity',
            'offset': 0,
            'length': text.length,
            'type': {'@type': 'textEntityTypeBold'},
          },
        ]),
        isTrue,
      );
      final request = sent();
      final spaced = outgoingText(request);
      expect(spaced, '中文 https://example.com/中文abc');
      final entity = outgoingEntities(request).single;
      final offset = entity['offset'] as int;
      final length = entity['length'] as int;
      expect(offset, 0);
      expect(spaced.substring(offset, offset + length), spaced);
    },
  );

  // A quote addresses what the author stored, never what the bubble painted, so
  // a selection made in 盘古之白 offsets is mapped back before the payload is
  // built — otherwise the quoted link goes out with a space nobody typed.
  test('a quote taken off the spaced display keeps the stored bytes', () async {
    const link = 'https://example.com/中文abc';
    const stored = '中文English看$link';
    final source = ChatMessage(
      id: 11,
      isOutgoing: false,
      date: 1,
      contentType: 'messageText',
      text: stored,
      textEntities: [
        const MessageTextEntity(
          offset: 2,
          length: 7,
          type: 'textEntityTypeBold',
        ),
        MessageTextEntity(
          offset: stored.indexOf(link),
          length: link.length,
          type: 'textEntityTypeUrl',
        ),
      ],
    );
    final painted = PanguSpacing.display(stored, source.textEntities);
    expect(painted.text, '中文 English 看 $link');

    MessageTextQuote? quoteFromPainted(int start, int end) {
      final mapped = PanguSpacing.reverseRange(
        start: start,
        end: end,
        insertedOffsets: painted.insertedOffsets,
        sourceLength: stored.length,
      );
      return quoteMessageRange(source, start: mapped.start, end: mapped.end);
    }

    // Across an inserted space: the words are quoted, the space is not, and the
    // bold entity keeps the offsets it has in the stored text.
    final word = painted.text.indexOf('English');
    final across = quoteFromPainted(word, word + 'English 看'.length);
    expect(across?.text, 'English看');
    expect(across?.position, stored.indexOf('English'));
    expect(across?.entities.single.type, 'textEntityTypeBold');
    expect(across?.entities.single.offset, 0);
    expect(across?.entities.single.length, 'English'.length);

    // A selection starting on the space in front of a mixed-script link still
    // quotes exactly the link; TDLib keeps no link entity inside a quote.
    final at = painted.text.indexOf('https://');
    final whole = quoteFromPainted(at - 1, at + link.length);
    expect(whole?.text, link);
    expect(whole?.position, stored.indexOf(link));
    expect(whole?.entities, isEmpty);

    final vm = model(send: true)
      ..setReply(source, quote: whole)
      ..setDraft('回复中文English');
    expect(await vm.send(), isTrue);
    final request = sent();
    expect(outgoingText(request), '回复中文 English');
    final replyTo = (request['reply_to'] as Map).cast<String, dynamic>();
    expect(replyTo['message_id'], 11);
    final sentQuote = (replyTo['quote'] as Map).cast<String, dynamic>();
    expect(sentQuote['position'], stored.indexOf(link));
    final quoted = (sentQuote['text'] as Map).cast<String, dynamic>();
    expect(quoted['text'], link);
    expect(quoted['entities'], isEmpty);
  });

  test('a link is left byte-identical while the switch is off', () async {
    final vm = model()..setDraft('看https://example.com/中文abc和mail@example.com');
    expect(await vm.send(), isTrue);
    expect(outgoingText(sent()), '看https://example.com/中文abc和mail@example.com');
  });

  test('editing spaces only when the edit switch is on', () async {
    final message = ChatMessage(
      id: 7,
      isOutgoing: true,
      date: 1,
      contentType: 'messageText',
      text: '中文English',
    );

    final sendOnly = model(send: true)..beginMessageEdit(message);
    expect(await sendOnly.submitMessageEdit('中文English'), isTrue);
    expect(outgoingText(sent('editMessageText')), '中文English');

    requests.clear();
    final both = model(send: true, edit: true)..beginMessageEdit(message);
    expect(await both.submitMessageEdit('中文English'), isTrue);
    expect(outgoingText(sent('editMessageText')), '中文 English');
  });

  test('editing a caption spaces the caption payload', () async {
    final message = ChatMessage(
      id: 8,
      isOutgoing: true,
      date: 1,
      contentType: 'messagePhoto',
      text: '中文photo',
      image: TdFileRef(id: 3),
    );
    final vm = model(edit: true)..beginMessageEdit(message);
    expect(await vm.submitMessageEdit('中文photo'), isTrue);
    final request = sent('editMessageCaption');
    final caption = (request['caption'] as Map).cast<String, dynamic>();
    expect(caption['text'], '中文 photo');
  });

  test('a dice emoji is still sent as a dice', () async {
    final vm = model(send: true);
    expect(await vm.sendFormatted('🎲', const []), isTrue);
    final request = sent();
    final content = (request['input_message_content'] as Map)
        .cast<String, dynamic>();
    expect(content['@type'], 'inputMessageDice');
  });
  test('plain CJK text is left alone', () async {
    final vm = model(send: true)..setDraft('今天天气不错');
    expect(await vm.send(), isTrue);
    expect(outgoingText(sent()), '今天天气不错');
  });
}
