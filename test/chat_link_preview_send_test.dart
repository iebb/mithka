import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/link_preview_fixer.dart';
import 'package:mithka/tdlib/td_client.dart';
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

  test('the override stays off until the reader opts in', () async {
    final vm = model()..setDraft('https://x.com/user/status/1');

    expect(await vm.send(), isTrue);

    expect(sentContent().containsKey('link_preview_options'), isFalse);
  });
}
