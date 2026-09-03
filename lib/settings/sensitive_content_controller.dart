import 'dart:async';

import 'package:flutter/foundation.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';

typedef SensitiveContentQuery =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);
typedef SensitiveContentQueryForClient =
    Future<Map<String, dynamic>> Function(
      Map<String, dynamic> request,
      int clientId,
    );

class SensitiveContentController extends ChangeNotifier {
  SensitiveContentController._({
    SensitiveContentQuery? query,
    SensitiveContentQueryForClient? queryForClient,
    int Function()? activeClientId,
    Stream<int>? activeSlotChanges,
    Stream<Map<String, dynamic>>? allUpdates,
  }) : _queryForClient =
           queryForClient ??
           (query == null
               ? TdClient.shared.queryTo
               : (request, _) => query(request)),
       _activeClientId =
           activeClientId ?? (() => TdClient.shared.activeClientId),
       _activeSlotChanges =
           activeSlotChanges ?? TdClient.shared.subscribeActiveSlotChanges(),
       _allUpdates = allUpdates ?? TdClient.shared.subscribeAll();

  @visibleForTesting
  factory SensitiveContentController.forTesting({
    required SensitiveContentQuery query,
    int Function()? activeClientId,
    Stream<int> activeSlotChanges = const Stream<int>.empty(),
    Stream<Map<String, dynamic>> allUpdates =
        const Stream<Map<String, dynamic>>.empty(),
  }) => SensitiveContentController._(
    query: query,
    activeClientId: activeClientId ?? (() => 1),
    activeSlotChanges: activeSlotChanges,
    allUpdates: allUpdates,
  );

  static final SensitiveContentController shared =
      SensitiveContentController._();

  static const canIgnoreOption = 'can_ignore_sensitive_content_restrictions';
  static const ignoreOption = 'ignore_sensitive_content_restrictions';

  final SensitiveContentQueryForClient _queryForClient;
  final int Function() _activeClientId;
  final Stream<int> _activeSlotChanges;
  final Stream<Map<String, dynamic>> _allUpdates;

  bool _initialized = false;
  bool _loading = false;
  bool _canIgnore = false;
  bool _enabled = false;
  int _accountGeneration = 0;
  int _refreshGeneration = 0;
  int _setGeneration = 0;
  StreamSubscription<int>? _slotSub;
  StreamSubscription<Map<String, dynamic>>? _authSub;

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
    _slotSub = _activeSlotChanges.listen((_) => _accountChanged());
    _authSub = _allUpdates.listen((update) {
      if (update.type != 'updateAuthorizationState' ||
          update.obj('authorization_state')?.type !=
              'authorizationStateReady' ||
          update.integer('@client_id') != _activeClientId()) {
        return;
      }
      unawaited(refresh());
    });
    await refresh();
  }

  void _accountChanged() {
    _accountGeneration += 1;
    _setGeneration += 1;
    _loading = false;
    _canIgnore = false;
    _enabled = false;
    notifyListeners();
    unawaited(refresh());
  }

  Future<void> refresh() async {
    final accountGeneration = _accountGeneration;
    final refreshGeneration = ++_refreshGeneration;
    final clientId = _activeClientId();
    _loading = true;
    notifyListeners();
    if (clientId == 0) {
      if (accountGeneration == _accountGeneration &&
          refreshGeneration == _refreshGeneration) {
        _loading = false;
        notifyListeners();
      }
      return;
    }
    final values = await Future.wait<bool?>([
      _optionBool(canIgnoreOption, clientId),
      _optionBool(ignoreOption, clientId),
    ]);
    if (accountGeneration != _accountGeneration ||
        refreshGeneration != _refreshGeneration ||
        clientId != _activeClientId()) {
      return;
    }
    final canIgnore = values[0];
    final enabled = values[1];
    _canIgnore = canIgnore ?? _canIgnore;
    _enabled = enabled ?? _enabled;
    _loading = false;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    final accountGeneration = _accountGeneration;
    final setGeneration = ++_setGeneration;
    final clientId = _activeClientId();
    if (clientId == 0) {
      throw StateError('TDLib client is not active yet');
    }
    await _queryForClient({
      '@type': 'setOption',
      'name': ignoreOption,
      'value': {'@type': 'optionValueBoolean', 'value': value},
    }, clientId);
    if (accountGeneration != _accountGeneration ||
        setGeneration != _setGeneration ||
        clientId != _activeClientId()) {
      return;
    }
    _enabled = value;
    if (value) _canIgnore = true;
    notifyListeners();
  }

  Future<bool?> _optionBool(String name, int clientId) async {
    try {
      final option = await _queryForClient({
        '@type': 'getOption',
        'name': name,
      }, clientId);
      return option.boolean('value');
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    unawaited(_slotSub?.cancel());
    unawaited(_authSub?.cancel());
    super.dispose();
  }
}
