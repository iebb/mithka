import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../theme/app_theme.dart';

enum AppAssetPickerType { image, video, imageAndVideo }

abstract final class AppAssetPicker {
  static Future<List<XFile>> pick(
    BuildContext context, {
    required AppAssetPickerType type,
    int maxAssets = 9,
    Duration? maxVideoDuration,
  }) async {
    if (maxAssets <= 0) return const [];
    final assets = await AssetPicker.pickAssets(
      context,
      pickerConfig: buildConfig(
        context,
        type: type,
        maxAssets: maxAssets,
        maxVideoDuration: maxVideoDuration,
      ),
    );
    if (assets == null || assets.isEmpty) return const [];

    return Future.wait(assets.map(_materialize));
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

  static Future<XFile> _materialize(AssetEntity asset) async {
    final file = await asset.originFile ?? await asset.file;
    if (file == null) {
      throw StateError('Unable to read selected asset ${asset.id}');
    }
    return XFile(file.path, mimeType: asset.mimeType);
  }
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
