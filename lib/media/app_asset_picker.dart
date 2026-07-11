import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../theme/app_theme.dart';

enum AppAssetPickerType { image, video, imageAndVideo }

class AppPickedAsset {
  const AppPickedAsset({required this.file, this.thumbnailBytes});

  final XFile file;
  final Uint8List? thumbnailBytes;
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
  }) async {
    final selection = await pickDetailed(
      context,
      type: type,
      maxAssets: maxAssets,
      maxVideoDuration: maxVideoDuration,
    );
    return selection.assets.map((asset) => asset.file).toList(growable: false);
  }

  static Future<AppAssetPickerSelection> pickDetailed(
    BuildContext context, {
    required AppAssetPickerType type,
    int maxAssets = 9,
    Duration? maxVideoDuration,
  }) async {
    if (maxAssets <= 0) {
      return const AppAssetPickerSelection(assets: [], failedCount: 0);
    }
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
        resolved.add(await _materialize(asset));
      } catch (_) {
        failedCount++;
      }
    }
    return AppAssetPickerSelection(
      assets: List.unmodifiable(resolved),
      failedCount: failedCount,
    );
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

  static Future<AppPickedAsset> _materialize(AssetEntity asset) async {
    final mimeType = asset.mimeType ?? await asset.mimeTypeAsync;
    final isGif = mimeType?.toLowerCase() == 'image/gif';
    final file = await asset.loadFile(
      isOrigin: asset.type == AssetType.video || isGif,
    );
    if (file == null) {
      throw StateError('Unable to read selected asset ${asset.id}');
    }
    final shouldCompressPhoto =
        asset.type == AssetType.image &&
        !isGif &&
        (await file.length() > _photoSendByteLimit ||
            asset.width > 4096 ||
            asset.height > 4096);
    final sendBytes = shouldCompressPhoto
        ? await _compressedPhotoBytes(asset)
        : null;
    if (shouldCompressPhoto && sendBytes == null) {
      throw StateError('Unable to prepare selected photo ${asset.id}');
    }
    final extension = shouldCompressPhoto
        ? 'jpg'
        : _fileExtension(file.path, mimeType, asset.type);
    final directory = await getTemporaryDirectory();
    final durableFile = File(
      '${directory.path}/mithka-picker-${DateTime.now().microsecondsSinceEpoch}-${asset.id.hashCode}.$extension',
    );
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
      ),
      thumbnailBytes: thumbnailBytes,
    );
  }

  static Future<Uint8List?> _compressedPhotoBytes(AssetEntity asset) async {
    Uint8List? lastResult;
    for (final target in const [
      (maxDimension: 4096, quality: 90),
      (maxDimension: 4096, quality: 82),
      (maxDimension: 3200, quality: 82),
      (maxDimension: 2560, quality: 76),
      (maxDimension: 2048, quality: 72),
    ]) {
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
      'image/png' => 'png',
      'image/gif' => 'gif',
      'image/webp' => 'webp',
      'video/quicktime' => 'mov',
      _ => type == AssetType.video ? 'mp4' : 'jpg',
    };
  }
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
