import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as image_lib;
import 'package:path_provider/path_provider.dart';

@immutable
class CustomMessageBubbleBackground {
  const CustomMessageBubbleBackground({
    required this.filePath,
    required this.width,
    required this.height,
    required this.stretchX,
    required this.stretchY,
    required this.backgroundColorValue,
    required this.foregroundColorValue,
  });

  factory CustomMessageBubbleBackground.fromJson(Map<String, dynamic> json) {
    final filePath = json['filePath'];
    final width = json['width'];
    final height = json['height'];
    final stretchX = json['stretchX'];
    final stretchY = json['stretchY'];
    final backgroundColorValue = json['backgroundColor'];
    final foregroundColorValue = json['foregroundColor'];
    if (filePath is! String ||
        filePath.isEmpty ||
        width is! int ||
        height is! int ||
        stretchX is! int ||
        stretchY is! int ||
        backgroundColorValue is! int ||
        foregroundColorValue is! int ||
        width < 3 ||
        height < 3 ||
        stretchX <= 0 ||
        stretchX >= width - 1 ||
        stretchY <= 0 ||
        stretchY >= height - 1) {
      throw const FormatException('Invalid custom message bubble');
    }
    return CustomMessageBubbleBackground(
      filePath: filePath,
      width: width,
      height: height,
      stretchX: stretchX,
      stretchY: stretchY,
      backgroundColorValue: backgroundColorValue,
      foregroundColorValue: foregroundColorValue,
    );
  }

  final String filePath;
  final int width;
  final int height;
  final int stretchX;
  final int stretchY;
  final int backgroundColorValue;
  final int foregroundColorValue;

  Rect get centerSlice =>
      Rect.fromLTWH(stretchX.toDouble(), stretchY.toDouble(), 1, 1);

  Size get minimumSize => Size(width.toDouble(), height.toDouble());

  EdgeInsets get contentPadding =>
      const EdgeInsets.symmetric(horizontal: 12, vertical: 9);

  Color get backgroundColor => Color(backgroundColorValue);
  Color get foregroundColor => Color(foregroundColorValue);
  bool get fileExists => File(filePath).existsSync();

  Map<String, dynamic> toJson() => {
    'version': 1,
    'filePath': filePath,
    'width': width,
    'height': height,
    'stretchX': stretchX,
    'stretchY': stretchY,
    'backgroundColor': backgroundColorValue,
    'foregroundColor': foregroundColorValue,
  };
}

enum CustomMessageBubbleImportFailure { invalidPng, tooSmall, tooLarge, write }

class CustomMessageBubbleImportException implements Exception {
  const CustomMessageBubbleImportException(this.failure, [this.cause]);

  final CustomMessageBubbleImportFailure failure;
  final Object? cause;

  @override
  String toString() => 'CustomMessageBubbleImportException($failure)';
}

