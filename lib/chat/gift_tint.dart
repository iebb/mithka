//
//  gift_tint.dart
//
//  The colours a gift card and its sheet draw with. An upgraded gift with a
//  backdrop keeps its own backdrop colours; any other gift with a sticker is
//  tinted by the sticker's main colour, found once off the UI isolate and
//  remembered across launches; everything else takes the theme colour.
//

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

/// The colours of one gift card and its sheet.
@immutable
class GiftPalette {
  const GiftPalette({
    required this.bodyStart,
    required this.bodyEnd,
    required this.ring,
    required this.ink,
    required this.ink2,
    required this.washTop,
    required this.washMiddle,
  });

  /// A tint from [seed]'s hue and saturation: the gift's own colour, or the
  /// theme colour. Every hue is brought to the same luminance first, so a
  /// yellow card is no brighter than a blue one.
  factory GiftPalette.fromSeed(
    Color seed, {
    required AppColors colors,
    required bool light,
  }) {
    final hsl = HSLColor.fromColor(seed);
    final hue = hsl.hue;
    final saturation = hsl.saturation.clamp(0.50, 0.85).toDouble();
    final tint = atLuminance(hue, saturation, 0.30);
    final card = colors.card;
    final bodyStart = Color.alphaBlend(
      tint.withValues(alpha: light ? 0.16 : 0.22),
      card,
    );
    final bodyEnd = Color.alphaBlend(
      tint.withValues(alpha: light ? 0.26 : 0.30),
      card,
    );
    final ring = Color.alphaBlend(
      tint.withValues(alpha: light ? 0.14 : 0.12),
      bodyEnd,
    );
    final surfaces = [bodyStart, bodyEnd, ring];
    final ink = light
        ? atLuminance(hue, math.min(saturation, 0.40), 0.05)
        : atLuminance(hue, math.min(saturation, 0.30), 0.80);
    final ink2 = light
        ? atLuminance(hue, math.min(saturation, 0.30), 0.10)
        : atLuminance(hue, math.min(saturation, 0.25), 0.60);
    return GiftPalette(
      bodyStart: bodyStart,
      bodyEnd: bodyEnd,
      ring: ring,
      ink: _readable(ink, surfaces, colors.textPrimary),
      ink2: _readable(ink2, surfaces, colors.textPrimary),
      washTop: bodyEnd,
      washMiddle: bodyStart,
    );
  }

  /// An upgraded gift's own backdrop: edge colour on the left, centre colour
  /// on the right, the symbol colour for the ring, the backdrop's text colour
  /// for both lines unless it is unreadable on the edge colour.
  factory GiftPalette.fromBackdrop(MessageGiftBackdropColors backdrop) {
    final edge = Color(backdrop.edgeColor);
    final center = Color(backdrop.centerColor);
    final text = Color(backdrop.textColor);
    final ink = contrastRatio(text, edge) < _minimumInkContrast
        ? readableForeground(edge)
        : text;
    return GiftPalette(
      bodyStart: edge,
      bodyEnd: center,
      ring: Color(backdrop.symbolColor).withValues(alpha: 0.35),
      ink: ink,
      ink2: ink,
      washTop: edge,
      washMiddle: center,
    );
  }

  /// The body gradient, left to right.
  final Color bodyStart;
  final Color bodyEnd;

  /// The decorative circle behind the sticker.
  final Color ring;

  /// The title's ink and the second line's.
  final Color ink;
  final Color ink2;

  /// The sheet's wash: [washTop] at the top, [washMiddle] at 55 %, then the
  /// sheet's own background.
  final Color washTop;
  final Color washMiddle;

  static const double _minimumInkContrast = 4.5;

  static GiftPalette lerp(GiftPalette a, GiftPalette b, double t) {
    if (t <= 0) return a;
    if (t >= 1) return b;
    Color mix(Color x, Color y) => Color.lerp(x, y, t)!;
    return GiftPalette(
      bodyStart: mix(a.bodyStart, b.bodyStart),
      bodyEnd: mix(a.bodyEnd, b.bodyEnd),
      ring: mix(a.ring, b.ring),
      ink: mix(a.ink, b.ink),
      ink2: mix(a.ink2, b.ink2),
      washTop: mix(a.washTop, b.washTop),
      washMiddle: mix(a.washMiddle, b.washMiddle),
    );
  }

