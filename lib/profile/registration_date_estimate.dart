//
//  registration_date_estimate.dart
//
//  Account age from a user ID alone. Telegram hands user IDs out roughly in
//  creation order, so interpolating between the anchors in
//  registration_date_anchors.dart estimates when an account was created. It
//  runs offline on purpose: asking a lookup service would tell a third party
//  which profiles the user is reading.
//
//  What the answer is worth:
//
//  * An estimate, never a fact. Telegram's own `chat.action_bar.account_info`
//    (registration year and month) wins wherever TDLib provides it, and a
//    caller that shows an estimate has to say so ("Around March 2021").
//  * Only for private user accounts. The upstream dataset is built from those
//    and excludes bots, so a bot ID has no position in this sequence and must
//    not be dated by it — the caller knows which profiles are bots, this file
//    does not.
//  * Only inside the fitted ID range. An ID past the newest anchor is not
//    "newer than" anything the table can prove: adjacent anchors in the raw
//    dataset invert often enough that the sequence is a trend, not a bound.
//    Those IDs get no answer rather than a claim this data cannot support.
//

import 'registration_date_anchors.dart';

/// Estimates the day [userId] was created, at UTC midnight, or null when this
/// table has no position for the ID.
///
/// Null covers every case an estimate would be invented for: chat and channel
/// IDs (negative), the anonymous service ID (0), and any ID outside
/// [registrationAnchorUserIds]' fitted range — older than the oldest anchor or
/// newer than the newest one.
DateTime? estimateRegistrationDate(int userId) {
  const ids = registrationAnchorUserIds;
  const days = registrationAnchorDaysSinceEpoch;
  if (ids.length < 2 || days.length != ids.length) return null;
  if (userId <= 0 || userId < ids.first || userId > ids.last) return null;

  // First anchor above userId; ids is strictly ascending, so userId sits in
  // the (lower, upper) pair and interpolation stays inside the table.
  var low = 0;
  var high = ids.length - 1;
  while (low < high) {
    final mid = (low + high) >> 1;
    if (ids[mid] <= userId) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  final upper = low;
  final lower = upper - 1;
  final span = ids[upper] - ids[lower];
  final day = span <= 0
      ? days[lower]
      : days[lower] +
            ((days[upper] - days[lower]) * (userId - ids[lower]) / span)
                .round();
  return DateTime.fromMillisecondsSinceEpoch(
    day * Duration.millisecondsPerDay,
    isUtc: true,
  );
}
