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
  }) : _ruleTemplate = const <Map<String, dynamic>>[];

  const PrivacyRuleSelection._({
    required this.visibility,
    required this.allowUserIds,
    required this.allowChatIds,
    required this.restrictUserIds,
    required this.restrictChatIds,
    required this._ruleTemplate,
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
    return PrivacyRuleSelection._(
      visibility: privacyVisibilityFromRules(rules),
      allowUserIds: allowUserIds,
      allowChatIds: allowChatIds,
      restrictUserIds: restrictUserIds,
      restrictChatIds: restrictChatIds,
      ruleTemplate: rules.map(_cloneRule).toList(),
    );
  }

  final PrivacyVisibilityOption visibility;
  final Set<int> allowUserIds;
  final Set<int> allowChatIds;
  final Set<int> restrictUserIds;
  final Set<int> restrictChatIds;
  final List<Map<String, dynamic>> _ruleTemplate;

  PrivacyRuleSelection copyWith({
    PrivacyVisibilityOption? visibility,
    Set<int>? allowUserIds,
    Set<int>? allowChatIds,
    Set<int>? restrictUserIds,
    Set<int>? restrictChatIds,
  }) => PrivacyRuleSelection._(
    visibility: visibility ?? this.visibility,
    allowUserIds: allowUserIds ?? this.allowUserIds,
    allowChatIds: allowChatIds ?? this.allowChatIds,
    restrictUserIds: restrictUserIds ?? this.restrictUserIds,
    restrictChatIds: restrictChatIds ?? this.restrictChatIds,
    ruleTemplate: _ruleTemplate,
  );

  List<Map<String, dynamic>> toRules() {
    final managedExceptions = <String, Map<String, dynamic>>{};
    if (visibility != PrivacyVisibilityOption.everyone &&
        allowUserIds.isNotEmpty) {
      managedExceptions['userPrivacySettingRuleAllowUsers'] = {
        '@type': 'userPrivacySettingRuleAllowUsers',
        'user_ids': allowUserIds.toList(),
      };
    }
    if (visibility != PrivacyVisibilityOption.everyone &&
        allowChatIds.isNotEmpty) {
      managedExceptions['userPrivacySettingRuleAllowChatMembers'] = {
        '@type': 'userPrivacySettingRuleAllowChatMembers',
        'chat_ids': allowChatIds.toList(),
      };
    }
    if (visibility != PrivacyVisibilityOption.nobody &&
        restrictUserIds.isNotEmpty) {
      managedExceptions['userPrivacySettingRuleRestrictUsers'] = {
        '@type': 'userPrivacySettingRuleRestrictUsers',
        'user_ids': restrictUserIds.toList(),
      };
    }
    if (visibility != PrivacyVisibilityOption.nobody &&
        restrictChatIds.isNotEmpty) {
      managedExceptions['userPrivacySettingRuleRestrictChatMembers'] = {
        '@type': 'userPrivacySettingRuleRestrictChatMembers',
        'chat_ids': restrictChatIds.toList(),
      };
    }

    if (_ruleTemplate.isEmpty) {
      final rules = <Map<String, dynamic>>[];
      for (final type in _managedExceptionTypes) {
        final rule = managedExceptions[type];
        if (rule != null) rules.add(_cloneRule(rule));
      }
      rules.add({'@type': visibility.ruleType});
      return rules;
    }

    // TDLib evaluates privacy rules in order. Keep rules which this UI doesn't
    // understand in their original positions, and only replace the rule kinds
    // represented by the broad selector and exception editors.
    final templateTypes = _ruleTemplate.map((rule) => rule.type).toSet();
    final missingExceptions = <Map<String, dynamic>>[];
    for (final type in _managedExceptionTypes) {
      if (templateTypes.contains(type)) continue;
      final rule = managedExceptions[type];
      if (rule != null) missingExceptions.add(rule);
    }
    final rules = <Map<String, dynamic>>[];
    final writtenExceptionTypes = <String>{};
    var wroteMissingExceptions = false;
    var wroteBroadRule = false;

    void writeMissingExceptions() {
      if (wroteMissingExceptions) return;
      rules.addAll(missingExceptions.map(_cloneRule));
      wroteMissingExceptions = true;
    }

    for (final sourceRule in _ruleTemplate) {
      final type = sourceRule.type;
      // Explicit user/chat exceptions need the highest priority. Insert newly
      // created exception kinds before the first special or broad rule.
      if (!_managedExceptionTypes.contains(type)) writeMissingExceptions();
      if (_managedBroadTypes.contains(type)) {
        if (!wroteBroadRule) {
          rules.add({'@type': visibility.ruleType});
          wroteBroadRule = true;
        }
        continue;
      }
      if (_managedExceptionTypes.contains(type)) {
        if (type != null && writtenExceptionTypes.add(type)) {
          final replacement = managedExceptions[type];
          if (replacement != null) rules.add(_cloneRule(replacement));
        }
        continue;
      }
      rules.add(_cloneRule(sourceRule));
    }

    writeMissingExceptions();
    if (!wroteBroadRule) rules.add({'@type': visibility.ruleType});
    return rules;
  }
}

