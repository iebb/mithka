import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/settings/privacy_rule_options.dart';

void main() {
  test('ignores exception rules and keeps the broad rule', () {
    expect(
      privacyVisibilityFromRules([
        {
          '@type': 'userPrivacySettingRuleAllowUsers',
          'user_ids': ['1'],
        },
        {'@type': 'userPrivacySettingRuleRestrictAll'},
      ]),
      PrivacyVisibilityOption.nobody,
    );
  });

  test('round-trips unmanaged rules without reordering or flattening them', () {
    final source = <Map<String, dynamic>>[
      {
        '@type': 'userPrivacySettingRuleRestrictUsers',
        'user_ids': [11],
      },
      {'@type': 'userPrivacySettingRuleAllowPremiumUsers'},
      {'@type': 'userPrivacySettingRuleRestrictBots'},
      {'@type': 'userPrivacySettingRuleRestrictContacts'},
      {
        '@type': 'userPrivacySettingRuleFutureAudience',
        'options': {
          'enabled': true,
          'levels': [1, 2],
        },
      },
      {'@type': 'userPrivacySettingRuleAllowAll'},
    ];

    final selection = PrivacyRuleSelection.fromRules(source);

    expect(selection.toRules(), source);

    // The selection owns a copy of the TDLib update, including nested values.
    (source[4]['options'] as Map<String, dynamic>)['enabled'] = false;
    expect(selection.toRules()[4]['options'], {
      'enabled': true,
      'levels': [1, 2],
    });
  });

  test('edits the broad rule while preserving special rule positions', () {
    final selection = PrivacyRuleSelection.fromRules([
      {'@type': 'userPrivacySettingRuleAllowBots'},
      {'@type': 'userPrivacySettingRuleRestrictContacts'},
      {'@type': 'userPrivacySettingRuleAllowAll'},
      {'@type': 'userPrivacySettingRuleAllowPremiumUsers'},
    ]);

    expect(
      selection
          .copyWith(visibility: PrivacyVisibilityOption.nobody)
          .toRules()
          .map((rule) => rule['@type']),
      [
        'userPrivacySettingRuleAllowBots',
        'userPrivacySettingRuleRestrictContacts',
        'userPrivacySettingRuleRestrictAll',
        'userPrivacySettingRuleAllowPremiumUsers',
      ],
    );
  });

  test('edits exception rules in place and inserts new exception types', () {
    final selection =
        PrivacyRuleSelection.fromRules([
          {
            '@type': 'userPrivacySettingRuleAllowUsers',
            'user_ids': ['11'],
          },
          {'@type': 'userPrivacySettingRuleAllowPremiumUsers'},
          {
            '@type': 'userPrivacySettingRuleRestrictUsers',
            'user_ids': ['12'],
          },
          {'@type': 'userPrivacySettingRuleAllowContacts'},
        ]).copyWith(
          allowUserIds: {21, 22},
          allowChatIds: {-1001},
          restrictUserIds: {23},
        );

    expect(selection.toRules(), [
      {
        '@type': 'userPrivacySettingRuleAllowUsers',
        'user_ids': [21, 22],
      },
      {
        '@type': 'userPrivacySettingRuleAllowChatMembers',
        'chat_ids': [-1001],
      },
      {'@type': 'userPrivacySettingRuleAllowPremiumUsers'},
      {
        '@type': 'userPrivacySettingRuleRestrictUsers',
        'user_ids': [23],
      },
      {'@type': 'userPrivacySettingRuleAllowContacts'},
    ]);
  });
}
