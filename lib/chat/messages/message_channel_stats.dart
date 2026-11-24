//
//  message_channel_stats.dart
//
//  Out-of-bubble counters for channel posts: how many times the post was
//  read and forwarded. They ride the same corner band as the reply badge and
//  the edited mark, so a channel post reads like the rest of the transcript
//  instead of carrying a second footer inside the bubble.
//

import 'package:flutter/material.dart';

import '../../components/app_icons.dart';
import '../../theme/app_theme.dart';

/// Telegram's compact counter form: 999 → "999", 1000 → "1K",
/// 1234 → "1.2K", 123456 → "123.4K", 1200000 → "1.2M".
String formatChannelStatCount(int value) {
  if (value < 1000) return '$value';
  const units = ['K', 'M', 'B'];
  var number = value;
  var unit = -1;
  var decimal = 0;
  while (number ~/ 1000 > 0 && unit < units.length - 1) {
    decimal = (number % 1000) ~/ 100;
    number ~/= 1000;
    unit++;
  }
  final buffer = StringBuffer('$number');
  if (decimal != 0) buffer.write('.$decimal');
  buffer.write(units[unit]);
  return buffer.toString();
}

/// One corner-band chip holding a channel post's view or forward count.
class MessageChannelStatChip extends StatelessWidget {
  const MessageChannelStatChip({
    super.key,
    required this.icon,
    required this.count,
    required this.foreground,
    required this.background,
    required this.semanticLabel,
  });

  final AppIconData icon;
  final int count;
  final Color foreground;
  final Color background;

  /// Spoken description, e.g. "1.2K views"; the chip itself only draws the
  /// number.
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(icon, size: 12, color: foreground),
          const SizedBox(width: 3),
          Text(
            formatChannelStatCount(count),
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              color: foreground,
              fontSize: 11,
              height: 1.1,
              fontWeight: FontWeight.w500,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
    return Semantics(label: semanticLabel, excludeSemantics: true, child: chip);
  }
}
