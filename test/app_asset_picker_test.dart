import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mithka/media/app_asset_picker.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

void main() {
  testWidgets('picker config follows app theme and requested asset type', (
    tester,
  ) async {
    AssetPickerConfig? config;
    ThemeData? pickerTheme;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.light,
          extensions: [AppColors.light],
        ),
        home: Builder(
          builder: (context) {
            config = AppAssetPicker.buildConfig(
              context,
              type: AppAssetPickerType.video,
              maxAssets: 1,
              maxVideoDuration: const Duration(seconds: 10),
            );
            pickerTheme = AppAssetPicker.pickerTheme(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(config?.requestType, RequestType.video);
    expect(config?.maxAssets, 1);
    expect(config?.gridCount, 4);
    expect(config?.pageSize, 80);
    final filter = config?.filterOptions as FilterOptionGroup;
    expect(
      filter.getOption(AssetType.video).durationConstraint.max,
      const Duration(seconds: 10),
    );
    expect(pickerTheme?.colorScheme.primary, AppTheme.brand);
    expect(
      pickerTheme?.scaffoldBackgroundColor,
      AppColors.light.groupedBackground,
    );
    expect(pickerTheme?.appBarTheme.backgroundColor, AppColors.light.navBar);
  });

  testWidgets('picker uses a denser tablet grid', (tester) async {
    AssetPickerConfig? config;
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            config = AppAssetPicker.buildConfig(
              context,
              type: AppAssetPickerType.imageAndVideo,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(config?.gridCount, 6);
    expect(config?.pageSize, 120);
  });

  test('picked media type uses MIME type and file extension', () {
    expect(
      isPickedAssetVideo(
        XFile('/tmp/no-extension', mimeType: 'video/quicktime'),
      ),
      isTrue,
    );
    expect(isPickedAssetVideo(XFile('/tmp/clip.MOV')), isTrue);
    expect(isPickedAssetGif(XFile('/tmp/reaction.GIF')), isTrue);
    expect(isPickedAssetVideo(XFile('/tmp/photo.jpg')), isFalse);
  });

  test('photo send thumbnail size preserves aspect ratio', () {
    expect(
      scaledPhotoThumbnailSize(4032, 3024, 4096),
      const ThumbnailSize(4032, 3024),
    );
    expect(
      scaledPhotoThumbnailSize(8064, 6048, 4096),
      const ThumbnailSize(4096, 3072),
    );
    expect(
      scaledPhotoThumbnailSize(3024, 4032, 3200),
      const ThumbnailSize(2400, 3200),
    );
  });
}
