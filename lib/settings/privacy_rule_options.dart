import 'package:mithka/l10n/app_localizations.dart';

import '../tdlib/json_helpers.dart';

enum PrivacyVisibilityOption {
  everyone,
  contacts,
  nobody;

  String get labelKey => switch (this) {
    PrivacyVisibilityOption.everyone => AppStringKeys.privacyVisibilityEveryone,
    PrivacyVisibilityOption.contacts => AppStringKeys.privacyVisibilityContacts,
    PrivacyVisibilityOption.nobody => AppStringKeys.privacyVisibilityNobody,
  };

  String get ruleType => switch (this) {
    PrivacyVisibilityOption.everyone => 'userPrivacySettingRuleAllowAll',
    PrivacyVisibilityOption.contacts => 'userPrivacySettingRuleAllowContacts',
    PrivacyVisibilityOption.nobody => 'userPrivacySettingRuleRestrictAll',
  };
}

class PrivacyRuleSelection {
  const PrivacyRuleSelection({
    required this.visibility,
    this.allowUserIds = const <int>{},
    this.allowChatIds = const <int>{},
    this.restrictUserIds = const <int>{},
    this.restrictChatIds = const <int>{},
  });

  factory PrivacyRuleSelection.fromRules(List<Map<String, dynamic>> rules) {
    final allowUserIds = <int>{};
    final allowChatIds = <int>{};
    final restrictUserIds = <int>{};
    final restrictChatIds = <int>{};
    for (final rule in rules) {
      switch (rule.type) {
        case 'userPrivacySettingRuleAllowUsers':
          allowUserIds.addAll(rule.int64Array('user_ids') ?? const <int>[]);
        case 'userPrivacySettingRuleAllowChatMembers':
          allowChatIds.addAll(rule.int64Array('chat_ids') ?? const <int>[]);
        case 'userPrivacySettingRuleRestrictUsers':
          restrictUserIds.addAll(rule.int64Array('user_ids') ?? const <int>[]);
        case 'userPrivacySettingRuleRestrictChatMembers':
          restrictChatIds.addAll(rule.int64Array('chat_ids') ?? const <int>[]);
      }
    }
    return PrivacyRuleSelection(
      visibility: privacyVisibilityFromRules(rules),
      allowUserIds: allowUserIds,
      allowChatIds: allowChatIds,
      restrictUserIds: restrictUserIds,
      restrictChatIds: restrictChatIds,
    );
  }

  final PrivacyVisibilityOption visibility;
  final Set<int> allowUserIds;
  final Set<int> allowChatIds;
  final Set<int> restrictUserIds;
  final Set<int> restrictChatIds;

  PrivacyRuleSelection copyWith({
    PrivacyVisibilityOption? visibility,
    Set<int>? allowUserIds,
    Set<int>? allowChatIds,
    Set<int>? restrictUserIds,
    Set<int>? restrictChatIds,
  }) => PrivacyRuleSelection(
    visibility: visibility ?? this.visibility,
    allowUserIds: allowUserIds ?? this.allowUserIds,
    allowChatIds: allowChatIds ?? this.allowChatIds,
    restrictUserIds: restrictUserIds ?? this.restrictUserIds,
    restrictChatIds: restrictChatIds ?? this.restrictChatIds,
  );

  List<Map<String, dynamic>> toRules() {
    final rules = <Map<String, dynamic>>[];
    if (visibility != PrivacyVisibilityOption.everyone &&
        allowUserIds.isNotEmpty) {
      rules.add({
        '@type': 'userPrivacySettingRuleAllowUsers',
        'user_ids': allowUserIds.toList(),
      });
    }
    if (visibility != PrivacyVisibilityOption.everyone &&
        allowChatIds.isNotEmpty) {
      rules.add({
        '@type': 'userPrivacySettingRuleAllowChatMembers',
        'chat_ids': allowChatIds.toList(),
      });
    }
    if (visibility != PrivacyVisibilityOption.nobody &&
        restrictUserIds.isNotEmpty) {
      rules.add({
        '@type': 'userPrivacySettingRuleRestrictUsers',
        'user_ids': restrictUserIds.toList(),
      });
    }
    if (visibility != PrivacyVisibilityOption.nobody &&
        restrictChatIds.isNotEmpty) {
      rules.add({
        '@type': 'userPrivacySettingRuleRestrictChatMembers',
        'chat_ids': restrictChatIds.toList(),
      });
    }
    rules.add({'@type': visibility.ruleType});
    return rules;
  }
}

PrivacyVisibilityOption privacyVisibilityFromRules(
  List<Map<String, dynamic>> rules,
) {
  var value = PrivacyVisibilityOption.everyone;
  for (final rule in rules) {
    final broadRule = switch (rule.type) {
      'userPrivacySettingRuleAllowAll' => PrivacyVisibilityOption.everyone,
      'userPrivacySettingRuleAllowContacts' => PrivacyVisibilityOption.contacts,
      'userPrivacySettingRuleRestrictAll' => PrivacyVisibilityOption.nobody,
      _ => null,
    };
    if (broadRule != null) value = broadRule;
  }
  return value;
}
