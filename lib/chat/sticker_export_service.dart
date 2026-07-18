import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:fvp/fvp.dart';
import 'package:image/image.dart' as image_lib;
import 'package:lottie/lottie.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';
import 'media_library_saver.dart';

enum StickerExportFormat { png, gif, mov, lottie }

enum StickerExportDestination { photos, files }

enum StickerExportResult {
  saved,
  cancelled,
  permissionDenied,
  unsupported,
  failed,
}

extension StickerExportFormatLabel on StickerExportFormat {
  String label({required bool animated}) => switch (this) {
    StickerExportFormat.png => animated ? 'APNG' : 'PNG',
    StickerExportFormat.gif => 'GIF',
    StickerExportFormat.mov => 'MOV',
    StickerExportFormat.lottie => 'Lottie JSON',
  };

  String get extension => switch (this) {
    StickerExportFormat.png => 'png',
    StickerExportFormat.gif => 'gif',
    StickerExportFormat.mov => 'mov',
    StickerExportFormat.lottie => 'json',
  };
}

class StickerExportService {
  const StickerExportService._();

  static const MethodChannel _channel = MethodChannel('mithka/sticker_export');
  static const int _maximumDimension = 512;
  static const int _maximumFrames = 180;

  static bool isAnimated(ChatMessage message) =>
      message.animatedSticker != null || message.videoSticker != null;

  static List<StickerExportFormat> availableFormats(
    ChatMessage message, {
    bool? supportsMov,
  }) => [
    StickerExportFormat.png,
    StickerExportFormat.gif,
    if (supportsMov ?? defaultTargetPlatform == TargetPlatform.iOS)
      StickerExportFormat.mov,
    if (message.animatedSticker != null) StickerExportFormat.lottie,
  ];

  static Future<StickerExportResult> export(
    ChatMessage message, {
    required StickerExportFormat format,
    required StickerExportDestination destination,
  }) async {
    if (!_isSupportedPlatform(destination)) {
      return StickerExportResult.unsupported;
    }
    if (format == StickerExportFormat.mov && !Platform.isIOS) {
      return StickerExportResult.unsupported;
    }
    if (format == StickerExportFormat.lottie &&
        (destination == StickerExportDestination.photos ||
            message.animatedSticker == null)) {
      return StickerExportResult.unsupported;
    }

    File? output;
    try {
      output = await _prepare(message, format);
      if (output == null || !await output.exists()) {
        return StickerExportResult.failed;
      }

      if (destination == StickerExportDestination.photos) {
        final result = await MediaLibrarySaver.savePreparedFile(
          output,
          isVideo: format == StickerExportFormat.mov,
          creationDate: DateTime.fromMillisecondsSinceEpoch(
            message.date * 1000,
          ),
        );
        return switch (result) {
          MediaLibrarySaveResult.saved => StickerExportResult.saved,
          MediaLibrarySaveResult.permissionDenied =>
            StickerExportResult.permissionDenied,
          MediaLibrarySaveResult.unsupported => StickerExportResult.unsupported,
          MediaLibrarySaveResult.failed => StickerExportResult.failed,
        };
      }

      final bytes = await output.readAsBytes();
      final selectedPath = await FilePicker.platform.saveFile(
        fileName: output.uri.pathSegments.last,
        type: FileType.custom,
        allowedExtensions: [format.extension],
        bytes: bytes,
      );
      if (selectedPath != null && !Platform.isIOS && !Platform.isAndroid) {
        await File(selectedPath).writeAsBytes(bytes, flush: true);
      }
      return selectedPath == null
          ? StickerExportResult.cancelled
          : StickerExportResult.saved;
    } on PlatformException catch (error) {
      if (error.code == 'sticker_export_unsupported') {
        return StickerExportResult.unsupported;
      }
      return StickerExportResult.failed;
    } catch (_) {
      return StickerExportResult.failed;
    } finally {
      if (output != null) {
        try {
          if (await output.exists()) await output.delete();
        } catch (_) {}
      }
    }
  }

  static bool _isSupportedPlatform(StickerExportDestination destination) {
    if (destination == StickerExportDestination.photos) {
      return Platform.isIOS || Platform.isAndroid;
    }
    return Platform.isIOS ||
        Platform.isAndroid ||
        Platform.isMacOS ||
        Platform.isWindows ||
        Platform.isLinux;
  }

