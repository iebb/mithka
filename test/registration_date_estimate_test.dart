import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/profile/registration_date_anchors.dart';
import 'package:mithka/profile/registration_date_estimate.dart';

void main() {
  const ids = registrationAnchorUserIds;
  const days = registrationAnchorDaysSinceEpoch;

  DateTime dayAt(int daysSinceEpoch) => DateTime.fromMillisecondsSinceEpoch(
    daysSinceEpoch * Duration.millisecondsPerDay,
    isUtc: true,
  );

  group('anchor table', () {
    test('is paired, ascending by ID and never moves back in time', () {
      expect(ids.length, greaterThanOrEqualTo(2));
      expect(days.length, ids.length);
      for (var i = 1; i < ids.length; i++) {
        expect(ids[i], greaterThan(ids[i - 1]), reason: 'anchor $i');
        expect(days[i], greaterThanOrEqualTo(days[i - 1]), reason: 'anchor $i');
      }
    });

    test('reaches from the launch day into the wide ID space', () {
      expect(ids.first, 0);
      expect(dayAt(days.first), DateTime.utc(2013, 8, 14));
      // Telegram widened user IDs past 2^32 in 2022; a table that stopped
      // there would date every modern account as nothing at all.
      expect(ids.last, greaterThan(1 << 32));
    });
  });

  group('estimateRegistrationDate', () {
    test('rejects IDs that are not positions in the user sequence', () {
      expect(estimateRegistrationDate(0), isNull);
      expect(estimateRegistrationDate(-1), isNull);
      expect(estimateRegistrationDate(-1002345678901), isNull);
    });

    test('lands exactly on every anchor it knows', () {
      for (var i = 0; i < ids.length; i++) {
        if (ids[i] <= 0) {
          // The launch anchor is a reference point, not somebody's account.
          continue;
        }
        expect(
          estimateRegistrationDate(ids[i]),
          dayAt(days[i]),
          reason: 'anchor ${ids[i]}',
        );
      }
    });

    test('interpolates inside the bracketing anchors', () {
      for (final userId in [1, 777000, 400169473, 1234567890, ids.last - 1]) {
        var upper = 1;
        while (ids[upper] <= userId) {
          upper++;
        }
        final lower = upper - 1;
        final estimate = estimateRegistrationDate(userId)!;
        expect(
          estimate.millisecondsSinceEpoch,
          greaterThanOrEqualTo(dayAt(days[lower]).millisecondsSinceEpoch),
          reason: '$userId lower bound',
        );
        expect(
          estimate.millisecondsSinceEpoch,
          lessThanOrEqualTo(dayAt(days[upper]).millisecondsSinceEpoch),
          reason: '$userId upper bound',
        );
      }
    });

    test('never dates a newer ID earlier than an older one', () {
      DateTime? previous;
      for (var step = 0; step <= 500; step++) {
        final userId = 1 + (ids.last - 1) * step ~/ 500;
        final day = estimateRegistrationDate(userId)!;
        if (previous != null) {
          expect(day.isBefore(previous), isFalse, reason: '$userId');
        }
        previous = day;
      }
    });

    test('answers nothing for an ID outside the fitted range', () {
      // The table is a trend fitted on submitted accounts, not a guarantee
      // that every larger ID was created later, so an ID past the newest
      // anchor gets no answer rather than a bound the data cannot support.
      for (final userId in [ids.last + 1, 99999999999, 1 << 40]) {
        expect(estimateRegistrationDate(userId), isNull, reason: '$userId');
      }
    });

    test("dates launch-era accounts to Telegram's first years", () {
      // 777000 is Telegram's own service number, 3655823 its founder's.
      final service = estimateRegistrationDate(777000)!;
      final founder = estimateRegistrationDate(3655823)!;
      expect(service.year, 2013);
      expect(founder.year, lessThanOrEqualTo(2014));
      expect(founder.isAfter(service), isTrue);
    });

    test('reads as a day at UTC midnight, so month edges stay put', () {
      final estimate = estimateRegistrationDate(1234567890)!;
      expect(estimate.isUtc, isTrue);
      expect(estimate.hour, 0);
      expect(estimate.minute, 0);
      expect(estimate.second, 0);
    });
  });
}
