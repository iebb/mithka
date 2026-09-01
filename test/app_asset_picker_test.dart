import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/media/app_asset_picker.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:provider/provider.dart';
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

  testWidgets('picker header uses owned icons without Material glyphs', (
    tester,
  ) async {
    final provider = DefaultAssetPickerProvider.forTest(
      requestType: RequestType.common,
      maxAssets: 10,
    );
    final delegate = AppAssetPickerBuilderDelegate(
      provider: provider,
      initialPermission: PermissionState.authorized,
      config: const AssetPickerConfig(maxAssets: 10),
      locale: const Locale('en'),
    );
    addTearDown(delegate.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        home: Builder(
          builder: (context) => Column(
            children: [
              delegate.backButton(context),
              delegate.pathEntitySelector(context),
            ],
          ),
        ),
      ),
    );

    final icons = tester.widgetList<AppIcon>(find.byType(AppIcon)).toList();
    expect(icons.map((icon) => icon.icon), contains(HeroAppIcons.xmark));
    expect(icons.map((icon) => icon.icon), contains(HeroAppIcons.chevronDown));
    expect(tester.takeException(), isNull);
  });

  testWidgets('limited-access tip and video badge carry no Material glyphs', (
    tester,
  ) async {
    final provider = DefaultAssetPickerProvider.forTest(
      requestType: RequestType.common,
      maxAssets: 10,
    );
    final delegate = AppAssetPickerBuilderDelegate(
      provider: provider,
      // The tip only exists while the OS granted partial access.
      initialPermission: PermissionState.limited,
      config: const AssetPickerConfig(maxAssets: 10),
      locale: const Locale('en'),
    );
    addTearDown(delegate.dispose);
    final video = AssetEntity(
      id: '1',
      typeInt: 2,
      width: 100,
      height: 100,
      duration: 6,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        home: Builder(
          builder: (context) => Column(
            children: [
              delegate.accessLimitedBottomTip(context),
              SizedBox(
                height: 60,
                width: 60,
                child: delegate.videoIndicator(context, video),
              ),
            ],
          ),
        ),
      ),
    );

    final glyphs = tester
        .widgetList<Icon>(find.byType(Icon))
        .map((icon) => icon.icon)
        .whereType<IconData>();
    expect(glyphs, isNotEmpty);
    // The package reaches for Icons.warning, Icons.keyboard_arrow_right and
    // Icons.videocam here. Mithka bundles no Material Icons font, so any that
    // survive draw as tofu boxes.
    expect(
      glyphs.where((glyph) => glyph.fontFamily == 'MaterialIcons'),
      isEmpty,
      reason: 'a Material codepoint has no glyph to render',
    );

    final owned = tester
        .widgetList<AppIcon>(find.byType(AppIcon))
        .map((icon) => icon.icon);
    expect(owned, contains(HeroAppIcons.triangleExclamation));
    expect(owned, contains(HeroAppIcons.chevronRight));
    expect(owned, contains(HeroAppIcons.solidFileVideo));
    expect(find.text('00:06'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview header uses owned icons and the app text style', (
    tester,
  ) async {
    final asset = AssetEntity(id: '1', typeInt: 1, width: 100, height: 100);
    final delegate = AppAssetPickerViewerDelegate(
      currentIndex: 0,
      previewAssets: <AssetEntity>[asset],
      themeData: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'PickerProbeFont',
        extensions: [AppColors.dark],
      ),
      provider: AssetPickerViewerProvider<AssetEntity>(<AssetEntity>[
        asset,
      ], maxAssets: 10),
    );
    // No dispose: the package only builds the delegate's tickers when the
    // viewer widget mounts, and this test drives the header on its own.

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.dark]),
        home: const SizedBox.shrink(),
      ),
    );
    // The header only draws its back affordance on a route that can pop.
    unawaited(
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(
            MaterialPageRoute<void>(
              builder: (context) => Stack(children: [delegate.appBar(context)]),
            ),
          ),
    );
    await tester.pumpAndSettle();

    final icons = tester.widgetList<AppIcon>(find.byType(AppIcon)).toList();
    expect(icons.map((icon) => icon.icon), contains(HeroAppIcons.chevronLeft));
    // The package draws this header with Material Icons codepoints, which the
    // app does not bundle, so they render as tofu on iOS.
    final glyphs = tester.widgetList<Icon>(find.byType(Icon));
    expect(glyphs, isNotEmpty);
    expect(
      glyphs.map((glyph) => glyph.icon?.fontFamily),
      isNot(contains('MaterialIcons')),
    );
    // The style is explicit rather than inherited from a theme the picker
    // route may not carry.
    expect(find.text('1/1'), findsOneWidget);
    final title = tester.widget<Text>(find.text('1/1'));
    expect(title.style?.fontSize, 17);
    expect(title.style?.color, isNotNull);
    // Named outright, so the counter cannot fall through to the platform's
    // last-resort face the way the package's inherited style did.
    expect(title.style?.fontFamily, 'PickerProbeFont');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the picker carries the send choices in its own bottom bar', (
    tester,
  ) async {
    // No tear-down for either: the delegate owns the options, and the
    // assertions at the end of this test dispose them in that order.
    final options = AppAssetSendOptions();
    final provider = DefaultAssetPickerProvider.forTest(
      requestType: RequestType.common,
      maxAssets: 10,
    );
    final delegate = AppAssetPickerBuilderDelegate(
      provider: provider,
      initialPermission: PermissionState.authorized,
      config: const AssetPickerConfig(maxAssets: 10),
      locale: const Locale('en'),
      sendOptions: options,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        home: ChangeNotifierProvider<DefaultAssetPickerProvider>.value(
          value: provider,
          child: Builder(
            builder: (context) => Align(
              alignment: Alignment.bottomCenter,
              child: delegate.bottomActionBar(context),
            ),
          ),
        ),
      ),
    );

    // 原图, WeChat's send-the-untouched-file switch, rides with the grid
    // instead of a sheet in front of it.
    expect(
      find.text(AppStrings.t(AppStringKeys.gallerySendOriginal)),
      findsOneWidget,
    );
    expect(options.sendOriginal.value, isFalse);
    await tester.tap(find.byKey(const ValueKey('pickerSendOriginal')));
    await tester.pump();
    expect(options.sendOriginal.value, isTrue);

    // The motion-photo switch stays out of the way until one is picked.
    expect(find.byKey(const ValueKey('pickerSendLiveAsVideo')), findsNothing);
    provider.selectAsset(
      AssetEntity(id: '2', typeInt: 1, width: 1, height: 1, subtype: 8),
    );
    await tester.pump();
    expect(
      find.text(AppStrings.t(AppStringKeys.gallerySendLiveAsVideo)),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('pickerSendLiveAsVideo')));
    await tester.pump();
    expect(options.sendLiveAsVideo.value, isTrue);

    // The toggles belong to the picker route: they outlive the grid's widgets
    // and go away with the delegate, so nothing can be listening by then.
    await tester.pumpWidget(const SizedBox.shrink());
    delegate.dispose();
    expect(
      () => options.sendOriginal.addListener(() {}),
      throwsA(isA<FlutterError>()),
    );
  });

  test('send options map the WeChat toggles onto materialisation', () {
    final options = AppAssetSendOptions();
    addTearDown(options.dispose);

    // Off: a downscaled copy, the same 1280 px cap the old sheet's default had.
    expect(options.photoMaxDimension, 1280);
    expect(options.preserveOriginalFiles, isFalse);
    expect(options.preferLivePhotoVideo, isFalse);

    // 原图: the untouched file, so no cap and no compression pass.
    options.sendOriginal.value = true;
    expect(options.photoMaxDimension, isNull);
    expect(options.preserveOriginalFiles, isTrue);

    options.sendLiveAsVideo.value = true;
    expect(options.preferLivePhotoVideo, isTrue);
  });

  test('a picker without send options keeps the caller\'s own quality', () {
    final delegate = AppAssetPickerBuilderDelegate(
      provider: DefaultAssetPickerProvider.forTest(
        requestType: RequestType.common,
        maxAssets: 10,
      ),
      initialPermission: PermissionState.authorized,
      config: const AssetPickerConfig(maxAssets: 10),
      locale: const Locale('en'),
    );
    addTearDown(delegate.dispose);
    expect(delegate.sendOptions, isNull);
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

  test('document picks preserve safe gallery filenames and extensions', () {
    expect(
      pickedAssetDocumentFileName(
        title: 'IMG_1234.HEIC',
        sourcePath: '/tmp/rendered.jpg',
        fallbackExtension: 'heic',
      ),
      'IMG_1234.HEIC',
    );
    expect(
      pickedAssetDocumentFileName(
        title: null,
        sourcePath: '/tmp/clip.MOV',
        fallbackExtension: 'mov',
      ),
      'clip.MOV',
    );
    expect(
      pickedAssetDocumentFileName(
        title: '..',
        sourcePath: '/tmp/photo.jpg',
        fallbackExtension: 'jpg',
      ),
      'attachment.jpg',
    );
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
