import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../theme/app_theme.dart';

enum AppAssetPickerType { image, video, imageAndVideo }

class AppPickedAsset {
  const AppPickedAsset({
    required this.file,
    this.thumbnailBytes,
    this.width,
    this.height,
    this.isAnimatedImage = false,
    this.isLivePhoto = false,
  });

  final XFile file;
  final Uint8List? thumbnailBytes;
  final int? width;
  final int? height;
  final bool isAnimatedImage;
  final bool isLivePhoto;
}

class AppAssetPickerSelection {
  const AppAssetPickerSelection({
    required this.assets,
    required this.failedCount,
  });

  final List<AppPickedAsset> assets;
  final int failedCount;
}

abstract final class AppAssetPicker {
  static const _photoSendByteLimit = 9 * 1024 * 1024;

  static Future<List<XFile>> pick(
    BuildContext context, {
    required AppAssetPickerType type,
    int maxAssets = 9,
    Duration? maxVideoDuration,
    bool preferLivePhotoVideo = false,
    bool preserveOriginalFiles = false,
    int? photoMaxDimension,
  }) async {
    final selection = await pickDetailed(
      context,
      type: type,
      maxAssets: maxAssets,
      maxVideoDuration: maxVideoDuration,
      preferLivePhotoVideo: preferLivePhotoVideo,
      preserveOriginalFiles: preserveOriginalFiles,
      photoMaxDimension: photoMaxDimension,
    );
    return selection.assets.map((asset) => asset.file).toList(growable: false);
  }

  static Future<AppAssetPickerSelection> pickDetailed(
    BuildContext context, {
    required AppAssetPickerType type,
    int maxAssets = 9,
    Duration? maxVideoDuration,
    bool preferLivePhotoVideo = false,
    bool preserveOriginalFiles = false,
    int? photoMaxDimension,
  }) async {
    if (maxAssets <= 0) {
      return const AppAssetPickerSelection(assets: [], failedCount: 0);
    }
    try {
      final assets = await AssetPicker.pickAssets(
        context,
        pickerConfig: buildConfig(
          context,
          type: type,
          maxAssets: maxAssets,
          maxVideoDuration: maxVideoDuration,
        ),
      );
      if (assets == null || assets.isEmpty) {
        return const AppAssetPickerSelection(assets: [], failedCount: 0);
      }

      final resolved = <AppPickedAsset>[];
      var failedCount = 0;
      for (final asset in assets) {
        try {
          resolved.add(
            await _materialize(
              asset,
              preferLivePhotoVideo: preferLivePhotoVideo,
              preserveOriginalFiles: preserveOriginalFiles,
              photoMaxDimension: photoMaxDimension,
            ),
          );
        } catch (_) {
          failedCount++;
        }
      }
      return AppAssetPickerSelection(
        assets: List.unmodifiable(resolved),
        failedCount: failedCount,
      );
    } on StateError {
      // Permission denied — request it and retry.
      final requestType = switch (type) {
        AppAssetPickerType.image => RequestType.image,
        AppAssetPickerType.video => RequestType.video,
        AppAssetPickerType.imageAndVideo => RequestType.common,
      };
      final state = await PhotoManager.requestPermissionExtend(
        requestOption: PermissionRequestOption(
          androidPermission: AndroidPermission(
            type: requestType,
            mediaLocation: false,
          ),
        ),
      );
      if (state == PermissionState.authorized ||
          state == PermissionState.limited) {
        final assets = await AssetPicker.pickAssets(
          context,
          pickerConfig: buildConfig(
            context,
            type: type,
            maxAssets: maxAssets,
            maxVideoDuration: maxVideoDuration,
          ),
        );
        if (assets == null || assets.isEmpty) {
          return const AppAssetPickerSelection(assets: [], failedCount: 0);
        }
        final resolved = <AppPickedAsset>[];
        var failedCount = 0;
        for (final asset in assets) {
          try {
            resolved.add(
              await _materialize(
                asset,
                preferLivePhotoVideo: preferLivePhotoVideo,
                preserveOriginalFiles: preserveOriginalFiles,
                photoMaxDimension: photoMaxDimension,
              ),
            );
          } catch (_) {
            failedCount++;
          }
        }
        return AppAssetPickerSelection(
          assets: List.unmodifiable(resolved),
          failedCount: failedCount,
        );
      }
      return const AppAssetPickerSelection(assets: [], failedCount: 0);
    }
  }

