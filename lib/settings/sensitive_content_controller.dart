import 'dart:async';

import 'package:flutter/foundation.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';

typedef SensitiveContentQuery =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

class SensitiveContentController extends ChangeNotifier {
  SensitiveContentController._({SensitiveContentQuery? query})
    : _query = query ?? TdClient.shared.query;

  @visibleForTesting
  factory SensitiveContentController.forTesting({
    required SensitiveContentQuery query,
  }) => SensitiveContentController._(query: query);

  static final SensitiveContentController shared =
      SensitiveContentController._();

  static const canIgnoreOption = 'can_ignore_sensitive_content_restrictions';
  static const ignoreOption = 'ignore_sensitive_content_restrictions';

  final SensitiveContentQuery _query;

  bool _initialized = false;
  bool _loading = false;
  bool _canIgnore = false;
  bool _enabled = false;

  bool get loading => _loading;
  bool get canIgnore => _canIgnore;
  bool get enabled => _enabled;
  bool get shouldShowToggle {
    if (defaultTargetPlatform == TargetPlatform.iOS) return _enabled;
    return _enabled || _canIgnore;
  }

  Future<void> initialize() async {
    if (_initialized || _loading) return;
    _initialized = true;
    TdClient.shared.subscribeActiveSlotChanges().listen(
      (_) => unawaited(refresh()),
    );
    await refresh();
  }

  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    final canIgnore = await _optionBool(canIgnoreOption);
    final enabled = await _optionBool(ignoreOption);
    _canIgnore = canIgnore ?? _canIgnore;
    _enabled = enabled ?? _enabled;
    _loading = false;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    await _query({
      '@type': 'setOption',
      'name': ignoreOption,
      'value': {'@type': 'optionValueBoolean', 'value': value},
    });
    _enabled = value;
    if (value) _canIgnore = true;
    notifyListeners();
  }

  Future<bool?> _optionBool(String name) async {
    try {
      final option = await _query({'@type': 'getOption', 'name': name});
      return option.boolean('value');
    } catch (_) {
      return null;
    }
  }
}
