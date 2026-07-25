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
    this.paletteColorValues = const <int>[],
    this.sourceMessageLink,
  });

  factory CustomMessageBubbleBackground.fromJson(Map<String, dynamic> json) {
    final filePath = json['filePath'];
    final width = json['width'];
    final height = json['height'];
    final stretchX = json['stretchX'];
    final stretchY = json['stretchY'];
    final backgroundColorValue = json['backgroundColor'];
    final foregroundColorValue = json['foregroundColor'];
    final palette = json['palette'];
    final sourceMessageLink = json['sourceMessageLink'];
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
      paletteColorValues: palette is List
          ? palette.whereType<int>().take(4).toList(growable: false)
          : <int>[foregroundColorValue],
      sourceMessageLink:
          sourceMessageLink is String && sourceMessageLink.isNotEmpty
          ? sourceMessageLink
          : null,
    );
  }

  final String filePath;
  final int width;
  final int height;
  final int stretchX;
  final int stretchY;
  final int backgroundColorValue;
  final int foregroundColorValue;
  final List<int> paletteColorValues;
  final String? sourceMessageLink;

  double get imageScale =>
      sourceMessageLink == null ? 1 : MessageBubbleRepositoryFormat.imageScale;

  Rect get centerSlice => Rect.fromLTWH(
    stretchX / imageScale,
    stretchY / imageScale,
    1 / imageScale,
    1 / imageScale,
  );

  Size get minimumSize {
    final overflow = visualOverflow;
    return Size(
      width / imageScale - overflow.horizontal,
      height / imageScale - overflow.vertical,
    );
  }

  EdgeInsets get contentPadding =>
      const EdgeInsets.symmetric(horizontal: 12, vertical: 9);

  // A square 90 px source corner compacts to 27 logical pixels. Its 30 px
  // transparent portion therefore becomes 9 logical pixels on every edge.
  // outside the layout aligns the inner 300 × 120 artwork vertices with the
  // corresponding vertices of a standard bubble.
  EdgeInsets get visualOverflow =>
      sourceMessageLink == null ? EdgeInsets.zero : const EdgeInsets.all(9);

  Color get backgroundColor => Color(backgroundColorValue);
  Color get foregroundColor => Color(foregroundColorValue);
  bool get fileExists => File(filePath).existsSync();

  Map<String, dynamic> toJson() => {
    'version': 2,
    'filePath': filePath,
    'width': width,
    'height': height,
    'stretchX': stretchX,
    'stretchY': stretchY,
    'backgroundColor': backgroundColorValue,
    'foregroundColor': foregroundColorValue,
    'palette': paletteColorValues,
    if (sourceMessageLink != null) 'sourceMessageLink': sourceMessageLink,
  };
}

enum CustomMessageBubbleImportFailure {
  invalidPng,
  tooSmall,
  tooLarge,
  wrongRepositorySize,
  invalidPalette,
  write,
}

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
    this.paletteColorValues = const <int>[],
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final int stretchX;
  final int stretchY;
  final int backgroundColorValue;
  final int foregroundColorValue;
  final List<int> paletteColorValues;
}

/// Canonical wire format used by the public @msgbubble repository.
///
/// The four 40px swatches sit in a compact center band. They are metadata rather
/// than bubble artwork and are removed before the PNG is center-slice compacted.
abstract final class MessageBubbleRepositoryFormat {
  static const width = 360;
  static const height = 180;
  static const artworkWidth = 300;
  static const artworkHeight = 120;
  static const artworkPadding = 30;
  static const swatchSize = 40;
  static const swatchGap = 10;
  static const swatchTop = 70;
  // 4 × 40 plus 3 × 10 = 190 px, centered on x=180. This leaves x=180
  // inside the 10 px gap between squares 2 and 3 for the center slice.
  static const swatchLeft = 85;
  static const swatchCount = 4;
  // Retain 30 px of transparent canvas plus 60 px of artwork per corner.
  static const protectedHorizontal = 90;
  static const protectedVertical = 90;
  static const runtimeCornerWidth = 27;
  static const runtimeCornerHeight = 27;
  static const imageScale = 10 / 3;

  static int swatchX(int index) =>
      swatchLeft + index * (swatchSize + swatchGap);
}

class CustomMessageBubblePngProcessor {
  const CustomMessageBubblePngProcessor({
    this.maximumBytes = 16 * 1024 * 1024,
    this.maximumDimension = 2048,
  });

  final int maximumBytes;
  final int maximumDimension;

  ProcessedMessageBubblePng process(Uint8List bytes) {
    return _process(bytes, repositoryFormat: false);
  }

  ProcessedMessageBubblePng processRepository(Uint8List bytes) {
    return _process(bytes, repositoryFormat: true);
  }