  static AssetPickerConfig buildConfig(
    BuildContext context, {
    required AppAssetPickerType type,
    int maxAssets = 9,
    Duration? maxVideoDuration,
  }) {
    final gridCount = MediaQuery.sizeOf(context).width >= 700 ? 6 : 4;
    return AssetPickerConfig(
      maxAssets: maxAssets,
      pageSize: gridCount * 20,
      gridCount: gridCount,
      requestType: switch (type) {
        AppAssetPickerType.image => RequestType.image,
        AppAssetPickerType.video => RequestType.video,
        AppAssetPickerType.imageAndVideo => RequestType.common,
      },
      pickerTheme: pickerTheme(context),
      textDelegate: assetPickerTextDelegateFromLocale(
        Localizations.maybeLocaleOf(context),
        fallback: const EnglishAssetPickerTextDelegate(),
      ),
      filterOptions: FilterOptionGroup(
        videoOption: FilterOption(
          durationConstraint: DurationConstraint(
            max: maxVideoDuration ?? const Duration(days: 1),
          ),
        ),
      ),
      keepScrollOffset: true,
    );
  }

  static ThemeData pickerTheme(BuildContext context) {
    final appTheme = Theme.of(context);
    final colors = context.colors;
    final brightness = appTheme.brightness;
    final base = AssetPicker.themeData(
      AppTheme.brand,
      light: brightness == Brightness.light,
    );
    final textTheme = appTheme.textTheme.apply(
      bodyColor: colors.textPrimary,
      displayColor: colors.textPrimary,
    );

    return base.copyWith(
      brightness: brightness,
      primaryColor: AppTheme.brand,
      scaffoldBackgroundColor: colors.groupedBackground,
      canvasColor: colors.background,
      cardColor: colors.card,
      dividerColor: colors.divider,
      disabledColor: colors.textTertiary,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      iconTheme: IconThemeData(color: colors.textPrimary),
      appBarTheme: base.appBarTheme.copyWith(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colors.navBar,
        foregroundColor: colors.textPrimary,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: colors.textPrimary),
        titleTextStyle: textTheme.titleMedium?.copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      colorScheme: base.colorScheme.copyWith(
        brightness: brightness,
        primary: AppTheme.brand,
        secondary: AppTheme.brand,
        surface: colors.background,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: colors.textPrimary,
        error: AppTheme.tagRed,
      ),
      bottomNavigationBarTheme: base.bottomNavigationBarTheme.copyWith(
        backgroundColor: colors.navBar,
        selectedItemColor: AppTheme.brand,
        unselectedItemColor: colors.textSecondary,
      ),
    );
  }

