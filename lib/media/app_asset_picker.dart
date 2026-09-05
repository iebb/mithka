import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../theme/app_theme.dart';

enum AppAssetPickerType { image, video, imageAndVideo }

/// The send choices WeChat keeps inside the picker itself rather than in a
/// sheet in front of it: 原图 (send the untouched original instead of a
/// downscaled copy) and, once a Live Photo is in the selection, sending its
/// motion component as a video.
class AppAssetSendOptions {
  /// Hand one to [AppAssetPicker.pickDetailed], which passes ownership to the
  /// picker route and disposes it when that route goes away.
  AppAssetSendOptions({this.scaledMaxDimension = 1280});

  /// Longest edge a photo is resized to while [sendOriginal] is off.
  final int scaledMaxDimension;

  final ValueNotifier<bool> sendOriginal = ValueNotifier<bool>(false);
  final ValueNotifier<bool> sendLiveAsVideo = ValueNotifier<bool>(false);

  int? get photoMaxDimension => sendOriginal.value ? null : scaledMaxDimension;
  bool get preserveOriginalFiles => sendOriginal.value;
  bool get preferLivePhotoVideo => sendLiveAsVideo.value;

  void dispose() {
    sendOriginal.dispose();
    sendLiveAsVideo.dispose();
  }
}

class AppPickedAsset {
  const AppPickedAsset({
    required this.file,
    this.originalFile,
    this.thumbnailBytes,
    this.width,
    this.height,
    this.isAnimatedImage = false,
    this.isLivePhoto = false,
  });

  final XFile file;
  final XFile? originalFile;
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

