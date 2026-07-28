import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/profile/profile_username_summary.dart';

void main() {
  group('compactProfileUsernameLabels', () {
    test('shows only the primary username when it is the only one', () {
      expect(compactProfileUsernameLabels(['primary']), ['@primary']);
    });

    test('summarizes extra active usernames as a count', () {
      expect(
        compactProfileUsernameLabels([
          'primary',
          'collectible_one',
          'collectible_two',
        ]),
        ['@primary', '+2'],
      );
    });

    test('returns no labels when there is no active username', () {
      expect(compactProfileUsernameLabels(const []), isEmpty);
    });
  });
}