  static Future<AppPickedAsset> _materialize(
    AssetEntity asset, {
    required bool preferLivePhotoVideo,
    required bool preserveOriginalFiles,
    int? photoMaxDimension,
  }) async {
    final originalMimeType = asset.mimeType ?? await asset.mimeTypeAsync;
    final livePhotoAsVideo = preferLivePhotoVideo && asset.isLivePhoto;
    final lowerMimeType = originalMimeType?.toLowerCase();
    final lowerTitle = asset.title?.toLowerCase() ?? '';
    final preserveOriginalAnimatedImage =
        lowerMimeType == 'image/gif' ||
        lowerMimeType == 'image/apng' ||
        lowerMimeType == 'image/png' ||
        lowerTitle.endsWith('.gif') ||
        lowerTitle.endsWith('.apng') ||
        lowerTitle.endsWith('.png');
    final file = await asset.loadFile(
      isOrigin:
          preserveOriginalFiles ||
          asset.type == AssetType.video ||
          livePhotoAsVideo ||
          preserveOriginalAnimatedImage,
      withSubtype: livePhotoAsVideo,
      darwinFileType: livePhotoAsVideo ? PMDarwinAVFileType.mp4 : null,
    );
    if (file == null) {
      throw StateError('Unable to read selected asset ${asset.id}');
    }
    final mimeType = livePhotoAsVideo ? 'video/mp4' : originalMimeType;
    final isGif = await _isGifFile(file, mimeType);
    final isApng = await _isApngFile(file, mimeType);
    final isAnimatedImage = isGif || isApng;
    final shouldCompressPhoto =
        !preserveOriginalFiles &&
        asset.type == AssetType.image &&
        !isAnimatedImage &&
        !livePhotoAsVideo &&
        (photoMaxDimension != null ||
            await file.length() > _photoSendByteLimit ||
            asset.width > 4096 ||
            asset.height > 4096);
    final sendBytes = shouldCompressPhoto
        ? await _compressedPhotoBytes(
            asset,
            preferredMaxDimension: photoMaxDimension,
          )
        : null;
    if (shouldCompressPhoto && sendBytes == null) {
      throw StateError('Unable to prepare selected photo ${asset.id}');
    }
    final extension = shouldCompressPhoto
        ? 'jpg'
        : (livePhotoAsVideo
              ? 'mp4'
              : isGif
              ? 'gif'
              : isApng
              ? 'png'
              : _fileExtension(file.path, mimeType, asset.type));
    final directory = await getTemporaryDirectory();
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final targetDirectory = preserveOriginalFiles
        ? await Directory(
            '${directory.path}/mithka-picker-$timestamp-${asset.id.hashCode}',
          ).create(recursive: true)
        : directory;
    final durableName = preserveOriginalFiles
        ? pickedAssetDocumentFileName(
            title: asset.title,
            sourcePath: file.path,
            fallbackExtension: extension,
          )
        : 'mithka-picker-$timestamp-${asset.id.hashCode}.$extension';
    final durableFile = File('${targetDirectory.path}/$durableName');
    if (sendBytes == null) {
      await file.copy(durableFile.path);
    } else {
      await durableFile.writeAsBytes(sendBytes, flush: true);
    }
    final thumbnailBytes = await asset.thumbnailDataWithSize(
      const ThumbnailSize(512, 512),
      quality: 86,
    );
    return AppPickedAsset(
      file: XFile(
        durableFile.path,
        mimeType: shouldCompressPhoto ? 'image/jpeg' : mimeType,
        name: durableName,
      ),
      thumbnailBytes: thumbnailBytes,
      width: asset.width > 0 ? asset.width : null,
      height: asset.height > 0 ? asset.height : null,
      isAnimatedImage: isAnimatedImage,
      isLivePhoto: asset.isLivePhoto,
    );
  }

  static Future<bool> _isGifFile(File file, String? mimeType) async {
    if (mimeType?.toLowerCase() == 'image/gif' ||
        file.path.toLowerCase().endsWith('.gif')) {
      return true;
    }
    final bytes = await _readPrefix(file, 6);
    if (bytes.length < 6) return false;
    return String.fromCharCodes(bytes) == 'GIF87a' ||
        String.fromCharCodes(bytes) == 'GIF89a';
  }

  static Future<bool> _isApngFile(File file, String? mimeType) async {
    final lowerMimeType = mimeType?.toLowerCase();
    if (lowerMimeType == 'image/apng' ||
        file.path.toLowerCase().endsWith('.apng')) {
      return true;
    }
    if (lowerMimeType != null && lowerMimeType != 'image/png') return false;
    final bytes = await _readPrefix(file, 1024 * 1024);
    if (bytes.length < 12 ||
        bytes[0] != 0x89 ||
        bytes[1] != 0x50 ||
        bytes[2] != 0x4e ||
        bytes[3] != 0x47) {
      return false;
    }
    for (var i = 8; i + 8 <= bytes.length; i++) {
      if (bytes[i] == 0x61 &&
          bytes[i + 1] == 0x63 &&
          bytes[i + 2] == 0x54 &&
          bytes[i + 3] == 0x4c) {
        return true;
      }
    }
    return false;
  }