  /// Moves [ink] toward [fallback] a tenth at a time until it reads at 4.5:1
  /// on every surface it sits on. Only a theme with an unusual card colour
  /// ever needs a step.
  static Color _readable(Color ink, List<Color> surfaces, Color fallback) {
    for (var step = 0; step <= 10; step++) {
      final candidate = Color.lerp(ink, fallback, step / 10)!;
      if (surfaces.every(
        (surface) => contrastRatio(candidate, surface) >= _minimumInkContrast,
      )) {
        return candidate;
      }
    }
    return fallback;
  }
}

/// Called with one rendered sticker frame, as straight-alpha RGBA bytes,
/// when the gift's colour has to come from the animation itself.
typedef GiftFrameProbe = void Function(Uint8List rgba, int width, int height);

/// Where a gift's colour comes from.
enum GiftTintSource {
  /// An upgraded gift's own backdrop colours.
  backdrop,

  /// The colour found in the gift's sticker, under [giftTintKey].
  sticker,

  /// The theme colour.
  theme,
}

GiftTintSource giftTintSource(MessageGift gift) {
  if (gift.backdropColors != null) return GiftTintSource.backdrop;
  return giftTintKey(gift) == null
      ? GiftTintSource.theme
      : GiftTintSource.sticker;
}

/// The cache key of a gift's colour: the regular gift's id, else the sticker
/// file's unique id, which is the same in every chat and account. Null for
/// kinds that always take the theme colour (Premium, Stars, Gram, refunds)
/// and for a gift without a sticker.
String? giftTintKey(MessageGift gift) {
  switch (gift.kind) {
    case MessageGiftKind.regular:
    case MessageGiftKind.upgraded:
    case MessageGiftKind.purchaseOffer:
    case MessageGiftKind.purchaseOfferRejected:
      break;
    case MessageGiftKind.refunded:
    case MessageGiftKind.refundedUpgraded:
    case MessageGiftKind.premium:
    case MessageGiftKind.premiumCode:
    case MessageGiftKind.stars:
    case MessageGiftKind.giveawayStars:
    case MessageGiftKind.gram:
      return null;
  }
  final sticker = gift.sticker;
  if (sticker == null) return null;
  if (gift.kind == MessageGiftKind.regular && gift.giftId != 0) {
    return 'gift:${gift.giftId}';
  }
  if (sticker.uniqueId.isNotEmpty) return 'sticker:${sticker.uniqueId}';
  return null;
}

/// The still a gift's colour is read from: the static thumbnail, or the
/// sticker itself when it is a static image. Null when only a rendered frame
/// of the animation can supply it.
TdFileRef? giftTintStill(MessageGiftSticker sticker) {
  if (sticker.hasStaticThumbnail) return sticker.thumbnail;
  return sticker.isAnimated ? null : sticker.image;
}

/// One input for [giftSeedFromPixels]: an encoded WebP / PNG / JPEG file
/// when [width] is 0, otherwise raw straight-alpha RGBA pixels.
typedef GiftSeedInput = ({Uint8List bytes, int width, int height});

