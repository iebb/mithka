import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mithka/media/app_asset_picker.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

/// Records which image_picker entry point the system picker used.
class _FakeImagePicker extends ImagePicker {
  _FakeImagePicker(this.files);

  final List<XFile> files;
  final calls = <String>[];
  int? limit;
  bool? fullMetadata;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    calls.add('pickImage:${source.name}');
    fullMetadata = requestFullMetadata;
    return files.firstOrNull;
  }

  @override
  Future<List<XFile>> pickMultiImage({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    int? limit,
    bool requestFullMetadata = true,
  }) async {
    calls.add('pickMultiImage');
    this.limit = limit;
    fullMetadata = requestFullMetadata;
    return files;
  }

  @override
  Future<List<XFile>> pickMultiVideo({
    Duration? maxDuration,
    int? limit,
  }) async {
    calls.add('pickMultiVideo');
    this.limit = limit;
    return files;
  }

  @override
  Future<List<XFile>> pickMultipleMedia({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    int? limit,
    bool requestFullMetadata = true,
  }) async {
    calls.add('pickMultipleMedia');
    this.limit = limit;
    fullMetadata = requestFullMetadata;
    return files;
  }
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('system-picker'));
  tearDown(() => dir.deleteSync(recursive: true));

  XFile write(String name, List<int> bytes) {
    final file = File('${dir.path}/$name')..writeAsBytesSync(bytes);
    return XFile(file.path);
  }

  test('multiple media go through the photo picker untouched', () async {
    final still = write('a.jpg', [0xff, 0xd8, 0xff, 0xe0]);
    final gif = write('b', 'GIF89a....'.codeUnits);
    final video = write('c.mp4', [0, 0, 0, 0x18]);
    final picker = _FakeImagePicker([still, gif, video]);

    final selection = await AppAssetPicker.pickWithSystemPicker(
      type: AppAssetPickerType.imageAndVideo,
      maxAssets: 10,
      picker: picker,
    );

    expect(picker.calls, ['pickMultipleMedia']);
    expect(picker.limit, 10);
    // Full metadata on iOS needs the library permission this path avoids.
    expect(picker.fullMetadata, isFalse);
    expect(
      [for (final a in selection.assets) a.file.path],
      [still.path, gif.path, video.path],
    );
    expect(
      [for (final a in selection.assets) a.isAnimatedImage],
      [false, true, false],
    );
    expect(
      [for (final a in selection.assets) a.originalFile?.path],
      [still.path, gif.path, video.path],
    );
    expect(selection.failedCount, 0);
  });

  test(
    'a single photo uses the gallery, and extra picks are dropped',
    () async {
      final single = _FakeImagePicker([
        write('a.jpg', const [0xff]),
      ]);
      final one = await AppAssetPicker.pickWithSystemPicker(
        type: AppAssetPickerType.image,
        maxAssets: 1,
        picker: single,
      );
      expect(single.calls, ['pickImage:gallery']);
      expect(single.fullMetadata, isFalse);
      expect(one.assets, hasLength(1));

      final videos = _FakeImagePicker([
        write('a.mp4', const [0]),
        write('b.mp4', const [0]),
        write('c.mp4', const [0]),
      ]);
      final two = await AppAssetPicker.pickWithSystemPicker(
        type: AppAssetPickerType.video,
        maxAssets: 2,
        picker: videos,
      );
      expect(videos.calls, ['pickMultiVideo']);
      expect(two.assets, hasLength(2));
    },
  );

  test('the system picker preference persists', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    expect(theme.useSystemPhotoPicker, isFalse);

    theme.useSystemPhotoPicker = true;

    expect(prefs.getBool('useSystemPhotoPicker'), isTrue);
    expect(ThemeController(prefs).useSystemPhotoPicker, isTrue);
  });

  testWidgets('limited access opens on the grid, not the settings page', (
    tester,
  ) async {
    late AssetPickerConfig config;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) {
            config = AppAssetPicker.buildConfig(
              context,
              type: AppAssetPickerType.image,
            );
            return const SizedBox();
          },
        ),
      ),
    );
    expect(
      config.limitedPermissionOverlayPredicate?.call(PermissionState.limited),
      isFalse,
    );
  });
}
