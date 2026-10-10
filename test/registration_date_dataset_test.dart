import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/profile/registration_date_anchors.dart';

/// What the vendored dataset says, so the shipped table can be audited against
/// the exact bytes it was generated from.
class _Dataset {
  _Dataset({required this.entries, required this.digest});

  factory _Dataset.read() {
    const path = 'data/tg_points.json';
    final file = File(path);
    if (!file.existsSync()) {
      throw StateError(
        '$path is missing, so the shipped anchor table is not reproducible',
      );
    }
    final bytes = file.readAsBytesSync();
    final payload = jsonDecode(utf8.decode(bytes)) as List;

    // One entry per submitted ID keeping its earliest submitted date — the
    // same reading tool/gen_registration_anchors.py does before it fits.
    final earliest = <int, DateTime>{};
    for (final entry in payload) {
      final pair = entry as List;
      final userId = (pair[0] as num).toInt();
      if (userId < 0) continue;
      final day = DateTime.parse('${pair[1]}T00:00:00Z');
      final known = earliest[userId];
      if (known == null || day.isBefore(known)) earliest[userId] = day;
    }
    final sortedIds = earliest.keys.toList()..sort();
    final entries = <(int, DateTime)>[
      for (final id in sortedIds) (id, earliest[id]!),
    ];
    return _Dataset(entries: entries, digest: sha256.convert(bytes).toString());
  }

  /// Submitted `(user ID, day)` pairs, ascending by ID.
  final List<(int, DateTime)> entries;

  /// SHA-256 of the vendored file, hex encoded.
  final String digest;

  /// Adjacent pairs where a larger ID carries an earlier day.
  int get inversions {
    var count = 0;
    for (var i = 1; i < entries.length; i++) {
      if (entries[i].$2.isBefore(entries[i - 1].$2)) count++;
    }
    return count;
  }
}

void main() {
  const ids = registrationAnchorUserIds;
  const days = registrationAnchorDaysSinceEpoch;
  final dataset = _Dataset.read();

  DateTime dayAt(int daysSinceEpoch) => DateTime.fromMillisecondsSinceEpoch(
    daysSinceEpoch * Duration.millisecondsPerDay,
    isUtc: true,
  );

  test('the shipped table was built from the shipped dataset', () {
    // Regenerating the table without vendoring its new input — or swapping the
    // input without regenerating — breaks this, so the pair stays auditable.
    expect(dataset.digest, registrationDatasetSha256);
  });

  test('the dataset pin names an upstream revision', () {
    expect(
      RegExp(r'^[0-9a-f]{40}$').hasMatch(registrationDatasetRevision),
      isTrue,
      reason: registrationDatasetRevision,
    );
  });

  test('the vendored dataset carries its own license', () {
    final license = File('data/LICENSE').readAsStringSync();
    expect(license, contains('MIT License'));
    expect(license, contains('Wizard Loop'));
  });

  test(
    'anchors are submitted accounts and the fit stops where the data does',
    () {
      final submitted = {for (final entry in dataset.entries) entry.$1};
      for (final id in ids) {
        expect(submitted.contains(id), isTrue, reason: 'anchor $id');
      }

      // The estimator interpolates and nothing more: both ends of the fitted
      // range are ends of the dataset, so no ID is dated past what the
      // submissions cover.
      expect(ids.first, dataset.entries.first.$1);
      expect(ids.last, dataset.entries.last.$1);
      final newestSubmitted = dataset.entries
          .map((entry) => entry.$2)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      expect(dayAt(days.last).isAfter(newestSubmitted), isFalse);
    },
  );

  test('the fit is monotone where the submissions are not', () {
    // Why the generator runs an isotonic regression at all: submissions invert
    // often enough that raw interpolation would date some newer accounts
    // earlier than older ones, and two profiles would then disagree.
    expect(dataset.inversions, greaterThan(0));
    for (var i = 1; i < days.length; i++) {
      expect(days[i], greaterThanOrEqualTo(days[i - 1]), reason: 'anchor $i');
    }
  });
}
