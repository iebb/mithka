import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as image_lib;

import '../l10n/app_localizations.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';

typedef StickerSetQuery =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

enum OwnedStickerSetType { regular, mask, customEmoji }

enum StickerFileFormat { webp, tgs, webm }

enum StickerMaskPoint { forehead, eyes, mouth, chin }

extension OwnedStickerSetTypeTd on OwnedStickerSetType {
  String get tdType => switch (this) {
    OwnedStickerSetType.regular => 'stickerTypeRegular',
    OwnedStickerSetType.mask => 'stickerTypeMask',
    OwnedStickerSetType.customEmoji => 'stickerTypeCustomEmoji',
  };
}

extension StickerFileFormatTd on StickerFileFormat {
  String get tdType => switch (this) {
    StickerFileFormat.webp => 'stickerFormatWebp',
    StickerFileFormat.tgs => 'stickerFormatTgs',
    StickerFileFormat.webm => 'stickerFormatWebm',
  };

  List<String> get allowedExtensions => switch (this) {
    StickerFileFormat.webp => const ['png', 'webp'],
    StickerFileFormat.tgs => const ['tgs'],
    StickerFileFormat.webm => const ['webm'],
  };
}

extension StickerMaskPointTd on StickerMaskPoint {
  String get tdType => switch (this) {
    StickerMaskPoint.forehead => 'maskPointForehead',
    StickerMaskPoint.eyes => 'maskPointEyes',
    StickerMaskPoint.mouth => 'maskPointMouth',
    StickerMaskPoint.chin => 'maskPointChin',
  };
}

class StickerMaskPlacement {
  const StickerMaskPlacement({
    required this.point,
    this.xShift = 0,
    this.yShift = 0,
    this.scale = 1,
  });

  final StickerMaskPoint point;
  final double xShift;
  final double yShift;
  final double scale;

  Map<String, dynamic> toTdJson() => {
    '@type': 'maskPosition',
    'point': {'@type': point.tdType},
    'x_shift': xShift,
    'y_shift': yShift,
    'scale': scale,
  };
}

class NewStickerDraft {
  const NewStickerDraft({
    required this.path,
    required this.format,
    required this.emojis,
    this.keywords = const [],
    this.maskPlacement,
    this.uploadedFileId = 0,
  });

  final String path;
  final StickerFileFormat format;
  final String emojis;
  final List<String> keywords;
  final StickerMaskPlacement? maskPlacement;
  final int uploadedFileId;

  NewStickerDraft withUploadedFileId(int fileId) => NewStickerDraft(
    path: path,
    format: format,
    emojis: emojis,
    keywords: keywords,
    maskPlacement: maskPlacement,
    uploadedFileId: fileId,
  );

  Map<String, dynamic> toTdJson() => {
    '@type': 'newSticker',
    'sticker': uploadedFileId == 0
        ? {'@type': 'inputFileLocal', 'path': path}
        : {'@type': 'inputFileId', 'id': uploadedFileId},
    'format': {'@type': format.tdType},
    'emojis': emojis.trim(),
    'mask_position': maskPlacement?.toTdJson(),
    'keywords': keywords
        .map((keyword) => keyword.trim())
        .where((keyword) => keyword.isNotEmpty)
        .toList(growable: false),
  };
}

class StickerValidationResult {
  const StickerValidationResult(this.errors);

  final List<String> errors;
  bool get isValid => errors.isEmpty;
}

abstract final class StickerInputValidator {
  static const staticStickerByteLimit = 512 * 1024;
  static const animatedStickerByteLimit = 64 * 1024;
  static const videoStickerByteLimit = 256 * 1024;

