import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/settings/privacy_rule_options.dart';

void main() {
  test('uses the first matching broad privacy rule', () {
    expect(
      privacyVisibilityFromRules([
        {'@type': 'userPrivacySettingRuleAllowAll'},
        {'@type': 'userPrivacySettingRuleRestrictAll'},
      ]),
      PrivacyVisibilityOption.everyone,
    );
  });

  test('decodes empty rules as nobody', () {
    expect(
      privacyVisibilityFromRules(const []),
      PrivacyVisibilityOption.nobody,
    );
  });

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

  test('uses contacts as the broad privacy rule', () {
    expect(
      privacyVisibilityFromRules([
        {
          '@type': 'userPrivacySettingRuleRestrictUsers',
          'user_ids': ['2'],
        },
        {'@type': 'userPrivacySettingRuleAllowContacts'},
      ]),
      PrivacyVisibilityOption.contacts,
    );
  });

  test('contacts followed by restrict all remains contacts', () {
    expect(
      privacyVisibilityFromRules([
        {'@type': 'userPrivacySettingRuleAllowContacts'},
        {'@type': 'userPrivacySettingRuleRestrictAll'},
      ]),
      PrivacyVisibilityOption.contacts,
    );
  });

  test('parses nested privacy rule updates', () {
    final update = privacyRulesUpdateFromTdObject({
      '@type': 'updateUserPrivacySettingRules',
      'setting': {'@type': 'userPrivacySettingShowStatus'},
      'rules': {
        '@type': 'userPrivacySettingRules',
        'rules': [
          {
            '@type': 'userPrivacySettingRuleAllowUsers',
            'user_ids': ['11'],
          },
          {'@type': 'userPrivacySettingRuleRestrictAll'},
        ],
      },
    });

    expect(update?.setting, 'userPrivacySettingShowStatus');
    expect(update?.selection.visibility, PrivacyVisibilityOption.nobody);
    expect(update?.selection.allowUserIds, {11});
    expect(update?.matchesSetting('userPrivacySettingShowStatus'), isTrue);
    expect(
      update?.matchesSetting('userPrivacySettingShowPhoneNumber'),
      isFalse,
    );
  });

  test('decodes an empty privacy rules update as nobody', () {
    final update = privacyRulesUpdateFromTdObject({
      '@type': 'updateUserPrivacySettingRules',
      'setting': {'@type': 'userPrivacySettingShowStatus'},
      'rules': {'@type': 'userPrivacySettingRules', 'rules': []},
    });

    expect(update?.selection.visibility, PrivacyVisibilityOption.nobody);
  });

  test('rejects unrelated or malformed privacy rule updates', () {
    expect(privacyRulesUpdateFromTdObject({'@type': 'updateUser'}), isNull);
    expect(
      privacyRulesUpdateFromTdObject({
        '@type': 'updateUserPrivacySettingRules',
        'setting': {'@type': 'userPrivacySettingShowStatus'},
        'rules': [],
      }),
      isNull,
    );
    expect(
      privacyRulesUpdateFromTdObject({
        '@type': 'updateUserPrivacySettingRules',
        'setting': {'@type': 'userPrivacySettingShowStatus'},
        'rules': {'@type': 'unexpectedRulesContainer', 'rules': []},
      }),
      isNull,
    );
    expect(
      privacyRulesUpdateFromTdObject({
        '@type': 'updateUserPrivacySettingRules',
        'setting': {'@type': 'userPrivacySettingShowStatus'},
        'rules': {
          '@type': 'userPrivacySettingRules',
          'rules': [
            {
              'user_ids': ['11'],
            },
          ],
        },
      }),
      isNull,
    );
    expect(
      privacyRulesUpdateFromTdObject({
        '@type': 'updateUserPrivacySettingRules',
        'setting': {'@type': 'userPrivacySettingShowStatus'},
        'rules': {
          '@type': 'userPrivacySettingRules',
          'rules': [true],
        },
      }),
      isNull,
    );
    expect(
      privacyRulesUpdateFromTdObject({
        '@type': 'updateUserPrivacySettingRules',
        'setting': {'@type': 42},
        'rules': {'@type': 'userPrivacySettingRules', 'rules': []},
      }),
      isNull,
    );
    expect(
      privacyRulesUpdateFromTdObject({
        '@type': 'updateUserPrivacySettingRules',
        'setting': {'@type': 'userPrivacySettingShowStatus'},
        'rules': {
          '@type': 'userPrivacySettingRules',
          'rules': [
            {'@type': 42},
          ],
        },
      }),
      isNull,
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

  test('inserts a new user exception before special audience rules', () {
    final selection = PrivacyRuleSelection.fromRules([
      {'@type': 'userPrivacySettingRuleRestrictBots'},
      {'@type': 'userPrivacySettingRuleAllowAll'},
    ]).copyWith(visibility: PrivacyVisibilityOption.nobody, allowUserIds: {42});

    expect(selection.toRules(), [
      {
        '@type': 'userPrivacySettingRuleAllowUsers',
        'user_ids': [42],
      },
      {'@type': 'userPrivacySettingRuleRestrictBots'},
      {'@type': 'userPrivacySettingRuleRestrictAll'},
    ]);
  });

  test('round-trips user and group exceptions with the broad rule', () {
    final selection = PrivacyRuleSelection.fromRules([
      {
        '@type': 'userPrivacySettingRuleAllowUsers',
        'user_ids': ['11', '12'],
      },
      {
        '@type': 'userPrivacySettingRuleAllowChatMembers',
        'chat_ids': ['-1001'],
      },
      {
        '@type': 'userPrivacySettingRuleRestrictUsers',
        'user_ids': ['13'],
      },
      {'@type': 'userPrivacySettingRuleAllowContacts'},
    ]);

    expect(selection.visibility, PrivacyVisibilityOption.contacts);
    expect(selection.allowUserIds, {11, 12});
    expect(selection.allowChatIds, {-1001});
    expect(selection.restrictUserIds, {13});
    expect(selection.toRules().map((rule) => rule['@type']), [
      'userPrivacySettingRuleAllowUsers',
      'userPrivacySettingRuleAllowChatMembers',
      'userPrivacySettingRuleRestrictUsers',
      'userPrivacySettingRuleAllowContacts',
    ]);
  });

  test('omits exception rules that are redundant for the broad rule', () {
    const everyone = PrivacyRuleSelection(
      visibility: PrivacyVisibilityOption.everyone,
      allowUserIds: {1},
      restrictUserIds: {2},
    );
    const nobody = PrivacyRuleSelection(
      visibility: PrivacyVisibilityOption.nobody,
      allowUserIds: {1},
      restrictUserIds: {2},
    );

    expect(everyone.toRules().map((rule) => rule['@type']), [
      'userPrivacySettingRuleRestrictUsers',
      'userPrivacySettingRuleAllowAll',
    ]);
    expect(nobody.toRules().map((rule) => rule['@type']), [
      'userPrivacySettingRuleAllowUsers',
      'userPrivacySettingRuleRestrictAll',
    ]);
  });
}
