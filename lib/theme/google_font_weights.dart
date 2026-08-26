//
//  google_font_weights.dart
//
//  Real weight faces for a runtime Google font.
//
//  google_fonts fetches one file per weight and registers each under its own
//  variant-suffixed family — `NotoSansTC_regular`, `NotoSansTC_500` — then
//  returns a style pinned to that name. Such a family holds exactly one face,
//  so asking it for w600, which most of this app's labels do, gets Skia's
//  synthetic embolden of the regular face instead of the designed SemiBold:
//  same advance widths, roughly 11% more ink, and w600 and w700 identical.
//
//  Registering the faces together under the plain family name lets Flutter
//  match a requested weight to a real file. The bytes are the ones google_fonts
//  already wrote to the application support directory, so this costs one extra
//  weight of bandwidth rather than a second copy of the family.
//

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';

/// The weights this app actually renders. w600 dominates its labels; w400 and
/// w500 arrive from the Material text theme.
const List<FontWeight> kGoogleFontWeights = [
  FontWeight.w400,
  FontWeight.w500,
  FontWeight.w600,
];

/// The variant segment google_fonts puts in a cached file's name.
///
/// It writes `<Family><NoSpaces>_<variant>_<hash>.ttf`, where the variant is
/// `regular` for 400 and the plain number otherwise.
@visibleForTesting
String googleFontVariantSegment(FontWeight weight) =>
    weight == FontWeight.w400 ? 'regular' : '${weight.value}';

/// Matches a cached file for [googleFamily] to the weight it carries, or null
/// when the name is not one of google_fonts' own.
@visibleForTesting
FontWeight? googleFontWeightOfCacheFile({
  required String googleFamily,
  required String fileName,
}) {
  final prefix = '${googleFamily.replaceAll(' ', '')}_';
  if (!fileName.startsWith(prefix) || !fileName.endsWith('.ttf')) return null;
  final rest = fileName.substring(prefix.length, fileName.length - 4);
  final separator = rest.lastIndexOf('_');
  if (separator <= 0) return null;
  final variant = rest.substring(0, separator);
  for (final weight in kGoogleFontWeights) {
    if (googleFontVariantSegment(weight) == variant) return weight;
  }
  return null;
}

/// Loads a Google family's weight faces under one family name.
///
/// Notifies once a family gains its real faces, so a text style cached against
/// the single-face variant name can be recomputed.
class GoogleFontWeightLoader extends ChangeNotifier {
  GoogleFontWeightLoader._();

  @visibleForTesting
  GoogleFontWeightLoader.forTesting();

  static final shared = GoogleFontWeightLoader._();

  final Set<String> _loaded = {};
  final Map<String, Future<void>> _inFlight = {};

  /// The family to name in a [TextStyle] once its faces are registered, or
  /// null while this process is still using google_fonts' per-variant naming.
  String? loadedFamily(String googleFamily) =>
      _loaded.contains(googleFamily) ? googleFamily : null;

  /// Fetches [googleFamily]'s weights and registers them together. Repeat
  /// calls for a family already loaded or in flight are free.
  Future<void> ensure(String googleFamily) {
    if (_loaded.contains(googleFamily)) return Future.value();
    return _inFlight[googleFamily] ??= _load(
      googleFamily,
    ).catchError((_) {}).whenComplete(() => _inFlight.remove(googleFamily));
  }

  Future<void> _load(String googleFamily) async {
    // Ask google_fonts for each weight first: that is what downloads the file
    // and puts it in the cache this then reads.
    for (final weight in kGoogleFontWeights) {
      GoogleFonts.getFont(googleFamily, fontWeight: weight);
    }
    await GoogleFonts.pendingFonts();

    final faces = await _cachedFaces(googleFamily);
    if (faces.isEmpty) return;
    final loader = FontLoader(googleFamily);
    for (final face in faces) {
      loader.addFont(face.readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
    _loaded.add(googleFamily);
    notifyListeners();
  }

  /// One file per requested weight, newest wins when a family was re-fetched
  /// under a new hash.
  Future<List<File>> _cachedFaces(String googleFamily) async {
    final Directory support;
    try {
      support = await getApplicationSupportDirectory();
    } catch (_) {
      return const [];
    }
    if (!support.existsSync()) return const [];
    final byWeight = <FontWeight, File>{};
    await for (final entity in support.list()) {
      if (entity is! File) continue;
      final weight = googleFontWeightOfCacheFile(
        googleFamily: googleFamily,
        fileName: entity.uri.pathSegments.last,
      );
      if (weight == null) continue;
      final existing = byWeight[weight];
      if (existing != null &&
          existing.statSync().modified.isAfter(entity.statSync().modified)) {
        continue;
      }
      byWeight[weight] = entity;
    }
    return byWeight.values.toList(growable: false);
  }
}
