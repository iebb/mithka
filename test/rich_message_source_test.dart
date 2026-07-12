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

      expect(payload['@type'], 'inputRichMessageFilePhoto');
      final photo = payload['photo']! as Map<String, dynamic>;
      expect(photo['width'], 1440);
      expect(photo['height'], 1920);
      expect(
        (photo['photo']! as Map<String, dynamic>)['path'],
        '/tmp/photo.jpg',
      );
    });

    test('builds every supported rich media file type', () {
      const cases = <OutgoingAttachmentKind, String>{
        OutgoingAttachmentKind.photo: 'inputRichMessageFilePhoto',
        OutgoingAttachmentKind.video: 'inputRichMessageFileVideo',
        OutgoingAttachmentKind.animation: 'inputRichMessageFileAnimation',
        OutgoingAttachmentKind.audio: 'inputRichMessageFileAudio',
        OutgoingAttachmentKind.document: 'inputRichMessageFileDocument',
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
        expect(payload['@type'], entry.value);
        expect(payload['id'], entry.key.name);
      }
    });
  });
}