const _managedExceptionTypes = <String>[
  'userPrivacySettingRuleAllowUsers',
  'userPrivacySettingRuleAllowChatMembers',
  'userPrivacySettingRuleRestrictUsers',
  'userPrivacySettingRuleRestrictChatMembers',
];

const _managedBroadTypes = <String>{
  'userPrivacySettingRuleAllowAll',
  'userPrivacySettingRuleAllowContacts',
  'userPrivacySettingRuleRestrictAll',
};

Map<String, dynamic> _cloneRule(Map<String, dynamic> rule) => {
  for (final entry in rule.entries) entry.key: _cloneJsonValue(entry.value),
};

dynamic _cloneJsonValue(dynamic value) {
  if (value is Map<String, dynamic>) return _cloneRule(value);
  if (value is List) return value.map(_cloneJsonValue).toList();
  return value;
}

class PrivacyRulesUpdate {
  const PrivacyRulesUpdate({required this.setting, required this.selection});

  final String setting;
  final PrivacyRuleSelection selection;

  bool matchesSetting(String expectedSetting) => setting == expectedSetting;
}

PrivacyRulesUpdate? privacyRulesUpdateFromTdObject(
  Map<String, dynamic> update,
) {
  if (update['@type'] != 'updateUserPrivacySettingRules') return null;
  final settingObject = update.obj('setting');
  final setting = settingObject?['@type'];
  final rulesObject = update.obj('rules');
  if (setting is! String ||
      rulesObject?['@type'] != 'userPrivacySettingRules' ||
      rulesObject!['rules'] is! List) {
    return null;
  }
  final rules = <Map<String, dynamic>>[];
  for (final value in rulesObject['rules'] as List) {
    if (value is! Map<String, dynamic> || value['@type'] is! String) {
      return null;
    }
    rules.add(value);
  }
  return PrivacyRulesUpdate(
    setting: setting,
    selection: PrivacyRuleSelection.fromRules(rules),
  );
}

PrivacyVisibilityOption privacyVisibilityFromRules(
  List<Map<String, dynamic>> rules,
) {
  bool isAllowed({required bool isContact}) {
    for (final rule in rules) {
      final result = switch (rule.type) {
        'userPrivacySettingRuleAllowContacts' when isContact => true,
        'userPrivacySettingRuleRestrictContacts' when isContact => false,
        'userPrivacySettingRuleAllowAll' => true,
        'userPrivacySettingRuleRestrictAll' => false,
        _ => null,
      };
      if (result != null) return result;
    }
    // TDLib defines an unmatched privacy action as not allowed.
    return false;
  }

  if (isAllowed(isContact: false)) return PrivacyVisibilityOption.everyone;
  if (isAllowed(isContact: true)) return PrivacyVisibilityOption.contacts;
  return PrivacyVisibilityOption.nobody;
}