/// The main colour of a gift sticker as an opaque ARGB value, or null when it
/// has too little colour to tint by (grey, white or pale art).
///
/// Runs through [compute]. The image is averaged down to 32 × 32; opaque,
/// clearly coloured pixels vote for one of 24 hue bins with their chroma;
/// the strongest bin and its two neighbours give the hue (a weighted circular
/// mean) and the saturation. Throws when the bytes are not an image.
int? giftSeedFromPixels(GiftSeedInput input) {
  var image = input.width == 0
      ? img.decodeImage(input.bytes)
      : img.Image.fromBytes(
          width: input.width,
          height: input.height,
          bytes: input.bytes.buffer,
          bytesOffset: input.bytes.offsetInBytes,
          numChannels: 4,
        );
  if (image == null) throw const FormatException('Not an image');
  if (image.hasPalette) image = image.convert(numChannels: 4);
  final small = img.copyResize(
    image,
    width: 32,
    height: 32,
    interpolation: img.Interpolation.average,
  );

  const bins = 24;
  const binWidth = 360 / bins;
  final hues = <double>[];
  final saturations = <double>[];
  final lightnesses = <double>[];
  final weights = <double>[];
  final binWeights = List<double>.filled(bins, 0);
  var opaque = 0;
  for (final pixel in small) {
    if (pixel.aNormalized < 0.5) continue;
    opaque++;
    final r = pixel.rNormalized.toDouble();
    final g = pixel.gNormalized.toDouble();
    final b = pixel.bNormalized.toDouble();
    final high = math.max(r, math.max(g, b));
    final low = math.min(r, math.min(g, b));
    final chroma = high - low;
    final lightness = (high + low) / 2;
    final saturation = chroma == 0
        ? 0.0
        : chroma / (1 - (2 * lightness - 1).abs());
    if (saturation < 0.25 ||
        lightness < 0.15 ||
        lightness > 0.90 ||
        chroma < 0.15) {
      continue;
    }
    final double hue;
    if (high == r) {
      hue = (60 * ((g - b) / chroma)) % 360;
    } else if (high == g) {
      hue = 60 * ((b - r) / chroma + 2);
    } else {
      hue = 60 * ((r - g) / chroma + 4);
    }
    hues.add(hue);
    saturations.add(saturation);
    lightnesses.add(lightness);
    weights.add(chroma);
    binWeights[(hue / binWidth).floor() % bins] += chroma;
  }
  if (opaque == 0 || hues.length < opaque * 0.10) return null;

  var peak = 0;
  var peakWeight = -1.0;
  for (var bin = 0; bin < bins; bin++) {
    final weight =
        binWeights[(bin + bins - 1) % bins] +
        binWeights[bin] +
        binWeights[(bin + 1) % bins];
    if (weight > peakWeight) {
      peak = bin;
      peakWeight = weight;
    }
  }
  var x = 0.0;
  var y = 0.0;
  var saturationSum = 0.0;
  var lightnessSum = 0.0;
  var weightSum = 0.0;
  for (var index = 0; index < hues.length; index++) {
    final bin = (hues[index] / binWidth).floor() % bins;
    final distance = (bin - peak + bins) % bins;
    if (distance > 1 && distance < bins - 1) continue;
    final weight = weights[index];
    final radians = hues[index] * math.pi / 180;
    x += weight * math.cos(radians);
    y += weight * math.sin(radians);
    saturationSum += weight * saturations[index];
    lightnessSum += weight * lightnesses[index];
    weightSum += weight;
  }
  if (weightSum == 0) return null;
  final hue = (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  return HSLColor.fromAHSL(
    1,
    hue,
    (saturationSum / weightSum).clamp(0.0, 1.0),
    (lightnessSum / weightSum).clamp(0.0, 1.0),
  ).toColor().toARGB32();
}

/// Every gift colour found so far, kept in memory and in preferences so a
/// gift seen before is drawn in its colour from the first frame, even after
/// a relaunch. "No usable colour" is remembered too.
class GiftTintCache {
  GiftTintCache._();

  static final GiftTintCache shared = GiftTintCache._();

  /// Local preference: a JSON object of cache key → ARGB, least recently used
  /// first; 0 means the gift has no usable colour.
  static const preferenceKey = 'giftTintSeeds';
  static const capacity = 500;
  static const int _none = 0;

  SharedPreferences? _preferences;
  final LinkedHashMap<String, int> _seeds = LinkedHashMap<String, int>();
  final Map<String, Future<Color?>> _pending = {};

  /// Keys whose still could not be read this session; they stay on the theme
  /// colour instead of retrying on every rebuild.
  final Set<String> _failed = {};

  void initialize(SharedPreferences preferences) {
    _preferences = preferences;
    final raw = preferences.getString(preferenceKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      for (final entry in decoded.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is String && value is int) _seeds[key] = value;
      }
    } on FormatException {
      return;
    }
  }

  /// Whether [key] has been resolved, to a colour or to none.
  bool knows(String key) => _seeds.containsKey(key) || _failed.contains(key);

  /// The remembered colour for [key]; null when it has none or is unknown.
  Color? seedFor(String key) {
    final value = _seeds.remove(key);
    if (value == null) return null;
    _seeds[key] = value;
    return value == _none ? null : Color(value);
  }

  /// Runs [extract] once for [key] and remembers its answer. Concurrent
  /// callers share the same run; a failed run resolves to null (the theme
  /// colour) and is not retried this session.
  Future<Color?> resolve(String key, Future<int?> Function() extract) {
    if (knows(key)) return SynchronousFuture(seedFor(key));
    return _pending[key] ??= () async {
      try {
        final value = await extract();
        _remember(key, value);
        return value == null ? null : Color(value);
      } catch (_) {
        _failed.add(key);
        return null;
      } finally {
        // Settled: later callers read the remembered answer instead.
        unawaited(_pending.remove(key));
      }
    }();
  }

  void _remember(String key, int? value) {
    _seeds.remove(key);
    _seeds[key] = value ?? _none;
    while (_seeds.length > capacity) {
      _seeds.remove(_seeds.keys.first);
    }
    final preferences = _preferences;
    if (preferences != null) {
      unawaited(preferences.setString(preferenceKey, jsonEncode(_seeds)));
    }
  }
}

