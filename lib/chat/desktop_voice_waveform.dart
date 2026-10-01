import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A fixed-width scrolling meter. Silent/missing samples stay on the baseline;
/// only measured microphone amplitudes raise the bars.
class DesktopVoiceWaveform extends StatelessWidget {
  const DesktopVoiceWaveform({
    super.key,
    required this.levels,
    required this.color,
    required this.baselineColor,
  });

  final List<double> levels;
  final Color color;
  final Color baselineColor;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: DesktopVoiceWaveformPainter(
        levels: levels,
        color: color,
        baselineColor: baselineColor,
      ),
      child: const SizedBox.expand(),
    ),
  );
}

class DesktopVoiceWaveformPainter extends CustomPainter {
  const DesktopVoiceWaveformPainter({
    required this.levels,
    required this.color,
    required this.baselineColor,
  });

  final List<double> levels;
  final Color color;
  final Color baselineColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const pitch = 5.0;
    final count = math.max(1, (size.width / pitch).floor());
    final samples = math.min(count, levels.length);
    final paint = Paint();
    for (var index = 0; index < count; index++) {
      final sample = index - (count - samples);
      final level = sample < 0
          ? -120.0
          : levels[levels.length - samples + sample];
      final amplitude = level.isFinite
          ? ((level.clamp(-60.0, 0.0) + 60) / 60)
          : 0.0;
      final height = math.min(size.height, 2 + amplitude * (size.height - 2));
      paint.color = sample < 0 ? baselineColor : color;
      final rect = Rect.fromLTWH(
        index * pitch,
        (size.height - height) / 2,
        math.min(2.0, size.width),
        height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(DesktopVoiceWaveformPainter oldDelegate) =>
      levels != oldDelegate.levels ||
      color != oldDelegate.color ||
      baselineColor != oldDelegate.baselineColor;
}
