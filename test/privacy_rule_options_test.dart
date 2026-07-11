import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/settings/privacy_rule_options.dart';

void main() {
  test('decodes nobody as the effective broad privacy rule', () {
    expect(
      privacyVisibilityFromRules([
        {'@type': 'userPrivacySettingRuleAllowAll'},
        {'@type': 'userPrivacySettingRuleRestrictAll'},
      ]),
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
