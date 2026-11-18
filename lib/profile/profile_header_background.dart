import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../chat/stickers/custom_emoji.dart';
import '../settings/accent_color_picker_view.dart';
import '../tdlib/json_helpers.dart';

/// The one or two colors Telegram paints behind a user's profile photo, from
/// the profile color when one is set and otherwise from the name color.
///
/// [profileAccentColors] and [accentColors] are TDLib's
/// `updateProfileAccentColors` and `updateAccentColors`. Returns null when
/// neither id resolves, so the caller keeps its own background.
List<Color>? profileHeaderColors({
  required int profileAccentColorId,
  required int accentColorId,
  required bool dark,
  Map<String, dynamic>? profileAccentColors,
  Map<String, dynamic>? accentColors,
}) {
  final theme = dark ? 'dark_theme_colors' : 'light_theme_colors';
  if (profileAccentColorId >= 0) {
    final entry = _colorEntry(profileAccentColors, profileAccentColorId);
    final values =
        entry?.obj(theme)?.int64Array('background_colors') ?? const <int>[];
    if (values.isNotEmpty) {
      return [for (final value in values.take(2)) _rgb(value)];
    }
  }
  if (accentColorId < 0) return null;
  Color? name;
  if (accentColorId < kAccentColors.length) {
    name = kAccentColors[accentColorId];
  } else {
    final entry = _colorEntry(accentColors, accentColorId);
    final values = entry?.int64Array(theme) ?? const <int>[];
    final builtIn = entry?.integer('built_in_accent_color_id') ?? -1;
    if (values.isNotEmpty) {
      name = _rgb(values.first);
    } else if (builtIn >= 0 && builtIn < kAccentColors.length) {
      name = kAccentColors[builtIn];
    }
  }
  if (name == null) return null;
  // A name color is a single mid tone; lift the centre so the photo sits in
  // light the way it does on a two-tone profile color.
  final edge = dark ? Color.lerp(name, const Color(0xFF000000), 0.22)! : name;
  return [Color.lerp(edge, const Color(0xFFFFFFFF), 0.2)!, edge];
}

Map<String, dynamic>? _colorEntry(Map<String, dynamic>? update, int id) {
  for (final entry
      in update?.objects('colors') ?? const <Map<String, dynamic>>[]) {
    if (entry.integer('id') == id) return entry;
  }
  return null;
}

Color _rgb(int value) => Color(0xFF000000 | (value & 0xFFFFFF));

/// One profile icon in the pattern: where its centre sits, how big it is
/// drawn, and how strongly it shows.
@immutable
class ProfilePatternSlot {
  const ProfilePatternSlot(this.center, this.size, this.opacity);

  final Offset center;
  final double size;
  final double opacity;
}

/// Rings of profile icons around the photo, smaller and fainter the further
/// out they sit. Icons that would be cut by the edge of [bounds] are left out.
@visibleForTesting
List<ProfilePatternSlot> profilePatternSlots(
  Size bounds,
  Offset photoCenter,
  double photoRadius,
) {
  const rings = 5;
  const firstGap = 20.0;
  const ringStep = 34.0;
  const spacing = 46.0;
  final slots = <ProfilePatternSlot>[];
  for (var ring = 0; ring < rings; ring++) {
    final radius = photoRadius + firstGap + ring * ringStep;
    final size = 20.0 - ring * 1.5;
    final opacity = 0.3 - ring * 0.045;
    final count = math.max(6, (2 * math.pi * radius / spacing).floor());
    // Alternate rings sit half a step round so icons don't line up in spokes.
    final offset = ring.isOdd ? math.pi / count : 0.0;
    for (var i = 0; i < count; i++) {
      final angle = offset + 2 * math.pi * i / count;
      final center =
          photoCenter + Offset(math.cos(angle), math.sin(angle)) * radius;
      final half = size / 2;
      if (center.dx < half ||
          center.dy < half ||
          center.dx > bounds.width - half ||
          center.dy > bounds.height - half) {
        continue;
      }
      slots.add(ProfilePatternSlot(center, size, opacity));
    }
  }
  return slots;
}

/// A profile header painted in Telegram's profile or name colors, lit around
/// the photo, with the user's profile icon repeated in rings behind it.
class ProfileHeaderBackground extends StatelessWidget {
  const ProfileHeaderBackground({
    super.key,
    required this.colors,
    required this.photoCenter,
    required this.photoRadius,
    this.patternEmojiId = 0,
  });

  /// One or two colors from [profileHeaderColors].
  final List<Color> colors;

  /// Where the photo's centre sits inside this box.
  final Offset photoCenter;
  final double photoRadius;

  /// The profile icon custom emoji; zero draws no pattern.
  final int patternEmojiId;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(decoration: BoxDecoration(gradient: _gradient(size))),
            if (patternEmojiId != 0)
              IgnorePointer(
                child: ExcludeSemantics(
                  child: RepaintBoundary(
                    child: Stack(
                      children: [
                        for (final slot in profilePatternSlots(
                          size,
                          photoCenter,
                          photoRadius,
                        ))
                          Positioned(
                            left: slot.center.dx - slot.size / 2,
                            top: slot.center.dy - slot.size / 2,
                            child: ColorFiltered(
                              // Any emoji, colored or not, becomes a dark
                              // silhouette at the slot's strength.
                              colorFilter: ColorFilter.mode(
                                const Color(
                                  0xFF000000,
                                ).withValues(alpha: slot.opacity),
                                BlendMode.srcIn,
                              ),
                              child: CustomEmojiView(
                                id: patternEmojiId,
                                size: slot.size,
                                animate: false,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Gradient _gradient(Size size) {
    final light = colors.length < 2
        ? Color.lerp(colors.first, const Color(0xFFFFFFFF), 0.2)!
        : colors.reduce(
            (a, b) => a.computeLuminance() >= b.computeLuminance() ? a : b,
          );
    final deep = colors.length < 2
        ? colors.first
        : colors.firstWhere((color) => color != light, orElse: () => light);
    final shortest = size.shortestSide <= 0 ? 1.0 : size.shortestSide;
    return RadialGradient(
      center: Alignment(
        size.width <= 0 ? 0 : photoCenter.dx / size.width * 2 - 1,
        size.height <= 0 ? 0 : photoCenter.dy / size.height * 2 - 1,
      ),
      // Fades from the light tone at the photo to the deep tone about 240 px
      // out, whatever the header's height.
      radius: 240 / shortest,
      colors: [light, deep],
    );
  }
}
