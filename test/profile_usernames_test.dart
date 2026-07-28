import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  group('TDParse.activeUsernames', () {
    test('keeps active collectible usernames in display-priority order', () {
      final user = <String, dynamic>{
        'id': 42,
        'usernames': {
          'active_usernames': [
            'primary_name',
            'collectible_one',
            '@Collectible_Two',
            'COLLECTIBLE_ONE',
            '',
          ],
          'disabled_usernames': ['disabled_collectible'],
          'editable_username': 'primary_name',
          'collectible_usernames': [
            'collectible_one',
            'Collectible_Two',
            'disabled_collectible',
          ],
        },
      };

      expect(TDParse.activeUsernames(user), [
        'primary_name',
        'collectible_one',
        'Collectible_Two',
      ]);
      expect(TDParse.userName(user), '@primary_name');
    });

    test('does not expose an explicitly inactive editable username', () {
      final user = <String, dynamic>{
        'usernames': {
          'active_usernames': <String>[],
          'editable_username': 'inactive_name',
        },
      };

      expect(TDParse.activeUsernames(user), isEmpty);
    });

    test('falls back to editable username when active list is absent', () {
      final user = <String, dynamic>{
        'usernames': {'editable_username': '@legacy_name'},
      };

      expect(TDParse.activeUsernames(user), ['legacy_name']);
    });
  });
}
