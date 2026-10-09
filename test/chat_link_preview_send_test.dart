import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/link_preview_fixer.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _chatId = 42;

/// A TDLib `textEntity` over [text], used to keep a formatted span out of the
/// link scan.
Map<String, dynamic> _codeEntity(String text) => {
  '@type': 'textEntity',
  'offset': 0,
  'length': text.length,
  'type': {'@type': 'textEntityTypeCode'},
};

/// A TDLib `textEntity` hiding [url] behind the first [length] characters.
Map<String, dynamic> _textUrlEntity(int length, String url) => {
  '@type': 'textEntity',
  'offset': 0,
  'length': length,
  'type': {'@type': 'textEntityTypeTextUrl', 'url': url},
};

/// A TDLib `textEntity` marking [length] characters at [offset] as a link.
Map<String, dynamic> _urlEntity(int offset, int length) => {
  '@type': 'textEntity',
  'offset': offset,
  'length': length,
  'type': {'@type': 'textEntityTypeUrl'},
};

Map<String, dynamic> _preEntity(String text) => {
  '@type': 'textEntity',
  'offset': 0,
  'length': text.length,
  'type': {'@type': 'textEntityTypePre'},
};

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
          if (request['@type'] == 'sendMessage') {
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

  setUp(() async {
    requests = [];
    SharedPreferences.setMockInitialValues({});
    LinkPreviewFixer.shared.initialize(await SharedPreferences.getInstance());
  });

  tearDown(() async {
    SharedPreferences.setMockInitialValues({});
    await LinkPreviewFixer.shared.setEnabled(false);
  });

  Future<void> enableFixer() async {
    SharedPreferences.setMockInitialValues({
      LinkPreviewFixer.preferenceKey: true,
    });
    LinkPreviewFixer.shared.initialize(await SharedPreferences.getInstance());
  }

  ChatViewModel model() {
    final vm = ChatViewModel(
      chatId: _chatId,
      title: 'Preview',
      markReadOnOpen: false,
    );
    addTearDown(vm.dispose);
    return vm;
  }

  Map<String, dynamic> sentContent() {
    final sent = requests
        .where((request) => request['@type'] == 'sendMessage')
        .single;
    return Map<String, dynamic>.from(
      sent['input_message_content'] as Map<String, dynamic>,
    );
  }

  test(
    'an opted-in send keeps the text and points the preview at a mirror',
    () async {
      await enableFixer();
      final vm = model()..setDraft('看 https://x.com/user/status/1 这个');

      expect(await vm.send(), isTrue);

      final content = sentContent();
      expect(content['text'], {
        '@type': 'formattedText',
        'text': '看 https://x.com/user/status/1 这个',
      });
      expect(content['link_preview_options'], {
        '@type': 'linkPreviewOptions',
        'is_disabled': false,
        'url': 'https://fixupx.com/user/status/1',
      });
    },
  );

  test('a formatted send skips a link the sender put in code', () async {
    await enableFixer();
    const coded = 'https://x.com/user/status/1';
    final vm = model();

    expect(
      await vm.sendFormatted('$coded 以及 https://twitter.com/user/status/2', [
        _codeEntity(coded),
      ]),
      isTrue,
    );

    // The code span does not claim the preview slot, so the visible Twitter
    // link is the first one TDLib would preview — and it has a mirror.
    final content = sentContent();
    expect(content['link_preview_options'], {
      '@type': 'linkPreviewOptions',
      'is_disabled': false,
      'url': 'https://fxtwitter.com/user/status/2',
    });
  });

  test('a hidden first link keeps the preview it already has', () async {
    await enableFixer();
    const label = 'Read this';
    final vm = model();

    // The label is followed by a mirrorable link, but the sender's own first
    // link points somewhere with no rule. Moving the card to the mirror would
    // swap which page the message previews.
    expect(
      await vm.sendFormatted('$label https://x.com/a/status/1', [
        _textUrlEntity(label.length, 'https://example.test/article'),
      ]),
      isTrue,
    );

    expect(sentContent().containsKey('link_preview_options'), isFalse);
  });

  test('a hidden link with a rule gets the mirror', () async {
    await enableFixer();
    const label = 'Read this';
    final vm = model();

    expect(
      await vm.sendFormatted(label, [
        _textUrlEntity(label.length, 'https://x.com/a/status/1'),
      ]),
      isTrue,
    );

    final content = sentContent();
    // The text keeps the sender's label and its hidden target; only the fetched
    // preview moves.
    final sent = content['text'] as Map<String, dynamic>;
    expect(sent['text'], label);
    expect(
      (sent['entities'] as List<dynamic>).first,
      _textUrlEntity(label.length, 'https://x.com/a/status/1'),
    );
    expect(content['link_preview_options'], {
      '@type': 'linkPreviewOptions',
      'is_disabled': false,
      'url': 'https://fixupx.com/a/status/1',
    });
  });

  test('a label spelling a mirrorable link is not read as one', () async {
    await enableFixer();
    const label = 'x.com/a/status/1';
    final vm = model();

    expect(
      await vm.sendFormatted('$label and more words', [
        _textUrlEntity(label.length, 'https://example.test/doc'),
      ]),
      isTrue,
    );

    expect(sentContent().containsKey('link_preview_options'), isFalse);
  });

  test('a formatted send skips a link the sender put in a pre block', () async {
    await enableFixer();
    const coded = 'https://x.com/user/status/1';
    final vm = model();

    expect(
      await vm.sendFormatted('$coded 以及 https://twitter.com/user/status/2', [
        _preEntity(coded),
      ]),
      isTrue,
    );

    expect(sentContent()['link_preview_options'], {
      '@type': 'linkPreviewOptions',
      'is_disabled': false,
      'url': 'https://fxtwitter.com/user/status/2',
    });
  });

  test(
    'a link the sender marked as a url entity is the one previewed',
    () async {
      await enableFixer();
      const link = 'https://x.com/user/status/1';
      const text = 'see $link now';
      final vm = model();

      expect(
        await vm.sendFormatted(text, [_urlEntity('see '.length, link.length)]),
        isTrue,
      );

      expect(sentContent()['link_preview_options'], {
        '@type': 'linkPreviewOptions',
        'is_disabled': false,
        'url': 'https://fixupx.com/user/status/1',
      });
    },
  );

  test('a link without a rule sends no preview override', () async {
    await enableFixer();
    final vm = model()..setDraft('https://example.test/a 和 https://x.com/b');

    expect(await vm.send(), isTrue);

    expect(sentContent().containsKey('link_preview_options'), isFalse);
  });

  test('the override stays off until the reader opts in', () async {
    final vm = model()..setDraft('https://x.com/user/status/1');

    expect(await vm.send(), isTrue);

    expect(sentContent().containsKey('link_preview_options'), isFalse);
  });

  test('repeating a message applies the same rule', () async {
    await enableFixer();
    final vm = model();
    vm.repeatMessage(
      ChatMessage(
        id: 7,
        isOutgoing: false,
        date: 1,
        text: 'https://www.pixiv.net/en/artworks/1',
        contentType: 'messageText',
      ),
    );
    // A repeat is fire-and-forget: let the send land.
    await Future<void>.delayed(Duration.zero);

    expect(sentContent()['link_preview_options'], {
      '@type': 'linkPreviewOptions',
      'is_disabled': false,
      'url': 'https://www.phixiv.net/en/artworks/1',
    });
  });

  test('editing keeps its explicit options and adds the mirror', () async {
    await enableFixer();
    final vm = model();

    await vm.editMessageText(11, 'https://x.com/user/status/1');
    var edited = requests
        .where((request) => request['@type'] == 'editMessageText')
        .single;
    expect(edited['input_message_content'], {
      '@type': 'inputMessageText',
      'text': {'@type': 'formattedText', 'text': 'https://x.com/user/status/1'},
      'link_preview_options': {
        '@type': 'linkPreviewOptions',
        'is_disabled': false,
        'url': 'https://fixupx.com/user/status/1',
      },
      'clear_draft': false,
    });

    await LinkPreviewFixer.shared.setEnabled(false);
    await vm.editMessageText(12, 'https://x.com/user/status/1');
    edited = requests
        .where((request) => request['@type'] == 'editMessageText')
        .last;
    expect(
      (edited['input_message_content']
          as Map<String, dynamic>)['link_preview_options'],
      {'@type': 'linkPreviewOptions', 'is_disabled': false},
    );
  });

  test('every conversation send path routes through the fixer', () {
    // The request-level hook is exercised above; these pins keep a composer
    // funnel from silently dropping it. The forum topic and scheduled-message
    // surfaces build their own requests and have no cheaper seam to drive.
    String source(String path) => File(path).readAsStringSync();

    final chatViewModel = source('lib/chat/chat_view_model.dart');
    expect(chatViewModel, contains('LinkPreviewFixer.shared.applyTo(request)'));
    expect(chatViewModel, contains("'url': ?previewUrl,"));
    expect(
      source('lib/chat/message_replies_sheet.dart'),
      contains('LinkPreviewFixer.shared.optionsForFormattedText(text)'),
    );
    expect(
      source('lib/channels/topic_chat_view.dart'),
      contains('LinkPreviewFixer.shared.applyTo(request)'),
    );
    expect(
      source('lib/chat/scheduled_messages_view.dart'),
      contains('LinkPreviewFixer.shared.optionsFor(text)'),
    );
  });
}