  static Future<StickerValidationResult> validate(
    NewStickerDraft draft, {
    required OwnedStickerSetType setType,
  }) async {
    final file = File(draft.path);
    if (!await file.exists()) {
      return StickerValidationResult([
        AppStrings.t(AppStringKeys.stickerStudioValidationFileMissing),
      ]);
    }
    return validateBytes(
      path: draft.path,
      bytes: await file.readAsBytes(),
      format: draft.format,
      emojis: draft.emojis,
      keywords: draft.keywords,
      setType: setType,
      maskPlacement: draft.maskPlacement,
    );
  }

  @visibleForTesting
  static StickerValidationResult validateBytes({
    required String path,
    required Uint8List bytes,
    required StickerFileFormat format,
    required String emojis,
    required List<String> keywords,
    required OwnedStickerSetType setType,
    StickerMaskPlacement? maskPlacement,
  }) {
    final errors = <String>[];
    final extension = path.split('.').last.toLowerCase();
    if (!format.allowedExtensions.contains(extension)) {
      errors.add(
        AppStrings.t(AppStringKeys.stickerStudioValidationExtension, {
          'value1': format.name.toUpperCase(),
          'value2': format.allowedExtensions
              .map((value) => '.$value')
              .join(' or '),
        }),
      );
    }
    final emojiCount = emojis.trim().characters.length;
    if (emojiCount == 0) {
      errors.add(
        AppStrings.t(AppStringKeys.stickerStudioValidationMatchingEmoji),
      );
    } else if (emojiCount > 20) {
      errors.add(
        AppStrings.t(AppStringKeys.stickerStudioValidationMatchingEmojiCount),
      );
    }
    if (keywords.length > 20) {
      errors.add(
        AppStrings.t(AppStringKeys.stickerStudioValidationKeywordsCount),
      );
    }
    final normalizedKeywords = keywords
        .map((keyword) => keyword.trim())
        .where((keyword) => keyword.isNotEmpty)
        .toList(growable: false);
    if (normalizedKeywords.fold<int>(0, (sum, value) => sum + value.length) >
        64) {
      errors.add(
        AppStrings.t(AppStringKeys.stickerStudioValidationKeywordsCharacters),
      );
    }
    if (setType == OwnedStickerSetType.mask &&
        format != StickerFileFormat.webp) {
      errors.add(AppStrings.t(AppStringKeys.stickerStudioValidationMaskFormat));
    }
    if (setType != OwnedStickerSetType.mask && maskPlacement != null) {
      errors.add(AppStrings.t(AppStringKeys.stickerStudioValidationMaskOnly));
    }
    if (maskPlacement != null && maskPlacement.scale <= 0) {
      errors.add(AppStrings.t(AppStringKeys.stickerStudioValidationMaskScale));
    }

    switch (format) {
      case StickerFileFormat.webp:
        if (bytes.length > staticStickerByteLimit) {
          errors.add(
            AppStrings.t(AppStringKeys.stickerStudioValidationStaticSize),
          );
        }
        final image = image_lib.decodeImage(bytes);
        if (image == null) {
          errors.add(AppStrings.t(AppStringKeys.stickerStudioValidationImage));
        } else if (image.width > 512 || image.height > 512) {
          errors.add(
            AppStrings.t(AppStringKeys.stickerStudioValidationStaticDimensions),
          );
        }
      case StickerFileFormat.tgs:
        if (bytes.length > animatedStickerByteLimit) {
          errors.add(
            AppStrings.t(AppStringKeys.stickerStudioValidationAnimatedSize),
          );
        }
        try {
          final decoded = GZipDecoder().decodeBytes(bytes);
          final document = jsonDecode(utf8.decode(decoded));
          if (document is! Map<String, dynamic>) {
            throw const FormatException('not an object');
          }
          final width = (document['w'] as num?)?.toInt();
          final height = (document['h'] as num?)?.toInt();
          final frameRate = (document['fr'] as num?)?.toDouble() ?? 0;
          final firstFrame = (document['ip'] as num?)?.toDouble() ?? 0;
          final lastFrame = (document['op'] as num?)?.toDouble() ?? 0;
          if (width != 512 || height != 512) {
            errors.add(
              AppStrings.t(AppStringKeys.stickerStudioValidationAnimatedCanvas),
            );
          }
          if (frameRate <= 0 ||
              lastFrame <= firstFrame ||
              (lastFrame - firstFrame) / frameRate > 3.05) {
            errors.add(
              AppStrings.t(
                AppStringKeys.stickerStudioValidationAnimatedDuration,
              ),
            );
          }
        } catch (_) {
          errors.add(AppStrings.t(AppStringKeys.stickerStudioValidationTgs));
        }
      case StickerFileFormat.webm:
        if (bytes.length > videoStickerByteLimit) {
          errors.add(
            AppStrings.t(AppStringKeys.stickerStudioValidationVideoSize),
          );
        }
        const ebmlHeader = [0x1a, 0x45, 0xdf, 0xa3];
        if (bytes.length < ebmlHeader.length ||
            !listEquals(bytes.take(4).toList(), ebmlHeader)) {
          errors.add(AppStrings.t(AppStringKeys.stickerStudioValidationVideo));
        }
    }
    return StickerValidationResult(List.unmodifiable(errors));
  }
}