  static Future<Uint8List> _readPrefix(File file, int maxBytes) async {
    final handle = await file.open();
    try {
      return await handle.read(maxBytes);
    } finally {
      await handle.close();
    }
  }

  static Future<Uint8List?> _compressedPhotoBytes(
    AssetEntity asset, {
    int? preferredMaxDimension,
  }) async {
    Uint8List? lastResult;
    final targets = preferredMaxDimension == null
        ? const [
            (maxDimension: 4096, quality: 90),
            (maxDimension: 4096, quality: 82),
            (maxDimension: 3200, quality: 82),
            (maxDimension: 2560, quality: 76),
            (maxDimension: 2048, quality: 72),
          ]
        : [
            (maxDimension: preferredMaxDimension, quality: 90),
            (maxDimension: preferredMaxDimension, quality: 84),
            (maxDimension: (preferredMaxDimension * 0.82).round(), quality: 80),
          ];
    for (final target in targets) {
      final size = scaledPhotoThumbnailSize(
        asset.width,
        asset.height,
        target.maxDimension,
      );
      final bytes = await asset.thumbnailDataWithSize(
        size,
        quality: target.quality,
      );
      if (bytes == null || bytes.isEmpty) continue;
      lastResult = bytes;
      if (bytes.length <= _photoSendByteLimit) return bytes;
    }
    return lastResult != null && lastResult.length <= _photoSendByteLimit
        ? lastResult
        : null;
  }

  static String _fileExtension(String path, String? mimeType, AssetType type) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    if (dot >= 0 && dot < name.length - 1) {
      return name.substring(dot + 1).toLowerCase();
    }
    return switch (mimeType?.toLowerCase()) {
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/gif' => 'gif',
      'image/webp' => 'webp',
      'image/heic' => 'heic',
      'image/heif' => 'heif',
      'image/avif' => 'avif',
      'video/mp4' => 'mp4',
      'video/quicktime' => 'mov',
      _ => type == AssetType.video ? 'mp4' : 'jpg',
    };
  }
}

String pickedAssetDocumentFileName({
  required String? title,
  required String sourcePath,
  required String fallbackExtension,
}) {
  final trimmedTitle = title?.trim() ?? '';
  final sourceName = trimmedTitle.isNotEmpty
      ? trimmedTitle
      : sourcePath.split(RegExp(r'[/\\]')).last;
  var safeName = sourceName.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_');
  if (safeName.isEmpty || safeName == '.' || safeName == '..') {
    safeName = 'attachment.$fallbackExtension';
  }
  if (!safeName.contains('.')) safeName = '$safeName.$fallbackExtension';
  return safeName;
}

ThumbnailSize scaledPhotoThumbnailSize(
  int width,
  int height,
  int maxDimension,
) {
  if (width <= 0 || height <= 0) {
    return ThumbnailSize.square(maxDimension);
  }
  final scale = maxDimension / (width > height ? width : height);
  if (scale >= 1) return ThumbnailSize(width, height);
  return ThumbnailSize(
    (width * scale).round().clamp(1, maxDimension),
    (height * scale).round().clamp(1, maxDimension),
  );
}

bool isPickedAssetVideo(XFile file) {
  if (file.mimeType?.toLowerCase().startsWith('video/') ?? false) return true;
  return _hasExtension(file, const ['mp4', 'mov', 'm4v', 'webm', 'avi', 'mkv']);
}

bool isPickedAssetGif(XFile file) {
  if (file.mimeType?.toLowerCase() == 'image/gif') return true;
  return _hasExtension(file, const ['gif']);
}

bool _hasExtension(XFile file, List<String> extensions) {
  final path = file.path.toLowerCase();
  final name = file.name.toLowerCase();
  return extensions.any(
    (extension) => path.endsWith('.$extension') || name.endsWith('.$extension'),
  );
}
