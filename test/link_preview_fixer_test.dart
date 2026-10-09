import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/link_preview_fixer.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

MessageTextEntity _code(int offset, int length) => MessageTextEntity(
  offset: offset,
  length: length,
  type: 'textEntityTypeCode',
);

/// A `TextUrl` entity hiding [url] behind [length] characters at [offset].
MessageTextEntity _textUrl(int offset, int length, String url) =>
    MessageTextEntity(
      offset: offset,
      length: length,
      type: 'textEntityTypeTextUrl',
      url: url,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    // The fixer is a process-wide singleton: leave it off for the next test.
    SharedPreferences.setMockInitialValues({});
    await LinkPreviewFixer.shared.setEnabled(false);
  });

  group('fixedUrl', () {
    test('moves known hosts to their mirror and keeps the path', () {
      expect(
        LinkPreviewFixer.fixedUrl('https://x.com/user/status/1'),
        'https://fixupx.com/user/status/1',
      );
      expect(
        LinkPreviewFixer.fixedUrl('https://twitter.com/user/status/1'),
        'https://fxtwitter.com/user/status/1',
      );
      expect(
        LinkPreviewFixer.fixedUrl('https://vm.tiktok.com/ZMabc/'),
        'https://vm.vxtiktok.com/ZMabc/',
      );
      expect(
        LinkPreviewFixer.fixedUrl('https://www.instagram.com/p/xyz/'),
        'https://ddinstagram.com/p/xyz/',
      );
      expect(
        LinkPreviewFixer.fixedUrl('https://www.reddit.com/r/a/comments/1/'),
        'https://www.vxreddit.com/r/a/comments/1/',
      );
      expect(
        LinkPreviewFixer.fixedUrl('https://bsky.app/profile/a/post/1'),
        'https://fxbsky.app/profile/a/post/1',
      );
      expect(
        LinkPreviewFixer.fixedUrl('https://www.pixiv.net/en/artworks/1'),
        'https://www.phixiv.net/en/artworks/1',
      );
      expect(
        LinkPreviewFixer.fixedUrl('https://www.miyoushe.com/ys/article/1'),
        'https://www.miyoushe.pp.ua/ys/article/1',
      );
      expect(
        LinkPreviewFixer.fixedUrl('https://m.miyoushe.com/ys/article/1'),
        'https://www.miyoushe.pp.ua/ys/article/1',
      );
      expect(
        LinkPreviewFixer.fixedUrl('https://www.hoyolab.com/article/1'),
        'https://www.hoyolab.pp.ua/article/1',
      );
      expect(
        LinkPreviewFixer.fixedUrl('https://www.coolapk.com/feed/1'),
        'https://coolapk1s.com/feed/1',
      );
    });

    test('accepts a bare host and an http link, and normalizes both', () {
      expect(
        LinkPreviewFixer.fixedUrl('x.com/user/status/1'),
        'https://fixupx.com/user/status/1',
      );
      expect(
        LinkPreviewFixer.fixedUrl('http://x.com/user/status/1'),
        'https://fixupx.com/user/status/1',
      );
      expect(
        LinkPreviewFixer.fixedUrl('HTTPS://X.COM/User/Status'),
        'https://fixupx.com/User/Status',
      );
      expect(LinkPreviewFixer.fixedUrl('https://x.com'), 'https://fixupx.com');
    });

    test('drops the query and the fragment', () {
      expect(
        LinkPreviewFixer.fixedUrl('https://x.com/a/status/1?s=20&t=share'),
        'https://fixupx.com/a/status/1',
      );
      expect(
        LinkPreviewFixer.fixedUrl('https://www.pixiv.net/artworks/1#anchor'),
        'https://www.phixiv.net/artworks/1',
      );
    });

    test('never carries credentials to a mirror', () {
      expect(
        LinkPreviewFixer.fixedUrl('https://reader:secret@x.com/a/status/1'),
        'https://fixupx.com/a/status/1',
      );
    });

    test('leaves unknown hosts alone', () {
      expect(LinkPreviewFixer.fixedUrl('https://example.com/x.com'), isNull);
      expect(LinkPreviewFixer.fixedUrl('https://notx.com/a'), isNull);
      expect(LinkPreviewFixer.fixedUrl(''), isNull);
      expect(LinkPreviewFixer.fixedUrl('ftp://x.com/a'), isNull);
      expect(LinkPreviewFixer.fixedUrl('mailto:someone@x.com'), isNull);
    });

    test('matches the host only, never a lookalike or a query value', () {
      expect(LinkPreviewFixer.fixedUrl('https://x.com.evil.test/a'), isNull);
      expect(LinkPreviewFixer.fixedUrl('https://evil.test/x.com/a'), isNull);
      expect(
        LinkPreviewFixer.fixedUrl('https://evil.test/?next=https://x.com/a'),
        isNull,
      );
      expect(LinkPreviewFixer.fixedUrl('https://fixupx.com/x.com'), isNull);
    });

    test('skips a non-default port instead of pointing it at a mirror', () {
      expect(LinkPreviewFixer.fixedUrl('https://x.com:8080/a'), isNull);
      expect(
        LinkPreviewFixer.fixedUrl('https://x.com:443/a'),
        'https://fixupx.com/a',
      );
    });
  });

  group('trimmedUrl', () {
    test('stops at the sentence around the link', () {
      expect(
        LinkPreviewFixer.trimmedUrl('https://x.com/a。'),
        'https://x.com/a',
      );
      expect(
        LinkPreviewFixer.trimmedUrl('https://x.com/a, then more'),
        'https://x.com/a',
      );
      expect(
        LinkPreviewFixer.trimmedUrl('https://x.com/a?b=1&c=2'),
        'https://x.com/a?b=1&c=2',
      );
    });

    test('keeps a balanced bracket and drops an unbalanced one', () {
      expect(
        LinkPreviewFixer.trimmedUrl('https://x.com/a_(b)'),
        'https://x.com/a_(b)',
      );
      expect(
        LinkPreviewFixer.trimmedUrl('https://x.com/a)'),
        'https://x.com/a',
      );
    });

    test('stops at a quote or an angle bracket', () {
      expect(
        LinkPreviewFixer.trimmedUrl('https://x.com/a"'),
        'https://x.com/a',
      );
      expect(
        LinkPreviewFixer.trimmedUrl('https://x.com/a>next'),
        'https://x.com/a',
      );
    });
  });

  group('firstPreviewableUrl', () {
    test('finds the first link, schemed or bare', () {
      expect(
        LinkPreviewFixer.firstPreviewableUrl('看 https://x.com/a/status/1 这个'),
        'https://x.com/a/status/1',
      );
      expect(
        LinkPreviewFixer.firstPreviewableUrl('x.com/a/status/1 和 y.test/b'),
        'x.com/a/status/1',
      );
      expect(LinkPreviewFixer.firstPreviewableUrl('没有链接'), isNull);
      expect(LinkPreviewFixer.firstPreviewableUrl(''), isNull);
    });

    test('keeps the first link even when a later one has a rule', () {
      // TDLib previews one page: the first URL. Fixing a later link would swap
      // which page the card shows, so it must not happen.
      expect(
        LinkPreviewFixer.firstPreviewableUrl(
          'https://example.test/a 和 https://x.com/b',
        ),
        'https://example.test/a',
      );
      expect(LinkPreviewFixer.fixedUrl('https://example.test/a'), isNull);
      expect(
        LinkPreviewFixer.firstPreviewableUrl('file.txt 里写着 x.com/a'),
        'file.txt',
      );
    });

    test('does not read a link out of an address or a version', () {
      expect(LinkPreviewFixer.firstPreviewableUrl('bob@x.com'), isNull);
      expect(LinkPreviewFixer.firstPreviewableUrl('版本 1.2.3 发布了'), isNull);
    });

    test('ignores links inside code spans', () {
      const text = '`https://example.test/a` https://x.com/b';
      expect(
        LinkPreviewFixer.firstPreviewableUrl(
          text,
          entities: [_code(0, '`https://example.test/a`'.length)],
        ),
        'https://x.com/b',
      );
      const only = 'https://x.com/b';
      expect(
        LinkPreviewFixer.firstPreviewableUrl(
          only,
          entities: [_code(0, only.length)],
        ),
        isNull,
      );
    });

    test('ignores entities that are not code', () {
      const text = 'https://x.com/a';
      expect(
        LinkPreviewFixer.firstPreviewableUrl(
          text,
          entities: [
            const MessageTextEntity(
              offset: 0,
              length: text.length,
              type: 'textEntityTypeBold',
            ),
          ],
        ),
        text,
      );
    });

    test('a hidden link is the link, not the label', () {
      // TDLib previews the target a TextUrl points at, so the target is what
      // decides whether a mirror applies — the label is decoration.
      const text = 'Read this';
      expect(
        LinkPreviewFixer.firstPreviewableUrl(
          text,
          entities: [_textUrl(0, text.length, 'https://x.com/a/status/1')],
        ),
        'https://x.com/a/status/1',
      );
    });

    test('the first link wins even when it is hidden', () {
      const text = 'Read this https://x.com/a/status/1';
      expect(
        LinkPreviewFixer.firstPreviewableUrl(
          text,
          entities: [_textUrl(0, 'Read this'.length, 'https://example.test/a')],
        ),
        'https://example.test/a',
      );
    });

    test('a label spelling an unrelated link is never scanned', () {
      // The label looks like the mirrorable link; the target does not. Reading
      // the label would move the card to a page the sender never linked.
      const label = 'x.com/a/status/1';
      const text = '$label and more words';
      expect(
        LinkPreviewFixer.firstPreviewableUrl(
          text,
          entities: [_textUrl(0, label.length, 'https://example.test/doc')],
        ),
        'https://example.test/doc',
      );
      // And with no target at all, the label contributes nothing.
      expect(
        LinkPreviewFixer.firstPreviewableUrl(
          text,
          entities: [_textUrl(0, label.length, '')],
        ),
        isNull,
      );
    });

    test('walks past a hidden target that is not a web link', () {
      const text = 'ton://site https://x.com/a/status/1';
      expect(
        LinkPreviewFixer.firstPreviewableUrl(
          text,
          entities: [_textUrl(0, 'ton://site'.length, 'tonsite://example')],
        ),
        'https://x.com/a/status/1',
      );
    });

    test('a url entity contributes its own slice', () {
      const link = 'https://x.com/a/status/1';
      const text = 'see $link now';
      expect(
        LinkPreviewFixer.firstPreviewableUrl(
          text,
          entities: const [
            MessageTextEntity(
              offset: 'see '.length,
              length: link.length,
              type: 'textEntityTypeUrl',
            ),
          ],
        ),
        link,
      );
      // TDLib skips a `Url` entity too short to hold a link, and keeps walking.
      expect(
        LinkPreviewFixer.firstPreviewableUrl(
          'x.y $link',
          entities: const [
            MessageTextEntity(offset: 0, length: 3, type: 'textEntityTypeUrl'),
          ],
        ),
        link,
      );
    });

    test('ignores links inside pre and quote spans', () {
      const coded = 'https://x.com/a';
      const text = '$coded https://twitter.com/b';
      for (final type in const [
        'textEntityTypePre',
        'textEntityTypePreCode',
        'textEntityTypeBlockQuote',
      ]) {
        expect(
          LinkPreviewFixer.firstPreviewableUrl(
            text,
            entities: [
              MessageTextEntity(offset: 0, length: coded.length, type: type),
            ],
          ),
          'https://twitter.com/b',
          reason: type,
        );
      }
    });
  });

  group('preference', () {
    test(
      'stays off until the reader opts in, and the choice persists',
      () async {
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        final fixer = LinkPreviewFixer.shared;
        fixer.initialize(preferences);
        expect(fixer.enabled, isFalse);
        expect(fixer.previewUrl('https://x.com/a'), isNull);
        expect(fixer.optionsFor('https://x.com/a'), isNull);

        var notifications = 0;
        void countNotifications() => notifications++;
        fixer.addListener(countNotifications);
        await fixer.setEnabled(true);
        fixer.removeListener(countNotifications);
        expect(notifications, 1);
        expect(fixer.enabled, isTrue);
        expect(preferences.getBool(LinkPreviewFixer.preferenceKey), isTrue);

        // A second initialize reads the stored choice back.
        fixer.initialize(preferences);
        expect(fixer.enabled, isTrue);
      },
    );

    test('only answers for a link that has a rule', () async {
      SharedPreferences.setMockInitialValues({
        LinkPreviewFixer.preferenceKey: true,
      });
      final fixer = LinkPreviewFixer.shared;
      fixer.initialize(await SharedPreferences.getInstance());
      expect(fixer.previewUrl('https://x.com/a'), 'https://fixupx.com/a');
      expect(fixer.optionsFor('https://x.com/a'), {
        '@type': 'linkPreviewOptions',
        'is_disabled': false,
        'url': 'https://fixupx.com/a',
      });
      expect(fixer.previewUrl('https://example.test/a'), isNull);
      expect(fixer.optionsFor('没有链接'), isNull);
    });
  });

  group('applyTo', () {
    Map<String, dynamic> textRequest(String text) => {
      '@type': 'sendMessage',
      'chat_id': 7,
      'input_message_content': {
        '@type': 'inputMessageText',
        'text': {'@type': 'formattedText', 'text': text},
      },
    };

    Future<LinkPreviewFixer> optedIn() async {
      SharedPreferences.setMockInitialValues({
        LinkPreviewFixer.preferenceKey: true,
      });
      return LinkPreviewFixer.shared
        ..initialize(await SharedPreferences.getInstance());
    }

    test(
      'points a text send at the mirror and leaves the request otherwise',
      () async {
        final fixer = await optedIn();
        final request = textRequest('看 https://x.com/a/status/1 这个');

        final fixed = fixer.applyTo(request);

        expect(fixed['@type'], 'sendMessage');
        expect(fixed['chat_id'], 7);
        final content = fixed['input_message_content'] as Map<String, dynamic>;
        expect(content['text'], {
          '@type': 'formattedText',
          'text': '看 https://x.com/a/status/1 这个',
        });
        expect(content['link_preview_options'], {
          '@type': 'linkPreviewOptions',
          'is_disabled': false,
          'url': 'https://fixupx.com/a/status/1',
        });
        // The caller's map is not edited in place.
        expect(
          (request['input_message_content'] as Map<String, dynamic>)
              .containsKey('link_preview_options'),
          isFalse,
        );
      },
    );

    test('keeps options the caller already chose', () async {
      final fixer = await optedIn();
      final request = textRequest('https://x.com/a/status/1');
      (request['input_message_content']
          as Map<String, dynamic>)['link_preview_options'] = {
        '@type': 'linkPreviewOptions',
        'is_disabled': true,
      };

      expect(fixer.applyTo(request), request);
    });

    test('leaves a caption and a link without a rule alone', () async {
      final fixer = await optedIn();
      final photo = <String, dynamic>{
        '@type': 'sendMessage',
        'chat_id': 7,
        'input_message_content': {
          '@type': 'inputMessagePhoto',
          'photo': {'@type': 'inputFileLocal', 'path': '/tmp/a.jpg'},
          'caption': {'@type': 'formattedText', 'text': 'https://x.com/a'},
        },
      };

      expect(fixer.applyTo(photo), photo);
      expect(
        (fixer.applyTo(
                  textRequest('https://example.test/a'),
                )['input_message_content']
                as Map<String, dynamic>)
            .containsKey('link_preview_options'),
        isFalse,
      );
    });

    test('does nothing while the reader has not opted in', () async {
      SharedPreferences.setMockInitialValues({});
      final fixer = LinkPreviewFixer.shared
        ..initialize(await SharedPreferences.getInstance());
      final request = textRequest('https://x.com/a/status/1');

      expect(fixer.applyTo(request), request);
    });
  });
}