  ProcessedMessageBubblePng _process(
    Uint8List bytes, {
    required bool repositoryFormat,
  }) {
    if (bytes.length > maximumBytes) {
      throw const CustomMessageBubbleImportException(
        CustomMessageBubbleImportFailure.tooLarge,
      );
    }
    if (!repositoryFormat && !_hasPngSignature(bytes)) {
      throw const CustomMessageBubbleImportException(
        CustomMessageBubbleImportFailure.invalidPng,
      );
    }
    final decoded = repositoryFormat
        ? image_lib.decodeImage(bytes)
        : image_lib.decodePng(bytes);
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

    var source = decoded;
    var palette = const <int>[];
    if (repositoryFormat) {
      if (decoded.width != MessageBubbleRepositoryFormat.width ||
          decoded.height != MessageBubbleRepositoryFormat.height) {
        throw const CustomMessageBubbleImportException(
          CustomMessageBubbleImportFailure.wrongRepositorySize,
        );
      }
      final prepared = _stripRepositoryPalette(decoded);
      source = _restoreRepositoryCornerTransparency(prepared.$1);
      palette = prepared.$2;
    }

    late final image_lib.Image compactImage;
    late final int stretchX;
    late final int stretchY;
    if (repositoryFormat) {
      compactImage = _compactRepositoryCorners(source);
      stretchX = MessageBubbleRepositoryFormat.protectedHorizontal;
      stretchY = MessageBubbleRepositoryFormat.protectedVertical;
    } else {
      final horizontal = _collapseRepeatedColumns(source);
      final compact = _collapseRepeatedRows(horizontal.image);
      compactImage = compact.image;
      stretchX = horizontal.stretch;
      stretchY = compact.stretch;
    }
    final center = compactImage.getPixel(stretchX, stretchY);
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
      bytes: Uint8List.fromList(image_lib.encodePng(compactImage)),
      width: compactImage.width,
      height: compactImage.height,
      stretchX: stretchX,
      stretchY: stretchY,
      backgroundColorValue: background.toARGB32(),
      foregroundColorValue: palette.isEmpty
          ? foreground.toARGB32()
          : palette.first,
      paletteColorValues: palette.isEmpty
          ? <int>[foreground.toARGB32()]
          : palette,
    );
  }

  (image_lib.Image, List<int>) _stripRepositoryPalette(image_lib.Image source) {
    final output = source.convert(numChannels: 4);
    // Sample the bubble fill above the palette band. The canvas center falls
    // inside swatch 3 in the 360 × 180 repository layout.
    final center = source.getPixel(
      source.width ~/ 2,
      MessageBubbleRepositoryFormat.swatchTop - 10,
    );
    final colors = <int>[];
    for (
      var index = 0;
      index < MessageBubbleRepositoryFormat.swatchCount;
      index++
    ) {
      final left = MessageBubbleRepositoryFormat.swatchX(index);
      const top = MessageBubbleRepositoryFormat.swatchTop;
      const inset = MessageBubbleRepositoryFormat.swatchSize ~/ 4;
      var red = 0;
      var green = 0;
      var blue = 0;
      var alpha = 0;
      var samples = 0;
      for (
        var y = top + inset;
        y < top + MessageBubbleRepositoryFormat.swatchSize - inset;
        y++
      ) {
        for (
          var x = left + inset;
          x < left + MessageBubbleRepositoryFormat.swatchSize - inset;
          x++
        ) {
          final pixel = source.getPixel(x, y);
          red += pixel.r.toInt();
          green += pixel.g.toInt();
          blue += pixel.b.toInt();
          alpha += pixel.a.toInt();
          samples++;
        }
      }
      for (
        var y = top;
        y < top + MessageBubbleRepositoryFormat.swatchSize;
        y++
      ) {
        for (
          var x = left;
          x < left + MessageBubbleRepositoryFormat.swatchSize;
          x++
        ) {
          output.setPixelRgba(x, y, center.r, center.g, center.b, center.a);
        }
      }
      colors.add(
        Color.fromARGB(
          alpha ~/ samples,
          red ~/ samples,
          green ~/ samples,
          blue ~/ samples,
        ).toARGB32(),
      );
    }
    return (output, colors);
  }

  bool _hasPngSignature(Uint8List bytes) {
    const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < signature.length) return false;
    for (var index = 0; index < signature.length; index++) {
      if (bytes[index] != signature[index]) return false;
    }
    return true;
  }

  image_lib.Image _restoreRepositoryCornerTransparency(image_lib.Image source) {
    if (source.getPixel(0, 0).a.toInt() == 0) return source;
    final output = source.convert(numChannels: 4);
    final visited = Uint8List(source.width * source.height);
    final queue = <int>[];
    var transparentCount = 0;

    const padding = MessageBubbleRepositoryFormat.artworkPadding;
    final artworkRight = source.width - padding - 1;
    final artworkBottom = source.height - padding - 1;
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        if (x < padding ||
            x > artworkRight ||
            y < padding ||
            y > artworkBottom) {
          final pixel = source.getPixel(x, y);
          output.setPixelRgba(x, y, pixel.r, pixel.g, pixel.b, 0);
        }
      }
    }
    final paddingOnly = output.convert(numChannels: 4);

    void flood(int startX, int startY) {
      final seed = source.getPixel(startX, startY);
      queue
        ..clear()
        ..add(startY * source.width + startX);
      while (queue.isNotEmpty) {
        final offset = queue.removeLast();
        if (visited[offset] != 0) continue;
        final x = offset % source.width;
        final y = offset ~/ source.width;
        if (x < padding ||
            x > artworkRight ||
            y < padding ||
            y > artworkBottom) {
          continue;
        }
        final pixel = source.getPixel(x, y);
        final delta = <int>[
          (pixel.r.toInt() - seed.r.toInt()).abs(),
          (pixel.g.toInt() - seed.g.toInt()).abs(),
          (pixel.b.toInt() - seed.b.toInt()).abs(),
        ].reduce((a, b) => a > b ? a : b);
        if (delta > 36) continue;
        visited[offset] = 1;
        final alpha = delta <= 6
            ? 0
            : ((delta - 6) * 8.5).round().clamp(0, 255);
        output.setPixelRgba(x, y, pixel.r, pixel.g, pixel.b, alpha);
        transparentCount++;
        if (x > 0) queue.add(offset - 1);
        if (x + 1 < source.width) queue.add(offset + 1);
        if (y > 0) queue.add(offset - source.width);
        if (y + 1 < source.height) queue.add(offset + source.width);
      }
    }

    flood(padding, padding);
    flood(artworkRight, padding);
    flood(padding, artworkBottom);
    flood(artworkRight, artworkBottom);
    // A malformed flat card has no closed bubble edge. Never erase its body.
    return transparentCount >
            MessageBubbleRepositoryFormat.artworkWidth *
                MessageBubbleRepositoryFormat.artworkHeight ~/
                2
        ? paddingOnly
        : output;
  }

  image_lib.Image _compactRepositoryCorners(image_lib.Image source) {
    const sourceEdgeX = MessageBubbleRepositoryFormat.protectedHorizontal;
    const sourceEdgeY = MessageBubbleRepositoryFormat.protectedVertical;
    const edgeX = MessageBubbleRepositoryFormat.protectedHorizontal;
    const edgeY = MessageBubbleRepositoryFormat.protectedVertical;
    final output = image_lib.Image(
      width: edgeX * 2 + 1,
      height: edgeY * 2 + 1,
      numChannels: 4,
    );
    int sourceCoordinate(
      int value,
      int outputLength,
      int sourceLength,
      int sourceCenter,
      int sourceMax,
    ) {
      final outputEdge = (outputLength - 1) ~/ 2;
      if (value == outputEdge) return sourceCenter;
      final fromEdge = value < outputEdge ? value : outputLength - 1 - value;
      final sourceFromEdge = outputEdge == 1
          ? 0
          : (fromEdge * (sourceLength - 1) / (outputEdge - 1)).round();
      return value < outputEdge ? sourceFromEdge : sourceMax - sourceFromEdge;
    }

    for (var y = 0; y < output.height; y++) {
      final sourceY = sourceCoordinate(
        y,
        output.height,
        sourceEdgeY,
        source.height ~/ 2,
        source.height - 1,
      );
      for (var x = 0; x < output.width; x++) {
        final sourceX = sourceCoordinate(
          x,
          output.width,
          sourceEdgeX,
          source.width ~/ 2,
          source.width - 1,
        );
        _copyPixel(source, sourceX, sourceY, output, x, y);
      }
    }
    return output;
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
    return _importProcessed(_processor.process(bytes));
  }

  Future<CustomMessageBubbleBackground> importRepositoryBytes(
    Uint8List bytes, {
    required String sourceMessageLink,
  }) async {
    return _importProcessed(
      _processor.processRepository(bytes),
      sourceMessageLink: sourceMessageLink,
    );
  }

  Future<CustomMessageBubbleBackground> _importProcessed(
    ProcessedMessageBubblePng processed, {
    String? sourceMessageLink,
  }) async {
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
        paletteColorValues: processed.paletteColorValues,
        sourceMessageLink: sourceMessageLink,
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
