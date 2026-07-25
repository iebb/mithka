import 'dart:io';

import 'package:image/image.dart' as image_lib;

const _logicalWidth = 49;
const _logicalHeight = 37;
const _scale = 2;
const _centerLogicalX = 24;
const _centerLogicalY = 18;

void main() {
  final output = Directory('assets/message_bubbles')
    ..createSync(recursive: true);
  final retina = Directory('${output.path}/2.0x')..createSync(recursive: true);

  for (final source in _sources) {
    final bytes = File(source.inputPath).readAsBytesSync();
    final decoded = image_lib.decodePng(bytes);
    if (decoded == null) {
      throw StateError('Could not decode ${source.inputPath}');
    }
    final trimmed = image_lib.trim(
      decoded,
      mode: image_lib.TrimMode.transparent,
    );
    final compact2x = _compact(trimmed, source.cornerWidthFraction);
    final compact1x = image_lib.copyResize(
      compact2x,
      width: _logicalWidth,
      height: _logicalHeight,
      interpolation: image_lib.Interpolation.cubic,
    );

    File(
      '${retina.path}/${source.name}.png',
    ).writeAsBytesSync(image_lib.encodePng(compact2x));
    File(
      '${output.path}/${source.name}.png',
    ).writeAsBytesSync(image_lib.encodePng(compact1x));
  }
}

image_lib.Image _compact(image_lib.Image source, double cornerWidthFraction) {
  final output = image_lib.Image(
    width: _logicalWidth * _scale,
    height: _logicalHeight * _scale,
    numChannels: 4,
  );
  image_lib.fill(output, color: image_lib.ColorRgba8(0, 0, 0, 0));

  final centerX = source.width ~/ 2;
  final centerY = source.height ~/ 2;
  final cornerWidth = (source.width * cornerWidthFraction).round();
  final centerSourceX = centerX - 1;
  final centerSourceY = centerY - 1;
  final bottomSourceY = centerY + 1;
  final rightSourceX = source.width - cornerWidth;

  final sourceColumns = <_Band>[
    _Band(0, cornerWidth, 0, _centerLogicalX * _scale),
    _Band(centerSourceX, 2, _centerLogicalX * _scale, _scale),
    _Band(
      rightSourceX,
      cornerWidth,
      (_centerLogicalX + 1) * _scale,
      _centerLogicalX * _scale,
    ),
  ];
  final sourceRows = <_Band>[
    _Band(0, centerY - 1, 0, _centerLogicalY * _scale),
    _Band(centerSourceY, 2, _centerLogicalY * _scale, _scale),
    _Band(
      bottomSourceY,
      source.height - bottomSourceY,
      (_centerLogicalY + 1) * _scale,
      _centerLogicalY * _scale,
    ),
  ];

  for (final row in sourceRows) {
    for (final column in sourceColumns) {
      final tile = image_lib.copyCrop(
        source,
        x: column.sourceStart,
        y: row.sourceStart,
        width: column.sourceExtent,
        height: row.sourceExtent,
      );
      final resized = image_lib.copyResize(
        tile,
        width: column.destinationExtent,
        height: row.destinationExtent,
        interpolation: image_lib.Interpolation.cubic,
      );
      image_lib.compositeImage(
        output,
        resized,
        dstX: column.destinationStart,
        dstY: row.destinationStart,
        blend: image_lib.BlendMode.direct,
      );
    }
  }
  return output;
}

class _Source {
  const _Source(this.name, this.cornerWidthFraction);

  final String name;
  final double cornerWidthFraction;

  String get inputPath =>
      'design/message_bubbles/gpt-image-2-sources/$name.png';
}

class _Band {
  const _Band(
    this.sourceStart,
    this.sourceExtent,
    this.destinationStart,
    this.destinationExtent,
  );

  final int sourceStart;
  final int sourceExtent;
  final int destinationStart;
  final int destinationExtent;
}

const _sources = <_Source>[
  _Source('midnight-aurora', 0.23),
  _Source('solar-porcelain', 0.20),
  _Source('berry-orbit', 0.25),
  _Source('arctic-blueprint', 0.18),
  _Source('ember-arcade', 0.22),
  _Source('lilac-constellation', 0.20),
  _Source('forest-familiar', 0.28),
  _Source('ink-wanderer', 0.25),
  _Source('pixel-cadet', 0.24),
  _Source('cosmic-mechanic', 0.28),
  _Source('pastry-pal', 0.25),
  _Source('noir-detective', 0.27),
];