  static Future<File?> _prepare(
    ChatMessage message,
    StickerExportFormat format,
  ) async {
    final source =
        message.animatedSticker ?? message.videoSticker ?? message.image;
    if (source == null) return null;
    final sourcePath = await TdFileCenter.shared.pathFor(source);
    if (sourcePath == null || sourcePath.isEmpty) return null;
    final input = File(sourcePath);
    if (!await input.exists()) return null;

    final directory = Directory(
      '${(await getTemporaryDirectory()).path}/mithka-sticker-export',
    );
    await directory.create(recursive: true);
    final sourceName = message.isAnimatedEmoji ? 'emoji' : 'sticker';
    final baseName =
        '$sourceName-${message.id}-${DateTime.now().microsecondsSinceEpoch}';
    if (format == StickerExportFormat.lottie) {
      if (message.animatedSticker == null) return null;
      final json = decodeTgsLottie(await input.readAsBytes());
      if (json == null) return null;
      final output = File('${directory.path}/$baseName.json');
      await output.writeAsBytes(json, flush: true);
      return output;
    }

    final intermediateFormat = format == StickerExportFormat.mov
        ? StickerExportFormat.png
        : format;
    final bytes = message.animatedSticker != null
        ? await _encodeTgs(input, intermediateFormat)
        : message.videoSticker != null
        ? await _encodeVideo(input, intermediateFormat)
        : await _encodeStatic(input, intermediateFormat);
    if (bytes == null || bytes.isEmpty) return null;

    final intermediate = File(
      '${directory.path}/$baseName.${intermediateFormat.extension}',
    );
    await intermediate.writeAsBytes(bytes, flush: true);

    if (format != StickerExportFormat.mov) return intermediate;
    try {
      final outputPath = await _channel.invokeMethod<String>('encodeAlphaMov', {
        'path': intermediate.path,
      });
      if (outputPath == null || outputPath.isEmpty) return null;
      return File(outputPath);
    } finally {
      try {
        if (await intermediate.exists()) await intermediate.delete();
      } catch (_) {}
    }
  }

  static Future<Uint8List?> _encodeStatic(
    File input,
    StickerExportFormat format,
  ) async {
    final decoded = image_lib.decodeImage(await input.readAsBytes());
    if (decoded == null) return null;
    final frame = decoded.frames.first;
    frame.frameDuration = 100;
    final encoder = _StickerFrameEncoder(format, frameCount: 1);
    encoder.addRgba(
      frame.getBytes(order: image_lib.ChannelOrder.rgba),
      width: frame.width,
      height: frame.height,
      durationMs: frame.frameDuration,
    );
    return encoder.finish();
  }

