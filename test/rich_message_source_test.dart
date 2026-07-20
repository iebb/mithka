import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/outgoing_attachment.dart';
import 'package:mithka/chat/rich_message_source.dart';

void main() {
  String repeated(String value, int count) => List.filled(count, value).join();

  group('telegramMessageLengthTier', () {
    test('uses the standard and rich message boundaries', () {
      expect(
        telegramMessageLengthTier(repeated('a', 4096)),
        TelegramMessageLengthTier.standard,
      );
      expect(
        telegramMessageLengthTier(repeated('a', 4097)),
        TelegramMessageLengthTier.rich,
      );
      expect(
        telegramMessageLengthTier(repeated('a', 32768)),
        TelegramMessageLengthTier.rich,
      );
      expect(
        telegramMessageLengthTier(repeated('a', 32769)),
        TelegramMessageLengthTier.exceeded,
      );
    });

    test('counts Unicode characters instead of UTF-8 bytes', () {
      expect(telegramUtf8CharacterCount(repeated('界', 4096)), 4096);
      expect(
        telegramMessageLengthTier(repeated('界', 4096)),
        TelegramMessageLengthTier.standard,
      );
      expect(
        telegramMessageLengthTier(repeated('界', 4097)),
        TelegramMessageLengthTier.rich,
      );
    });
  });

  group('richMessageFilePayload', () {
    test('preserves photo dimensions and local path', () {
      final payload = richMessageFilePayload(
        const RichMessageSendFile(
          id: 'photo-1',
          attachment: OutgoingAttachment(
            path: '/tmp/photo.jpg',
            kind: OutgoingAttachmentKind.photo,
            width: 1440,
            height: 1920,
          ),
        ),
      );

      expect(payload['@type'], 'inputRichMessageMedia');
      expect(payload['id'], 'photo-1');
      final media = payload['media']! as Map<String, dynamic>;
      expect(media['@type'], 'inputMessagePhoto');
      final photo = media['photo']! as Map<String, dynamic>;
      expect(photo['width'], 1440);
      expect(photo['height'], 1920);
      expect(
        (photo['photo']! as Map<String, dynamic>)['path'],
        '/tmp/photo.jpg',
      );
    });

    test('builds every supported rich media file type', () {
      const cases = <OutgoingAttachmentKind, String>{
        OutgoingAttachmentKind.photo: 'inputMessagePhoto',
        OutgoingAttachmentKind.video: 'inputMessageVideo',
        OutgoingAttachmentKind.animation: 'inputMessageAnimation',
        OutgoingAttachmentKind.audio: 'inputMessageAudio',
        OutgoingAttachmentKind.voiceNote: 'inputMessageVoiceNote',
      };

      for (final entry in cases.entries) {
        final payload = richMessageFilePayload(
          RichMessageSendFile(
            id: entry.key.name,
            attachment: OutgoingAttachment(
              path: '/tmp/${entry.key.name}.bin',
              kind: entry.key,
              width: 640,
              height: 360,
            ),
          ),
        );
        expect(payload['@type'], 'inputRichMessageMedia');
        expect((payload['media'] as Map)['@type'], entry.value);
        expect(payload['id'], entry.key.name);
      }
    });

    test(
      'rejects documents because Telegram rich media cannot contain them',
      () {
        expect(
          () => richMessageFilePayload(
            const RichMessageSendFile(
              id: 'document',
              attachment: OutgoingAttachment(
                path: '/tmp/file.pdf',
                kind: OutgoingAttachmentKind.document,
              ),
            ),
          ),
          throwsArgumentError,
        );
      },
    );
  });

  test('builds a user rich message from explicit blocks', () {
    final content = richMessageInputContent([
      {
        '@type': 'inputPageBlockParagraph',
        'text': {'@type': 'richTextPlain', 'text': 'Hello'},
      },
    ]);

    expect(content['@type'], 'inputMessageRichMessage');
    final message = content['message']! as Map<String, dynamic>;
    expect(message['@type'], 'inputRichMessage');
    final source = message['source']! as Map<String, dynamic>;
    expect(source['@type'], 'richMessageSourceBlocks');
    expect(source['blocks'], hasLength(1));
    expect(source, isNot(contains('media')));
    expect(message, isNot(contains('files')));
    expect(content['clear_draft'], isTrue);
    expect(() => richMessageInputContent(const []), throwsArgumentError);
  });

  test('converts formatted entities into TDLib RichText nodes', () {
    final richText = formattedTextToRichText('bold link @user', const [
      {
        '@type': 'textEntity',
        'offset': 0,
        'length': 4,
        'type': {'@type': 'textEntityTypeBold'},
      },
      {
        '@type': 'textEntity',
        'offset': 5,
        'length': 4,
        'type': {
          '@type': 'textEntityTypeTextUrl',
          'url': 'https://example.com',
        },
      },
      {
        '@type': 'textEntity',
        'offset': 10,
        'length': 5,
        'type': {'@type': 'textEntityTypeMention'},
      },
    ]);

    expect(richText['@type'], 'richTexts');
    final nodes = richText['texts']! as List;
    expect((nodes[0] as Map)['@type'], 'richTextBold');
    expect((nodes[2] as Map)['@type'], 'richTextUrl');
    expect((nodes[2] as Map)['url'], 'https://example.com');
    expect((nodes[4] as Map)['@type'], 'richTextMention');
    expect((nodes[4] as Map)['username'], 'user');
  });

  test('preserves date-time formatting for direct and relay sends', () {
    const entity = {
      '@type': 'textEntity',
      'offset': 0,
      'length': 8,
      'type': {
        '@type': 'textEntityTypeDateTime',
        'unix_time': 1647531900,
        'formatting_type': {
          '@type': 'dateTimeFormattingTypeAbsolute',
          'show_day_of_week': true,
          'date_precision': {'@type': 'dateTimePartPrecisionLong'},
          'time_precision': {'@type': 'dateTimePartPrecisionShort'},
        },
      },
    };

    final richText = formattedTextToRichText('tomorrow', const [entity]);
    expect(richText['@type'], 'richTextDateTime');
    expect(richText['unix_time'], 1647531900);
    expect(
      (richText['formatting_type'] as Map)['@type'],
      'dateTimeFormattingTypeAbsolute',
    );
    expect(
      formattedTextToRichInlineHtml('tomorrow', const [entity]),
      '<tg-time unix="1647531900" format="wDt">tomorrow</tg-time>',
    );
  });

  test('builds every supported direct rich media block from a file id', () {
    const cases = <OutgoingAttachmentKind, (String, String, String)>{
      OutgoingAttachmentKind.photo: ('inputPageBlockPhoto', 'photo', 'photo'),
      OutgoingAttachmentKind.video: ('inputPageBlockVideo', 'video', 'video'),
      OutgoingAttachmentKind.animation: (
        'inputPageBlockAnimation',
        'animation',
        'animation',
      ),
      OutgoingAttachmentKind.audio: ('inputPageBlockAudio', 'audio', 'audio'),
      OutgoingAttachmentKind.voiceNote: (
        'inputPageBlockVoiceNote',
        'voice_note',
        'voice_note',
      ),
    };

    for (final entry in cases.entries) {
      final payload = richMessageMediaBlockPayload(
        OutgoingAttachment(
          path: '',
          kind: entry.key,
          fileId: 77,
          duration: 12,
          title: 'Song',
          performer: 'Artist',
          caption: 'Caption',
        ),
      );
      expect(payload['@type'], entry.value.$1);
      final typedMedia = payload[entry.value.$2]! as Map<String, dynamic>;
      final inputFile = typedMedia[entry.value.$3]! as Map<String, dynamic>;
      expect(inputFile, {'@type': 'inputFileId', 'id': 77});
      expect((payload['caption'] as Map)['@type'], 'pageBlockCaption');
    }

    expect(
      () => richMessageMediaBlockPayload(
        const OutgoingAttachment(
          path: '/tmp/file.pdf',
          kind: OutgoingAttachmentKind.document,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('omits absent captions from every direct rich media block', () {
    for (final kind in const [
      OutgoingAttachmentKind.photo,
      OutgoingAttachmentKind.video,
      OutgoingAttachmentKind.animation,
      OutgoingAttachmentKind.audio,
      OutgoingAttachmentKind.voiceNote,
    ]) {
      for (final caption in const ['', ' \n\t ']) {
        final payload = richMessageMediaBlockPayload(
          OutgoingAttachment(
            path: '',
            kind: kind,
            fileId: 77,
            caption: caption,
          ),
        );

        expect(
          payload['caption'],
          isNull,
          reason: '${kind.name} must not get a caption from whitespace',
        );
      }
    }
  });
}