@visibleForTesting
Map<String, dynamic> createStickerSetRequest({
  required int userId,
  required String title,
  required String name,
  required OwnedStickerSetType type,
  required bool needsRepainting,
  required List<NewStickerDraft> stickers,
  String source = 'Mithka',
}) => {
  '@type': 'createNewStickerSet',
  'user_id': userId,
  'title': title.trim(),
  'name': name.trim(),
  'sticker_type': {'@type': type.tdType},
  'needs_repainting':
      type == OwnedStickerSetType.customEmoji && needsRepainting,
  'stickers': stickers.map((sticker) => sticker.toTdJson()).toList(),
  'source': source,
};

@visibleForTesting
Map<String, dynamic> addStickerToSetRequest({
  required int userId,
  required String name,
  required NewStickerDraft sticker,
}) => {
  '@type': 'addStickerToSet',
  'user_id': userId,
  'name': name,
  'sticker': sticker.toTdJson(),
};

@visibleForTesting
Map<String, dynamic> replaceStickerInSetRequest({
  required int userId,
  required String name,
  required int oldStickerFileId,
  required NewStickerDraft sticker,
}) => {
  '@type': 'replaceStickerInSet',
  'user_id': userId,
  'name': name,
  'old_sticker': {'@type': 'inputFileId', 'id': oldStickerFileId},
  'new_sticker': sticker.toTdJson(),
};

@visibleForTesting
Map<String, dynamic> uploadStickerFileRequest({
  required int userId,
  required NewStickerDraft sticker,
}) => {
  '@type': 'uploadStickerFile',
  'user_id': userId,
  'sticker_format': {'@type': sticker.format.tdType},
  'sticker': {'@type': 'inputFileLocal', 'path': sticker.path},
};

class StickerSetManagementService {
  StickerSetManagementService({StickerSetQuery? query})
    : _query = query ?? TdClient.shared.query;

  final StickerSetQuery _query;

  Future<int> myId() async =>
      (await _query({'@type': 'getMe'})).int64('id') ?? 0;