  /// [sendOptions] hands the quality choices to the picker's own bottom bar.
  /// The values it carries when the picker closes win over
  /// [preferLivePhotoVideo], [preserveOriginalFiles] and [photoMaxDimension].
  static Future<AppAssetPickerSelection> pickDetailed(
    BuildContext context, {
    required AppAssetPickerType type,
    int maxAssets = 9,
    Duration? maxVideoDuration,
    bool preferLivePhotoVideo = false,
    bool preserveOriginalFiles = false,
    int? photoMaxDimension,
    AppAssetSendOptions? sendOptions,
  }) async {
    if (maxAssets <= 0) {
      return const AppAssetPickerSelection(assets: [], failedCount: 0);
    }
    Future<AppAssetPickerSelection> materializeAll(
      List<AssetEntity> assets,
    ) async {
      // Read the toggles once, here: the picker route is still tearing down
      // while this runs, and it owns the notifiers.
      final live = sendOptions?.preferLivePhotoVideo ?? preferLivePhotoVideo;
      final original =
          sendOptions?.preserveOriginalFiles ?? preserveOriginalFiles;
      final maxDimension = sendOptions?.photoMaxDimension ?? photoMaxDimension;
      final resolved = <AppPickedAsset>[];
      var failedCount = 0;
      for (final asset in assets) {
        try {
          resolved.add(
            await _materialize(
              asset,
              preferLivePhotoVideo: live,
              preserveOriginalFiles: original,
              photoMaxDimension: maxDimension,
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

    try {
      final assets = await _pickAssets(
        context,
        config: buildConfig(
          context,
          type: type,
          maxAssets: maxAssets,
          maxVideoDuration: maxVideoDuration,
        ),
        sendOptions: sendOptions,
      );
      if (assets == null || assets.isEmpty) {
        return const AppAssetPickerSelection(assets: [], failedCount: 0);
      }
      return materializeAll(assets);
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
        // The permission dialog awaited above; the host route may be gone.
        if (!context.mounted) {
          return const AppAssetPickerSelection(assets: [], failedCount: 0);
        }
        final assets = await _pickAssets(
          context,
          config: buildConfig(
            context,
            type: type,
            maxAssets: maxAssets,
            maxVideoDuration: maxVideoDuration,
          ),
          sendOptions: sendOptions,
        );
        if (assets == null || assets.isEmpty) {
          return const AppAssetPickerSelection(assets: [], failedCount: 0);
        }
        return materializeAll(assets);
      }
      return const AppAssetPickerSelection(assets: [], failedCount: 0);
    }
  }

  static Future<List<AssetEntity>?> _pickAssets(
    BuildContext context, {
    required AssetPickerConfig config,
    AppAssetSendOptions? sendOptions,
  }) async {
    final permissionRequestOption = PermissionRequestOption(
      androidPermission: AndroidPermission(
        type: config.requestType,
        mediaLocation: false,
      ),
    );
    final initialPermission = await AssetPicker.permissionCheck(
      requestOption: permissionRequestOption,
    );
    if (!context.mounted) return null;

    final provider = DefaultAssetPickerProvider(
      maxAssets: config.maxAssets,
      pageSize: config.pageSize,
      pathThumbnailSize: config.pathThumbnailSize,
      selectedAssets: config.selectedAssets,
      requestType: config.requestType,
      sortPathDelegate: config.sortPathDelegate,
      sortPathsByModifiedDate: config.sortPathsByModifiedDate,
      filterOptions: config.filterOptions,
    );
    final delegate = AppAssetPickerBuilderDelegate(
      provider: provider,
      initialPermission: initialPermission,
      config: config,
      locale: Localizations.maybeLocaleOf(context),
      sendOptions: sendOptions,
    );
    final picker =
        AssetPicker<
          AssetEntity,
          AssetPathEntity,
          AppAssetPickerBuilderDelegate
        >(permissionRequestOption: permissionRequestOption, builder: delegate);
    return Navigator.maybeOf(
      context,
      rootNavigator: true,
    )?.push(AssetPickerPageRoute<List<AssetEntity>>(builder: (_) => picker));
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
    // Force the app's family onto every entry rather than trusting each one to
    // already carry it: the package styles text the app never sees, and a
    // family it cannot resolve falls through to whatever the platform picks
    // last (a serif face on iOS).
    final appBody = appTheme.textTheme.bodyMedium;
    final textTheme = appTheme.textTheme.apply(
      fontFamily: appBody?.fontFamily,
      fontFamilyFallback: appBody?.fontFamilyFallback,
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
    final mediaFileUsesOriginal =
        preserveOriginalFiles ||
        asset.type == AssetType.video ||
        livePhotoAsVideo ||
        preserveOriginalAnimatedImage;
    final file = await asset.loadFile(
      isOrigin: mediaFileUsesOriginal,
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
    final targetDirectory = mediaFileUsesOriginal
        ? await Directory(
            '${directory.path}/mithka-picker-$timestamp-${asset.id.hashCode}',
          ).create(recursive: true)
        : directory;
    final durableName = mediaFileUsesOriginal
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
    XFile originalPickedFile;
    if (mediaFileUsesOriginal) {
      originalPickedFile = XFile(
        durableFile.path,
        mimeType: mimeType,
        name: durableName,
      );
    } else {
      final originalSource = await asset.loadFile(
        withSubtype: livePhotoAsVideo,
        darwinFileType: livePhotoAsVideo ? PMDarwinAVFileType.mp4 : null,
      );
      if (originalSource == null) {
        throw StateError('Unable to read original selected asset ${asset.id}');
      }
      final originalExtension = livePhotoAsVideo
          ? 'mp4'
          : _fileExtension(originalSource.path, mimeType, asset.type);
      final originalName = pickedAssetDocumentFileName(
        title: asset.title,
        sourcePath: originalSource.path,
        fallbackExtension: originalExtension,
      );
      final originalDirectory = await Directory(
        '${directory.path}/mithka-picker-original-$timestamp-${asset.id.hashCode}',
      ).create(recursive: true);
      final durableOriginal = File('${originalDirectory.path}/$originalName');
      await originalSource.copy(durableOriginal.path);
      originalPickedFile = XFile(
        durableOriginal.path,
        mimeType: mimeType,
        name: originalName,
      );
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
      originalFile: originalPickedFile,
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

/// App-owned chrome for the third-party asset grid.
///
/// Mithka deliberately does not bundle Material Icons. The package defaults
/// therefore resolve private-use icon codepoints through the user's text font,
/// which produces corrupted letters or question marks on iOS. Keep the picker
/// behavior while replacing its visible header glyphs with project icons.
class AppAssetPickerBuilderDelegate
    extends DefaultAssetPickerBuilderDelegate<DefaultAssetPickerProvider> {
  AppAssetPickerBuilderDelegate({
    required super.provider,
    required super.initialPermission,
    required AssetPickerConfig config,
    required super.locale,
    this.sendOptions,
  }) : super(
         gridCount: config.gridCount,
         pickerTheme: config.pickerTheme,
         gridThumbnailSize: config.gridThumbnailSize,
         previewThumbnailSize: config.previewThumbnailSize,
         specialPickerType: config.specialPickerType,
         specialItems: config.specialItems,
         loadingIndicatorBuilder: config.loadingIndicatorBuilder,
         selectPredicate: config.selectPredicate,
         shouldRevertGrid: config.shouldRevertGrid,
         limitedPermissionOverlayPredicate:
             config.limitedPermissionOverlayPredicate,
         pathNameBuilder: config.pathNameBuilder,
         assetsChangeCallback: config.assetsChangeCallback,
         assetsChangeRefreshPredicate: config.assetsChangeRefreshPredicate,
         textDelegate: config.textDelegate,
         themeColor: config.themeColor,
         keepScrollOffset: config.keepScrollOffset,
         shouldAutoplayPreview: config.shouldAutoplayPreview,
         dragToSelect: config.dragToSelect,
         enableLivePhoto: config.enableLivePhoto,
       );

  /// Present when the caller wants the quality choices in the picker's own
  /// bottom bar instead of a sheet in front of it. The delegate takes
  /// ownership: the toggles are listened to by widgets on this route, so they
  /// can only be disposed once the route is, which is what [dispose] does.
  final AppAssetSendOptions? sendOptions;

  @override
  void dispose() {
    sendOptions?.dispose();
    super.dispose();
  }

  @override
  Widget backButton(BuildContext context) {
    final color = theme.iconTheme.color ?? theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: AppInteractiveSurface(
        semanticLabel: MaterialLocalizations.of(context).closeButtonTooltip,
        onTap: () => Navigator.maybeOf(context)?.maybePop(),
        borderRadius: BorderRadius.circular(24),
        showHover: false,
        showFocusRing: false,
        child: SizedBox.square(
          dimension: 48,
          child: Center(
            child: AppIcon(HeroAppIcons.xmark, size: 22, color: color),
          ),
        ),
      ),
    );
  }

  @override
  Widget pathEntitySelector(BuildContext context) {
    Widget pathText(String text, String semanticsText) => Flexible(
      child: Text(
        text,
        semanticsLabel: semanticsText,
        maxLines: 1,
        overflow: TextOverflow.fade,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w400),
      ),
    );

    return UnconstrainedBox(
      child: GestureDetector(
        onTap: () {
          if (isPermissionLimited && provider.isAssetsEmpty) {
            PhotoManager.presentLimited();
            return;
          }
          if (provider.currentPath == null) return;
          isSwitchingPath.value = !isSwitchingPath.value;
        },
        child: Container(
          height: appBarItemHeight,
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.5,
          ),
          padding: const EdgeInsetsDirectional.only(start: 12, end: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: theme.focusColor,
          ),
          child: ListenableBuilder(
            listenable: provider,
            builder: (_, _) {
              final path = provider.currentPath?.path;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (path == null && isPermissionLimited)
                    pathText(
                      textDelegate.changeAccessibleLimitedAssets,
                      semanticsTextDelegate.changeAccessibleLimitedAssets,
                    ),
                  if (path != null)
                    pathText(
                      isPermissionLimited && path.isAll
                          ? textDelegate.accessiblePathName
                          : pathNameBuilder?.call(path) ?? path.name,
                      isPermissionLimited && path.isAll
                          ? semanticsTextDelegate.accessiblePathName
                          : pathNameBuilder?.call(path) ?? path.name,
                    ),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 5),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (theme.iconTheme.color ?? Colors.black)
                            .withValues(alpha: 0.5),
                      ),
                      child: ValueListenableBuilder<bool>(
                        valueListenable: isSwitchingPath,
                        builder: (_, isSwitchingPath, child) =>
                            Transform.rotate(
                              angle: isSwitchingPath ? math.pi : 0,
                              child: child,
                            ),
                        child: SizedBox.square(
                          dimension: 20,
                          child: Center(
                            child: AppIcon(
                              HeroAppIcons.chevronDown,
                              size: 14,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Tapping a tile picks it, the way WeChat's grid behaves. The package's
  /// default sends the tap to the full-screen viewer instead, which buries
  /// selection behind a second screen; the bottom bar's preview button still
  /// opens the viewer for anyone who wants a closer look.
  @override
  Widget selectedBackdrop(BuildContext context, int index, AssetEntity asset) {
    final indicatorSize = MediaQuery.sizeOf(context).width / gridCount / 3;
    return Positioned.fill(
      child: Consumer<DefaultAssetPickerProvider>(
        builder: (context, provider, _) {
          final selected = provider.selectedAssets.contains(asset);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => selectAsset(context, asset, index, selected),
            child: AnimatedContainer(
              duration: switchingPathDuration,
              padding: EdgeInsets.all(indicatorSize * .35),
              color: selected
                  ? theme.colorScheme.primary.withValues(alpha: .45)
                  : theme.colorScheme.surface.withValues(alpha: .1),
            ),
          );
        },
      ),
    );
  }

  /// The package draws the tick with a Material Icons codepoint, which this
  /// app does not bundle.
  @override
  Widget selectIndicator(BuildContext context, int index, AssetEntity asset) {
    final indicatorSize = MediaQuery.sizeOf(context).width / gridCount / 3;
    final duration = switchingPathDuration * 0.75;
    return PositionedDirectional(
      top: 0,
      end: 0,
      child: Selector<DefaultAssetPickerProvider, String>(
        selector: (_, provider) => provider.selectedDescriptions,
        builder: (context, descriptions, _) {
          final selected = descriptions.contains(asset.toString());
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => selectAsset(context, asset, index, selected),
            child: Container(
              margin: EdgeInsets.all(indicatorSize / 4),
              width: indicatorSize,
              height: indicatorSize,
              alignment: AlignmentDirectional.topEnd,
              child: AnimatedContainer(
                duration: duration,
                width: indicatorSize / 1.25,
                height: indicatorSize / 1.25,
                decoration: BoxDecoration(
                  border: selected
                      ? null
                      : Border.all(
                          color: Colors.white.withValues(alpha: 0.85),
                          width: indicatorSize / 25,
                        ),
                  color: selected ? themeColor : null,
                  shape: BoxShape.circle,
                ),
                child: selected
                    ? Center(
                        child: FittedBox(
                          child: Padding(
                            padding: EdgeInsets.all(indicatorSize / 10),
                            child: isSingleAssetMode
                                ? AppIcon(
                                    HeroAppIcons.check,
                                    size: indicatorSize / 2,
                                    color: Colors.white,
                                  )
                                : Text(
                                    // WeChat numbers the selection rather than
                                    // ticking it, so the send order is visible.
                                    '${context.read<DefaultAssetPickerProvider>().selectedAssets.indexOf(asset) + 1}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          );
        },
      ),
    );
  }

  /// Adds WeChat's in-picker send choices above the preview/confirm row.
  @override
  Widget bottomActionBar(BuildContext context) {
    final options = sendOptions;
    if (options == null) return super.bottomActionBar(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListenableBuilder(
          listenable: provider,
          builder: (context, _) {
            final selected = provider.selectedAssets;
            final showLivePhoto = selected.any((asset) => asset.isLivePhoto);
            return Container(
              color: theme.bottomAppBarTheme.color,
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              child: Row(
                children: [
                  _sendOptionToggle(
                    context,
                    key: const ValueKey('pickerSendOriginal'),
                    label: AppStringKeys.gallerySendOriginal.l10n(context),
                    value: options.sendOriginal,
                  ),
                  if (showLivePhoto) ...[
                    const SizedBox(width: 20),
                    _sendOptionToggle(
                      context,
                      key: const ValueKey('pickerSendLiveAsVideo'),
                      label: AppStringKeys.gallerySendLiveAsVideo.l10n(context),
                      value: options.sendLiveAsVideo,
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        super.bottomActionBar(context),
      ],
    );
  }

  /// Same story as [accessLimitedBottomTip]: the package stamps
  /// `Icons.videocam` beside every video's duration, which without Material
  /// Icons is a tofu box on each video thumbnail in the grid.
  @override
  Widget videoIndicator(BuildContext context, AssetEntity asset) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.maxFinite,
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: AlignmentDirectional.bottomCenter,
            end: AlignmentDirectional.topCenter,
            colors: [theme.splashColor, Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            const AppIcon(
              HeroAppIcons.solidFileVideo,
              size: 20,
              color: Colors.white,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 4),
                child: Text(
                  textDelegate.durationIndicatorBuilder(
                    Duration(seconds: asset.duration),
                  ),
                  maxLines: 1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    decoration: TextDecoration.none,
                  ),
                  strutStyle: const StrutStyle(
                    forceStrutHeight: true,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The package draws this banner with `Icons.warning` and
  /// `Icons.keyboard_arrow_right`. Without Material Icons bundled those two
  /// codepoints have no glyph and render as tofu boxes at either end of the
  /// blue bar. Same layout and same tap target, project icons instead.
  @override
  Widget accessLimitedBottomTip(BuildContext context) {
    final bottomPadding = hasBottomActions
        ? 0.0
        : MediaQuery.paddingOf(context).bottom;
    return GestureDetector(
      onTap: () {
        Feedback.forTap(context);
        PhotoManager.openSetting();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
        ).add(EdgeInsets.only(bottom: bottomPadding)),
        height: permissionLimitedBarHeight + bottomPadding,
        color: theme.primaryColor,
        child: Row(
          children: [
            const SizedBox(width: 5),
            AppIcon(
              HeroAppIcons.triangleExclamation,
              size: 24,
              color: const Color(0xFFFFA726).withValues(alpha: 0.8),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Semantics(
                label: semanticsTextDelegate.accessAllTip,
                child: Text(
                  textDelegate.accessAllTip,
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.textTheme.bodySmall?.color,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
            AppIcon(
              HeroAppIcons.chevronRight,
              size: 20,
              color: (theme.iconTheme.color ?? theme.colorScheme.onSurface)
                  .withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sendOptionToggle(
    BuildContext context, {
    required Key key,
    required String label,
    required ValueNotifier<bool> value,
  }) {
    final onSurface = theme.colorScheme.onSurface;
    return ValueListenableBuilder<bool>(
      key: key,
      valueListenable: value,
      builder: (context, checked, _) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => value.value = !checked,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: checked ? themeColor : Colors.transparent,
                border: checked
                    ? null
                    : Border.all(color: onSurface.withValues(alpha: 0.5)),
              ),
              child: checked
                  ? const Center(
                      child: AppIcon(
                        HeroAppIcons.check,
                        size: 13,
                        color: Colors.white,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                color: onSurface,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Routes the viewer through [AppAssetPickerViewerDelegate] so its header
  /// gets project icons and the app's text style instead of the package's
  /// Material glyphs.
  @override
  Future<void> viewAsset(
    BuildContext context,
    int? index,
    AssetEntity currentAsset,
  ) async {
    final selected = provider.selectedAssets;
    final previewing = index == null ? selected : provider.currentAssets;
    if (previewing.isEmpty) return;
    final effectiveIndex = index ?? previewing.indexOf(currentAsset);
    final result =
        await AssetPickerViewer.pushToViewerWithDelegate<
          AssetEntity,
          AssetPathEntity,
          AssetPickerViewerProvider<AssetEntity>,
          AppAssetPickerViewerDelegate
        >(
          context,
          delegate: AppAssetPickerViewerDelegate(
            currentIndex: effectiveIndex < 0 ? 0 : effectiveIndex,
            previewAssets: previewing.toList(growable: false),
            provider: AssetPickerViewerProvider<AssetEntity>(
              selected,
              maxAssets: provider.maxAssets,
            ),
            themeData: theme,
            previewThumbnailSize: previewThumbnailSize,
            selectedAssets: selected,
            selectorProvider: provider,
            maxAssets: provider.maxAssets,
            selectPredicate: selectPredicate,
            shouldAutoplayPreview: shouldAutoplayPreview,
          ),
        );
    if (result != null && context.mounted) {
      await Navigator.maybeOf(context)?.maybePop(result);
    }
  }
}

/// The preview screen's chrome, for the same reason the grid has its own: the
/// package's header spends Material Icons codepoints this app does not bundle,
/// so the back arrow and the tick render as tofu, and its title leans on a
/// text style the picker theme does not reach.
class AppAssetPickerViewerDelegate
    extends
        DefaultAssetPickerViewerBuilderDelegate<
          AssetPickerViewerProvider<AssetEntity>,
          DefaultAssetPickerProvider
        > {
  AppAssetPickerViewerDelegate({
    required super.currentIndex,
    required super.previewAssets,
    required super.themeData,
    required super.provider,
    super.previewThumbnailSize,
    super.selectedAssets,
    super.selectorProvider,
    super.maxAssets,
    super.selectPredicate,
    super.shouldAutoplayPreview,
    super.enableLivePhoto,
  });

  /// Sourced from the picker theme rather than left to inherit: the package's
  /// header installs its own [DefaultTextStyle], and anything the app has not
  /// put a family on lands on whatever the platform picks last — which is how
  /// the counter ended up in a serif face.
  TextStyle get _titleStyle =>
      (themeData.appBarTheme.titleTextStyle ??
              themeData.textTheme.titleMedium ??
              themeData.textTheme.bodyMedium ??
              const TextStyle())
          .copyWith(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.none,
          );

  @override
  Widget appBar(BuildContext context) {
    final foreground =
        themeData.appBarTheme.foregroundColor ??
        themeData.colorScheme.onSurface;
    final bar = AssetPickerAppBar(
      backgroundColor: themeData.appBarTheme.backgroundColor,
      leading: AppInteractiveSurface(
        semanticLabel: MaterialLocalizations.of(context).backButtonTooltip,
        onTap: () => Navigator.maybeOf(context)?.maybePop(),
        borderRadius: BorderRadius.circular(24),
        showHover: false,
        showFocusRing: false,
        child: SizedBox.square(
          dimension: 48,
          child: Center(
            child: AppIcon(
              HeroAppIcons.chevronLeft,
              size: 22,
              color: foreground,
            ),
          ),
        ),
      ),
      title: StreamBuilder<int>(
        initialData: currentIndex,
        stream: pageStreamController.stream,
        builder: (context, snapshot) => Text(
          '${snapshot.requireData + 1}/${previewAssets.length}',
          style: _titleStyle.copyWith(color: foreground),
        ),
      ),
      actions: [selectButton(context), const SizedBox(width: 14)],
    );
    return ValueListenableBuilder<bool>(
      valueListenable: isDisplayingDetail,
      builder: (context, displaying, child) => AnimatedPositionedDirectional(
        duration: kThemeAnimationDuration,
        curve: Curves.easeInOut,
        top: displaying
            ? 0
            : -(MediaQuery.paddingOf(context).top + bar.preferredSize.height),
        start: 0,
        end: 0,
        child: child!,
      ),
      child: bar,
    );
  }

  @override
  Widget selectButton(BuildContext context) {
    return ChangeNotifierProvider<AssetPickerViewerProvider<AssetEntity>>.value(
      value: provider!,
      child: Consumer<AssetPickerViewerProvider<AssetEntity>>(
        builder: (context, provider, _) {
          final asset = previewAssets[currentIndex];
          final selected = provider.currentlySelectedAssets.contains(asset);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChangingSelected(context, asset, selected),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? themeData.colorScheme.secondary : null,
                border: selected
                    ? null
                    : Border.all(
                        color:
                            themeData.iconTheme.color ??
                            themeData.colorScheme.onSurface,
                      ),
              ),
              child: selected
                  ? const Center(
                      child: AppIcon(
                        HeroAppIcons.check,
                        size: 18,
                        color: Colors.white,
                      ),
                    )
                  : null,
            ),
          );
        },
      ),
    );
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