@immutable
class ProcessedMessageBubblePng {
  const ProcessedMessageBubblePng({
    required this.bytes,
    required this.width,
    required this.height,
    required this.stretchX,
    required this.stretchY,
    required this.backgroundColorValue,
    required this.foregroundColorValue,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final int stretchX;
  final int stretchY;
  final int backgroundColorValue;
  final int foregroundColorValue;
}

class CustomMessageBubblePngProcessor {
  const CustomMessageBubblePngProcessor({
    this.maximumBytes = 16 * 1024 * 1024,
    this.maximumDimension = 2048,
  });

  final int maximumBytes;
  final int maximumDimension;

  ProcessedMessageBubblePng process(Uint8List bytes) {
    if (bytes.length > maximumBytes) {
      throw const CustomMessageBubbleImportException(
        CustomMessageBubbleImportFailure.tooLarge,
      );
    }
    if (!_hasPngSignature(bytes)) {
      throw const CustomMessageBubbleImportException(
        CustomMessageBubbleImportFailure.invalidPng,
      );
    }
    final decoded = image_lib.decodePng(bytes);
    if (decoded == null) {
      throw const CustomMessageBubbleImportException(
        CustomMessageBubbleImportFailure.invalidPng,
      );
    }
    if (decoded.width < 3 || decoded.height < 3) {
      throw const CustomMessageBubbleImportException(
        CustomMessageBubbleImportFailure.tooSmall,
      );
    }
    if (decoded.width > maximumDimension || decoded.height > maximumDimension) {
      throw const CustomMessageBubbleImportException(
        CustomMessageBubbleImportFailure.tooLarge,
      );
    }

    final horizontal = _collapseRepeatedColumns(decoded);
    final compact = _collapseRepeatedRows(horizontal.image);
    final center = compact.image.getPixel(horizontal.stretch, compact.stretch);
    final background = Color.fromARGB(
      center.a.toInt(),
      center.r.toInt(),
      center.g.toInt(),
      center.b.toInt(),
    );
    final foreground = background.computeLuminance() > 0.52
        ? const Color(0xFF1E1E1E)
        : const Color(0xFFFFFFFF);
    return ProcessedMessageBubblePng(
      bytes: Uint8List.fromList(image_lib.encodePng(compact.image)),
      width: compact.image.width,
      height: compact.image.height,
      stretchX: horizontal.stretch,
      stretchY: compact.stretch,
      backgroundColorValue: background.toARGB32(),
      foregroundColorValue: foreground.toARGB32(),
    );
  }

  bool _hasPngSignature(Uint8List bytes) {
    const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < signature.length) return false;
    for (var index = 0; index < signature.length; index++) {
      if (bytes[index] != signature[index]) return false;
    }
    return true;
  }

  _CollapsedAxis _collapseRepeatedColumns(image_lib.Image source) {
    final center = (source.width - 1) ~/ 2;
    var start = center;
    var end = center + 1;
    while (start > 1 && _columnsEqual(source, start - 1, center)) {
      start--;
    }
    while (end < source.width - 1 && _columnsEqual(source, end, center)) {
      end++;
    }
    if (end - start == 1) {
      return _CollapsedAxis(source, center);
    }
    final output = image_lib.Image(
      width: start + 1 + source.width - end,
      height: source.height,
      numChannels: 4,
    );
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < output.width; x++) {
        final sourceX = x < start
            ? x
            : (x == start ? center : end + x - start - 1);
        _copyPixel(source, sourceX, y, output, x, y);
      }
    }
    return _CollapsedAxis(output, start);
  }

  _CollapsedAxis _collapseRepeatedRows(image_lib.Image source) {
    final center = (source.height - 1) ~/ 2;
    var start = center;
    var end = center + 1;
    while (start > 1 && _rowsEqual(source, start - 1, center)) {
      start--;
    }
    while (end < source.height - 1 && _rowsEqual(source, end, center)) {
      end++;
    }
    if (end - start == 1) {
      return _CollapsedAxis(source, center);
    }
    final output = image_lib.Image(
      width: source.width,
      height: start + 1 + source.height - end,
      numChannels: 4,
    );
    for (var y = 0; y < output.height; y++) {
      final sourceY = y < start
          ? y
          : (y == start ? center : end + y - start - 1);
      for (var x = 0; x < source.width; x++) {
        _copyPixel(source, x, sourceY, output, x, y);
      }
    }
    return _CollapsedAxis(output, start);
  }

  bool _columnsEqual(image_lib.Image image, int a, int b) {
    for (var y = 0; y < image.height; y++) {
      if (!_pixelsEqual(image.getPixel(a, y), image.getPixel(b, y))) {
        return false;
      }
    }
    return true;
  }

  bool _rowsEqual(image_lib.Image image, int a, int b) {
    for (var x = 0; x < image.width; x++) {
      if (!_pixelsEqual(image.getPixel(x, a), image.getPixel(x, b))) {
        return false;
      }
    }
    return true;
  }

  bool _pixelsEqual(image_lib.Pixel a, image_lib.Pixel b) =>
      a.r == b.r && a.g == b.g && a.b == b.b && a.a == b.a;

  void _copyPixel(
    image_lib.Image source,
    int sourceX,
    int sourceY,
    image_lib.Image destination,
    int destinationX,
    int destinationY,
  ) {
    final pixel = source.getPixel(sourceX, sourceY);
    destination.setPixelRgba(
      destinationX,
      destinationY,
      pixel.r,
      pixel.g,
      pixel.b,
      pixel.a,
    );
  }
}

class CustomMessageBubbleImporter {
  CustomMessageBubbleImporter({
    Future<Directory> Function()? supportDirectory,
    this._processor = const CustomMessageBubblePngProcessor(),
    String Function()? fileId,
  }) : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
       _fileId =
           fileId ?? (() => DateTime.now().microsecondsSinceEpoch.toString());

  final Future<Directory> Function() _supportDirectory;
  final CustomMessageBubblePngProcessor _processor;
  final String Function() _fileId;

  Future<CustomMessageBubbleBackground> importFile(String sourcePath) async {
    late final Uint8List bytes;
    try {
      bytes = await File(sourcePath).readAsBytes();
    } catch (error) {
      throw CustomMessageBubbleImportException(
        CustomMessageBubbleImportFailure.invalidPng,
        error,
      );
    }
    return importBytes(bytes);
  }

  Future<CustomMessageBubbleBackground> importBytes(Uint8List bytes) async {
    final processed = _processor.process(bytes);
    File? temporary;
    try {
      final support = await _supportDirectory();
      final directory = Directory('${support.path}/message_bubbles');
      await directory.create(recursive: true);
      final id = _fileId().replaceAll(RegExp('[^a-zA-Z0-9_-]'), '');
      final name = 'custom_${id.isEmpty ? 'import' : id}.png';
      final destination = File('${directory.path}/$name');
      temporary = File('${directory.path}/.$name.tmp');
      await temporary.writeAsBytes(processed.bytes, flush: true);
      if (await destination.exists()) await destination.delete();
      final stored = await temporary.rename(destination.path);
      return CustomMessageBubbleBackground(
        filePath: stored.path,
        width: processed.width,
        height: processed.height,
        stretchX: processed.stretchX,
        stretchY: processed.stretchY,
        backgroundColorValue: processed.backgroundColorValue,
        foregroundColorValue: processed.foregroundColorValue,
      );
    } on CustomMessageBubbleImportException {
      rethrow;
    } catch (error) {
      try {
        if (temporary != null && await temporary.exists()) {
          await temporary.delete();
        }
      } catch (_) {}
      throw CustomMessageBubbleImportException(
        CustomMessageBubbleImportFailure.write,
        error,
      );
    }
  }
}

class _CollapsedAxis {
  const _CollapsedAxis(this.image, this.stretch);

  final image_lib.Image image;
  final int stretch;
}
