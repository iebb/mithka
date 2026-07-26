import 'dart:typed_data';

import 'video_source.dart';

Future<Uint8List?> generateThumbnail({
  required MithkaVideoSource source,
  required Duration position,
  required int maxWidth,
  required int quality,
}) => Future<Uint8List?>.value();