  Future<List<Map<String, dynamic>>> ownedSets() async {
    final result = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final response = await _query({
        '@type': 'getOwnedStickerSets',
        'offset_sticker_set_id': offset,
        'limit': 100,
      });
      final page = response.objects('sets') ?? const [];
      result.addAll(page);
      if (page.isEmpty || page.length < 100) break;
      final next = page.last.int64('id') ?? 0;
      if (next == 0 || next == offset) break;
      offset = next;
    }
    return result;
  }

  Future<Map<String, dynamic>> getSet(int setId) =>
      _query({'@type': 'getStickerSet', 'set_id': setId});

  Future<String> suggestedName(String title) async =>
      (await _query({
        '@type': 'getSuggestedStickerSetName',
        'title': title.trim(),
      })).str('text') ??
      '';

  Future<Map<String, dynamic>> checkName(String name) =>
      _query({'@type': 'checkStickerSetName', 'name': name.trim()});

  Future<Map<String, dynamic>> create({
    required String title,
    required String name,
    required OwnedStickerSetType type,
    required bool needsRepainting,
    required List<NewStickerDraft> stickers,
  }) async {
    final userId = await myId();
    final uploaded = <NewStickerDraft>[];
    for (final sticker in stickers) {
      uploaded.add(await _upload(userId, sticker));
    }
    return _query(
      createStickerSetRequest(
        userId: userId,
        title: title,
        name: name,
        type: type,
        needsRepainting: needsRepainting,
        stickers: uploaded,
      ),
    );
  }

  Future<void> add(String name, NewStickerDraft sticker) async {
    final userId = await myId();
    final uploaded = await _upload(userId, sticker);
    await _query(
      addStickerToSetRequest(userId: userId, name: name, sticker: uploaded),
    );
  }

  Future<void> replace(
    String name,
    int oldStickerFileId,
    NewStickerDraft sticker,
  ) async {
    final userId = await myId();
    final uploaded = await _upload(userId, sticker);
    await _query(
      replaceStickerInSetRequest(
        userId: userId,
        name: name,
        oldStickerFileId: oldStickerFileId,
        sticker: uploaded,
      ),
    );
  }

  Future<void> setTitle(String name, String title) => _query({
    '@type': 'setStickerSetTitle',
    'name': name,
    'title': title.trim(),
  });

  Future<void> delete(String name) =>
      _query({'@type': 'deleteStickerSet', 'name': name});

  Future<void> move(int fileId, int position) => _query({
    '@type': 'setStickerPositionInSet',
    'sticker': {'@type': 'inputFileId', 'id': fileId},
    'position': position,
  });

  Future<void> remove(int fileId) => _query({
    '@type': 'removeStickerFromSet',
    'sticker': {'@type': 'inputFileId', 'id': fileId},
  });

  Future<void> setEmojis(int fileId, String emojis) => _query({
    '@type': 'setStickerEmojis',
    'sticker': {'@type': 'inputFileId', 'id': fileId},
    'emojis': emojis.trim(),
  });

  Future<void> setKeywords(int fileId, List<String> keywords) => _query({
    '@type': 'setStickerKeywords',
    'sticker': {'@type': 'inputFileId', 'id': fileId},
    'keywords': keywords
        .map((keyword) => keyword.trim())
        .where((keyword) => keyword.isNotEmpty)
        .toList(growable: false),
  });

  Future<void> setMaskPlacement(int fileId, StickerMaskPlacement? placement) =>
      _query({
        '@type': 'setStickerMaskPosition',
        'sticker': {'@type': 'inputFileId', 'id': fileId},
        'mask_position': placement?.toTdJson(),
      });

  Future<void> setThumbnail({
    required String name,
    required String? path,
    required StickerFileFormat? format,
  }) async {
    await _query({
      '@type': 'setStickerSetThumbnail',
      'user_id': await myId(),
      'name': name,
      'thumbnail': path == null
          ? null
          : {'@type': 'inputFileLocal', 'path': path},
      'format': format == null ? null : {'@type': format.tdType},
    });
  }

  Future<void> setCustomEmojiThumbnail(String name, int customEmojiId) =>
      _query({
        '@type': 'setCustomEmojiStickerSetThumbnail',
        'name': name,
        'custom_emoji_id': customEmojiId,
      });

  Future<NewStickerDraft> _upload(int userId, NewStickerDraft sticker) async {
    final file = await _query(
      uploadStickerFileRequest(userId: userId, sticker: sticker),
    );
    final fileId = file.int64('id') ?? 0;
    if (fileId == 0) {
      throw StateError('TDLib did not return an uploaded sticker file.');
    }
    return sticker.withUploadedFileId(fileId);
  }
}
