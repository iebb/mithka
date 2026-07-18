import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:mithka/chat/sticker_set_management_service.dart';

void main() {
  test('new sticker and create set requests match pinned TDLib schema', () {
    const draft = NewStickerDraft(
      path: '/tmp/face.png',
      format: StickerFileFormat.webp,
      emojis: ' 🙂 ',
      keywords: [' happy ', 'face'],
      maskPlacement: StickerMaskPlacement(
        point: StickerMaskPoint.eyes,
        xShift: 0.25,
        yShift: -0.5,
        scale: 1.2,
      ),
    );

    expect(
      createStickerSetRequest(
        userId: 42,
        title: ' Faces ',
        name: 'faces_by_me',
        type: OwnedStickerSetType.mask,
        needsRepainting: true,
        stickers: const [draft],
      ),
      {
        '@type': 'createNewStickerSet',
        'user_id': 42,
        'title': 'Faces',
        'name': 'faces_by_me',
        'sticker_type': {'@type': 'stickerTypeMask'},
        'needs_repainting': false,
        'stickers': [
          {
            '@type': 'newSticker',
            'sticker': {'@type': 'inputFileLocal', 'path': '/tmp/face.png'},
            'format': {'@type': 'stickerFormatWebp'},
            'emojis': '🙂',
            'mask_position': {
              '@type': 'maskPosition',
              'point': {'@type': 'maskPointEyes'},
              'x_shift': 0.25,
              'y_shift': -0.5,
              'scale': 1.2,
            },
            'keywords': ['happy', 'face'],
          },
        ],
        'source': 'Mithka',
      },
    );
  });

  test('add and replace requests use newSticker and inputFileId', () {
    const draft = NewStickerDraft(
      path: '/tmp/emoji.tgs',
      format: StickerFileFormat.tgs,
      emojis: '🔥',
    );
    expect(
      addStickerToSetRequest(userId: 8, name: 'fire', sticker: draft)['@type'],
      'addStickerToSet',
    );
    expect(
      replaceStickerInSetRequest(
        userId: 8,
        name: 'fire',
        oldStickerFileId: 99,
        sticker: draft,
      ),
      containsPair('old_sticker', {'@type': 'inputFileId', 'id': 99}),
    );
    expect(uploadStickerFileRequest(userId: 8, sticker: draft), {
      '@type': 'uploadStickerFile',
      'user_id': 8,
      'sticker_format': {'@type': 'stickerFormatTgs'},
      'sticker': {'@type': 'inputFileLocal', 'path': '/tmp/emoji.tgs'},
    });
    expect(draft.withUploadedFileId(777).toTdJson()['sticker'], {
      '@type': 'inputFileId',
      'id': 777,
    });
  });

  test(
    'static and animated source validation checks dimensions and duration',
    () {
      final png = Uint8List.fromList(
        image_lib.encodePng(image_lib.Image(width: 512, height: 320)),
      );
      final validImage = StickerInputValidator.validateBytes(
        path: 'sticker.png',
        bytes: png,
        format: StickerFileFormat.webp,
        emojis: '🙂',
        keywords: const ['smile'],
        setType: OwnedStickerSetType.regular,
      );
      expect(validImage.isValid, isTrue, reason: validImage.errors.join(', '));

      final tgs = Uint8List.fromList(
        GZipEncoder().encode(
          utf8.encode(
            jsonEncode({'w': 512, 'h': 512, 'fr': 60, 'ip': 0, 'op': 180}),
          ),
        )!,
      );
      final validAnimated = StickerInputValidator.validateBytes(
        path: 'sticker.tgs',
        bytes: tgs,
        format: StickerFileFormat.tgs,
        emojis: '✨',
        keywords: const [],
        setType: OwnedStickerSetType.customEmoji,
      );
      expect(
        validAnimated.isValid,
        isTrue,
        reason: validAnimated.errors.join(', '),
      );

      final tooLarge = StickerInputValidator.validateBytes(
        path: 'sticker.png',
        bytes: Uint8List.fromList(
          image_lib.encodePng(image_lib.Image(width: 513, height: 512)),
        ),
        format: StickerFileFormat.webp,
        emojis: '',
        keywords: List.filled(21, 'word'),
        setType: OwnedStickerSetType.regular,
      );
      expect(tooLarge.isValid, isFalse);
      expect(tooLarge.errors, contains(contains('512 by 512')));
      expect(tooLarge.errors, contains(contains('at least one')));
      expect(tooLarge.errors, contains(contains('at most 20')));
    },
  );

  test(
    'owned set pagination and management requests use exact fields',
    () async {
      final requests = <Map<String, dynamic>>[];
      final service = StickerSetManagementService(
        query: (request) async {
          requests.add(request);
          return switch (request['@type']) {
            'getMe' => {'@type': 'user', 'id': 73},
            'getOwnedStickerSets' => {
              '@type': 'stickerSets',
              'sets': <Map<String, dynamic>>[],
            },
            _ => {'@type': 'ok'},
          };
        },
      );

      await service.ownedSets();
      await service.setTitle('my_set', ' New title ');
      await service.move(123, 4);
      await service.remove(123);
      await service.setEmojis(123, ' 👋 ');
      await service.setKeywords(123, const [' hello ', 'wave']);
      await service.setMaskPlacement(
        123,
        const StickerMaskPlacement(point: StickerMaskPoint.chin),
      );
      await service.setThumbnail(
        name: 'my_set',
        path: '/tmp/thumb.webp',
        format: StickerFileFormat.webp,
      );
      await service.setCustomEmojiThumbnail('my_set', 555);
      await service.delete('my_set');

      expect(requests.first, {
        '@type': 'getOwnedStickerSets',
        'offset_sticker_set_id': 0,
        'limit': 100,
      });
      expect(requests[1], {
        '@type': 'setStickerSetTitle',
        'name': 'my_set',
        'title': 'New title',
      });
      expect(requests[2]['@type'], 'setStickerPositionInSet');
      expect(requests[2]['position'], 4);
      expect(requests[3]['@type'], 'removeStickerFromSet');
      expect(requests[4]['emojis'], '👋');
      expect(requests[5]['keywords'], ['hello', 'wave']);
      expect(requests[6]['mask_position'], {
        '@type': 'maskPosition',
        'point': {'@type': 'maskPointChin'},
        'x_shift': 0.0,
        'y_shift': 0.0,
        'scale': 1.0,
      });
      expect(requests[7], {'@type': 'getMe'});
      expect(requests[8]['@type'], 'setStickerSetThumbnail');
      expect(requests[8]['user_id'], 73);
      expect(requests[9]['@type'], 'setCustomEmojiStickerSetThumbnail');
      expect(requests[10], {'@type': 'deleteStickerSet', 'name': 'my_set'});
    },
  );
}