  static Future<Uint8List?> _encodeTgs(
    File input,
    StickerExportFormat format,
  ) async {
    final compressed = await input.readAsBytes();
    final json = Uint8List.fromList(GZipDecoder().decodeBytes(compressed));
    final composition = await LottieComposition.fromBytes(json);
    final drawable = LottieDrawable(composition);
    final originalWidth = composition.bounds.width;
    final originalHeight = composition.bounds.height;
    if (originalWidth <= 0 || originalHeight <= 0) return null;
    final outputSize = _fitSize(originalWidth, originalHeight);
    final frameRate = composition.frameRate.clamp(1.0, 60.0);
    final frameCount = (composition.seconds * frameRate).ceil().clamp(
      1,
      _maximumFrames,
    );
    final durationMs = (composition.duration.inMilliseconds / frameCount)
        .round()
        .clamp(16, 1000);
    final encoder = _StickerFrameEncoder(format, frameCount: frameCount);

    for (var index = 0; index < frameCount; index++) {
      drawable.setProgress(index / frameCount);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      drawable.draw(
        canvas,
        ui.Rect.fromLTWH(
          0,
          0,
          outputSize.$1.toDouble(),
          outputSize.$2.toDouble(),
        ),
      );
      final picture = recorder.endRecording();
      final rendered = await picture.toImage(outputSize.$1, outputSize.$2);
      picture.dispose();
      final byteData = await rendered.toByteData();
      rendered.dispose();
      if (byteData == null) return null;
      encoder.addRgba(
        byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        ),
        width: outputSize.$1,
        height: outputSize.$2,
        durationMs: durationMs,
      );
      if (index % 4 == 3) await Future<void>.delayed(Duration.zero);
    }
    return encoder.finish();
  }

  @visibleForTesting
  static Uint8List? decodeTgsLottie(Uint8List compressed) {
    try {
      final json = Uint8List.fromList(GZipDecoder().decodeBytes(compressed));
      final document = jsonDecode(utf8.decode(json));
      if (document is! Map<String, dynamic> ||
          document['fr'] is! num ||
          document['ip'] is! num ||
          document['op'] is! num ||
          document['layers'] is! List) {
        return null;
      }
      return json;
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _encodeVideo(
    File input,
    StickerExportFormat format,
  ) async {
    final controller = VideoPlayerController.file(input);
    try {
      await controller.initialize();
      await controller.setVolume(0);
      await controller.pause();
      final media = controller.getMediaInfo();
      final video = media?.video?.firstOrNull;
      final sourceWidth =
          video?.codec.width ?? controller.value.size.width.round();
      final sourceHeight =
          video?.codec.height ?? controller.value.size.height.round();
      if (sourceWidth <= 0 || sourceHeight <= 0) return null;
      final outputSize = _fitSize(sourceWidth, sourceHeight);
      final durationMs = controller.value.duration.inMilliseconds > 0
          ? controller.value.duration.inMilliseconds
          : (media?.duration ?? 0);
      if (durationMs <= 0) return null;
      final frameRate = (video?.codec.frameRate ?? 30.0).clamp(1.0, 60.0);
      final frameCount = (durationMs / 1000 * frameRate).ceil().clamp(
        1,
        _maximumFrames,
      );
      final frameDuration = (durationMs / frameCount).round().clamp(16, 1000);
      final encoder = _StickerFrameEncoder(format, frameCount: frameCount);

      for (var index = 0; index < frameCount; index++) {
        final position = Duration(
          milliseconds: (durationMs * index / frameCount).round(),
        );
        await controller.seekTo(position);
        await Future<void>.delayed(const Duration(milliseconds: 8));
        final rgba = await controller.snapshot(
          width: outputSize.$1,
          height: outputSize.$2,
        );
        if (rgba == null || rgba.length < outputSize.$1 * outputSize.$2 * 4) {
          return null;
        }
        encoder.addRgba(
          rgba,
          width: outputSize.$1,
          height: outputSize.$2,
          durationMs: frameDuration,
        );
      }
      return encoder.finish();
    } finally {
      await controller.dispose();
    }
  }

  static (int, int) _fitSize(num width, num height) {
    final scale = width > height
        ? (_maximumDimension / width).clamp(0.0, 1.0)
        : (_maximumDimension / height).clamp(0.0, 1.0);
    return (
      (width * scale).round().clamp(1, _maximumDimension),
      (height * scale).round().clamp(1, _maximumDimension),
    );
  }

  @visibleForTesting
  static Uint8List? encodeRgbaFramesForTest(
    List<Uint8List> frames, {
    required int width,
    required int height,
    required int durationMs,
    required StickerExportFormat format,
  }) {
    if (format == StickerExportFormat.lottie) return null;
    final encoder = _StickerFrameEncoder(format, frameCount: frames.length);
    for (final frame in frames) {
      encoder.addRgba(
        frame,
        width: width,
        height: height,
        durationMs: durationMs,
      );
    }
    return encoder.finish();
  }
}

class _StickerFrameEncoder {
  _StickerFrameEncoder(this.format, {required int frameCount}) {
    if (format == StickerExportFormat.png) _png.start(frameCount);
  }

  final StickerExportFormat format;
  final image_lib.PngEncoder _png = image_lib.PngEncoder();
  final image_lib.GifEncoder _gif = image_lib.GifEncoder();

  void addRgba(
    Uint8List rgba, {
    required int width,
    required int height,
    required int durationMs,
  }) {
    final image = image_lib.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgba.buffer,
      bytesOffset: rgba.offsetInBytes,
      numChannels: 4,
      order: image_lib.ChannelOrder.rgba,
      frameDuration: durationMs,
    );
    if (format == StickerExportFormat.png) {
      _png.addFrame(image);
    } else {
      _gif.addFrame(image, duration: (durationMs / 10).round().clamp(2, 100));
    }
  }

  Uint8List? finish() =>
      format == StickerExportFormat.png ? _png.finish() : _gif.finish();
}