/// Resolves a gift's [GiftPalette] and rebuilds as its colour arrives.
///
/// A gift whose colour is already known draws in it from the first frame.
/// The first time a gift is seen it draws in the theme colour, then every
/// colour moves to the gift's own (instantly under Reduce Motion). The
/// builder's probe is non-null only while the colour must come from a
/// rendered frame of the animation; the sticker view feeds it one frame.
class GiftTintBuilder extends StatefulWidget {
  const GiftTintBuilder({
    super.key,
    required this.gift,
    required this.accountSlot,
    required this.builder,
  });

  final MessageGift gift;
  final int accountSlot;
  final Widget Function(
    BuildContext context,
    GiftPalette palette,
    GiftFrameProbe? probe,
  )
  builder;

  @override
  State<GiftTintBuilder> createState() => _GiftTintBuilderState();
}

class _GiftTintBuilderState extends State<GiftTintBuilder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _arrival = AnimationController(
    vsync: this,
    value: 1,
  );
  late final CurvedAnimation _progress = CurvedAnimation(
    parent: _arrival,
    curve: AppMotion.standard,
  );
  String? _key;
  Color? _seed;

  /// Waiting for a rendered frame: the gift has no still to read.
  bool _needsFrame = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(GiftTintBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (giftTintKey(widget.gift) != _key ||
        oldWidget.accountSlot != widget.accountSlot) {
      _bind();
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    _arrival.dispose();
    super.dispose();
  }

  void _bind() {
    _generation++;
    _key = giftTintKey(widget.gift);
    _seed = null;
    _needsFrame = false;
    _arrival.value = 1;
    final key = _key;
    if (key == null || widget.gift.backdropColors != null) return;
    final cache = GiftTintCache.shared;
    if (cache.knows(key)) {
      _seed = cache.seedFor(key);
      return;
    }
    final sticker = widget.gift.sticker;
    final still = sticker == null ? null : giftTintStill(sticker);
    if (still == null) {
      _needsFrame = true;
      return;
    }
    final slot = widget.accountSlot;
    _settle(key, cache.resolve(key, () => _seedFromFile(still, slot)));
  }

  static Future<int?> _seedFromFile(TdFileRef ref, int slot) async {
    final path = await TdFileCenter.shared.pathFor(ref, accountSlot: slot);
    if (path == null) throw StateError('The gift still did not download');
    final bytes = await File(path).readAsBytes();
    return compute(giftSeedFromPixels, (bytes: bytes, width: 0, height: 0));
  }

  void _onFrame(Uint8List rgba, int width, int height) {
    final key = _key;
    if (key == null || !_needsFrame) return;
    _needsFrame = false;
    _settle(
      key,
      GiftTintCache.shared.resolve(
        key,
        () => compute(giftSeedFromPixels, (
          bytes: rgba,
          width: width,
          height: height,
        )),
      ),
    );
  }

  void _settle(String key, Future<Color?> seed) {
    final generation = _generation;
    unawaited(
      seed.then((color) {
        if (!mounted || generation != _generation || key != _key) return;
        setState(() => _seed = color);
        if (color == null) return;
        _arrival.duration = AppMotion.duration(context, AppMotion.responsive);
        unawaited(_arrival.forward(from: 0));
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final light = Theme.of(context).brightness == Brightness.light;
    final backdrop = widget.gift.backdropColors;
    final seed = _seed;
    final probe = _needsFrame ? _onFrame : null;
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, _) {
        if (backdrop != null) {
          return widget.builder(
            context,
            GiftPalette.fromBackdrop(backdrop),
            null,
          );
        }
        final theme = GiftPalette.fromSeed(
          AppTheme.brand,
          colors: colors,
          light: light,
        );
        if (seed == null) return widget.builder(context, theme, probe);
        final tinted = GiftPalette.fromSeed(seed, colors: colors, light: light);
        return widget.builder(
          context,
          GiftPalette.lerp(theme, tinted, _progress.value),
          null,
        );
      },
    );
  }
}
