import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

class AnimatedAvatarPreparer {
  const AnimatedAvatarPreparer._();

  static const _channel = MethodChannel('mithka/animated_avatar');

  static Future<XFile> prepare(
    XFile source, {
    required AnimatedAvatarCrop crop,
  }) async {
    if (!Platform.isIOS) return source;
    final outputPath = await _channel.invokeMethod<String>('prepare', {
      'path': source.path,
      'cropLeft': crop.left,
      'cropTop': crop.top,
      'cropWidth': crop.width,
      'cropHeight': crop.height,
    });
    if (outputPath == null || outputPath.isEmpty) {
      throw StateError('Animated avatar conversion returned no video');
    }
    final output = File(outputPath);
    if (!await output.exists() || await output.length() == 0) {
      throw StateError('Animated avatar conversion returned an invalid video');
    }
    return XFile(outputPath, mimeType: 'video/mp4');
  }
}

class AnimatedAvatarCrop {
  const AnimatedAvatarCrop({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;
}
