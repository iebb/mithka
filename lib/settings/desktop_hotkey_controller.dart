import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/adaptive_platform.dart';

enum DesktopHotkeyAction { openSettings, newChat, focusSearch, screenshot }

@immutable
class DesktopHotkeyGesture {
  const DesktopHotkeyGesture({
    required this.key,
    this.control = false,
    this.alt = false,
    this.shift = false,
    this.meta = false,
  });

  final LogicalKeyboardKey key;
  final bool control;
  final bool alt;
  final bool shift;
  final bool meta;

  bool get hasModifier => control || alt || shift || meta;

  SingleActivator get activator => SingleActivator(
    key,
    control: control,
    alt: alt,
    shift: shift,
    meta: meta,
    includeRepeats: false,
  );

  Map<String, Object> toJson() => {
    'keyId': key.keyId,
    'control': control,
    'alt': alt,
    'shift': shift,
    'meta': meta,
  };

  static DesktopHotkeyGesture? tryParse(Object? value) {
    if (value is! Map) return null;
    final keyId = value['keyId'];
    if (keyId is! int || keyId <= 0) return null;
    return DesktopHotkeyGesture(
      key: LogicalKeyboardKey(keyId),
      control: value['control'] == true,
      alt: value['alt'] == true,
      shift: value['shift'] == true,
      meta: value['meta'] == true,
    );
  }

  String label({required TargetPlatform platform}) {
    final keyLabel = desktopHotkeyKeyLabel(key);
    if (platform == TargetPlatform.macOS) {
      final buffer = StringBuffer();
      if (control) buffer.write('⌃');
      if (alt) buffer.write('⌥');
      if (shift) buffer.write('⇧');
      if (meta) buffer.write('⌘');
      buffer.write(keyLabel);
      return buffer.toString();
    }
    return [
      if (control) 'Ctrl',
      if (alt) 'Alt',
      if (shift) 'Shift',
      if (meta) 'Meta',
      keyLabel,
    ].join(' + ');
  }

  @override
  bool operator ==(Object other) =>
      other is DesktopHotkeyGesture &&
      other.key.keyId == key.keyId &&
      other.control == control &&
      other.alt == alt &&
      other.shift == shift &&
      other.meta == meta;

  @override
  int get hashCode => Object.hash(key.keyId, control, alt, shift, meta);
}

String desktopHotkeyKeyLabel(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.comma) return ',';
  if (key == LogicalKeyboardKey.period) return '.';
  if (key == LogicalKeyboardKey.slash) return '/';
  if (key == LogicalKeyboardKey.semicolon) return ';';
  if (key == LogicalKeyboardKey.quote) return "'";
  if (key == LogicalKeyboardKey.bracketLeft) return '[';
  if (key == LogicalKeyboardKey.bracketRight) return ']';
  if (key == LogicalKeyboardKey.backslash) return '\\';
  if (key == LogicalKeyboardKey.minus) return '-';
  if (key == LogicalKeyboardKey.equal) return '=';
  if (key == LogicalKeyboardKey.space) return 'Space';
  if (key == LogicalKeyboardKey.tab) return 'Tab';
  if (key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter) {
    return 'Enter';
  }
  if (key == LogicalKeyboardKey.backspace) return 'Backspace';
  if (key == LogicalKeyboardKey.delete) return 'Delete';
  if (key == LogicalKeyboardKey.arrowUp) return '↑';
  if (key == LogicalKeyboardKey.arrowDown) return '↓';
  if (key == LogicalKeyboardKey.arrowLeft) return '←';
  if (key == LogicalKeyboardKey.arrowRight) return '→';
  final label = key.keyLabel.trim();
  return label.isEmpty ? 'Key ${key.keyId}' : label.toUpperCase();
}

bool isDesktopHotkeyModifier(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.controlLeft ||
    key == LogicalKeyboardKey.controlRight ||
    key == LogicalKeyboardKey.altLeft ||
    key == LogicalKeyboardKey.altRight ||
    key == LogicalKeyboardKey.shiftLeft ||
    key == LogicalKeyboardKey.shiftRight ||
    key == LogicalKeyboardKey.metaLeft ||
    key == LogicalKeyboardKey.metaRight;

bool desktopHotkeyCanBeAssigned(DesktopHotkeyGesture gesture) {
  if (isDesktopHotkeyModifier(gesture.key) ||
      gesture.key == LogicalKeyboardKey.escape) {
    return false;
  }
  if (gesture.hasModifier) return true;
  return _desktopFunctionKeys.contains(gesture.key);
}

final Set<LogicalKeyboardKey> _desktopFunctionKeys = {
  LogicalKeyboardKey.f1,
  LogicalKeyboardKey.f2,
  LogicalKeyboardKey.f3,
  LogicalKeyboardKey.f4,
  LogicalKeyboardKey.f5,
  LogicalKeyboardKey.f6,
  LogicalKeyboardKey.f7,
  LogicalKeyboardKey.f8,
  LogicalKeyboardKey.f9,
  LogicalKeyboardKey.f10,
  LogicalKeyboardKey.f11,
  LogicalKeyboardKey.f12,
};

enum DesktopHotkeyAssignmentResult { assigned, duplicate, invalid }

class DesktopHotkeyController extends ChangeNotifier {
  DesktopHotkeyController(this._prefs, {TargetPlatform? platform})
    : platform = platform ?? defaultTargetPlatform {
    _load();
  }

  static const _storageKey = 'mithka.desktopHotkeys.v1';
  static DesktopHotkeyController? _shared;

  static DesktopHotkeyController initializeShared(
    SharedPreferences prefs, {
    bool replace = false,
    TargetPlatform? platform,
  }) {
    if (_shared == null || replace) {
      _shared = DesktopHotkeyController(prefs, platform: platform);
    }
    return _shared!;
  }

  static DesktopHotkeyController? get maybeShared => _shared;

  static DesktopHotkeyController get shared {
    final value = _shared;
    if (value == null) {
      throw StateError('DesktopHotkeyController has not been initialized.');
    }
    return value;
  }

  final SharedPreferences _prefs;
  final TargetPlatform platform;
  final Map<DesktopHotkeyAction, DesktopHotkeyGesture> _bindings = {};

  bool get available => !kIsWeb && isDesktopTargetPlatform(platform);

  DesktopHotkeyGesture bindingFor(DesktopHotkeyAction action) =>
      _bindings[action] ?? _defaultFor(action);

  DesktopHotkeyAssignmentResult assign(
    DesktopHotkeyAction action,
    DesktopHotkeyGesture gesture,
  ) {
    if (!desktopHotkeyCanBeAssigned(gesture)) {
      return DesktopHotkeyAssignmentResult.invalid;
    }
    for (final entry in _bindings.entries) {
      if (entry.key != action && entry.value == gesture) {
        return DesktopHotkeyAssignmentResult.duplicate;
      }
    }
    if (_bindings[action] == gesture) {
      return DesktopHotkeyAssignmentResult.assigned;
    }
    _bindings[action] = gesture;
    unawaited(_persist());
    notifyListeners();
    return DesktopHotkeyAssignmentResult.assigned;
  }

  void resetDefaults() {
    _bindings
      ..clear()
      ..addEntries(
        DesktopHotkeyAction.values.map(
          (action) => MapEntry(action, _defaultFor(action)),
        ),
      );
    unawaited(_persist());
    notifyListeners();
  }

  Future<void> reload() async {
    await _prefs.reload();
    _load();
    notifyListeners();
  }

  void _load() {
    _bindings
      ..clear()
      ..addEntries(
        DesktopHotkeyAction.values.map(
          (action) => MapEntry(action, _defaultFor(action)),
        ),
      );
    final encoded = _prefs.getString(_storageKey);
    if (encoded == null || encoded.isEmpty) return;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return;
      for (final action in DesktopHotkeyAction.values) {
        final gesture = DesktopHotkeyGesture.tryParse(decoded[action.name]);
        if (gesture == null || !desktopHotkeyCanBeAssigned(gesture)) continue;
        final duplicated = _bindings.entries.any(
          (entry) => entry.key != action && entry.value == gesture,
        );
        if (!duplicated) _bindings[action] = gesture;
      }
    } on Object {
      // A malformed preference is ignored in favor of complete defaults.
    }
  }

  Future<void> _persist() => _prefs.setString(
    _storageKey,
    jsonEncode({
      for (final action in DesktopHotkeyAction.values)
        action.name: bindingFor(action).toJson(),
    }),
  );

  DesktopHotkeyGesture _defaultFor(DesktopHotkeyAction action) {
    final primaryIsMeta = platform == TargetPlatform.macOS;
    return switch (action) {
      DesktopHotkeyAction.openSettings => DesktopHotkeyGesture(
        key: LogicalKeyboardKey.comma,
        meta: primaryIsMeta,
        control: !primaryIsMeta,
      ),
      DesktopHotkeyAction.newChat => DesktopHotkeyGesture(
        key: LogicalKeyboardKey.keyN,
        meta: primaryIsMeta,
        control: !primaryIsMeta,
      ),
      DesktopHotkeyAction.focusSearch => DesktopHotkeyGesture(
        key: LogicalKeyboardKey.keyF,
        meta: primaryIsMeta,
        control: !primaryIsMeta,
      ),
      DesktopHotkeyAction.screenshot => const DesktopHotkeyGesture(
        key: LogicalKeyboardKey.keyA,
        control: true,
        alt: true,
      ),
    };
  }
}

typedef DesktopHotkeyCallback = FutureOr<void> Function();
typedef DesktopHotkeyEnabled = bool Function();

class DesktopHotkeyRegistration {
  DesktopHotkeyRegistration._(this._registry, this._action, this._identity);

  DesktopHotkeyRegistry? _registry;
  final DesktopHotkeyAction _action;
  final Object _identity;

  void dispose() {
    _registry?._unregister(_action, _identity);
    _registry = null;
  }
}

class DesktopHotkeyRegistry extends ChangeNotifier {
  DesktopHotkeyRegistry();

  static final DesktopHotkeyRegistry instance = DesktopHotkeyRegistry();

  final Map<DesktopHotkeyAction, List<_DesktopHotkeyHandler>> _handlers = {};
  bool _notificationQueued = false;
  bool _disposed = false;

  DesktopHotkeyRegistration register(
    DesktopHotkeyAction action,
    DesktopHotkeyCallback callback, {
    DesktopHotkeyEnabled? isEnabled,
  }) {
    final identity = Object();
    (_handlers[action] ??= []).add(
      _DesktopHotkeyHandler(identity, callback, isEnabled),
    );
    _notifyHandlersChanged();
    return DesktopHotkeyRegistration._(this, action, identity);
  }

  bool hasEnabledHandler(DesktopHotkeyAction action) =>
      _enabledHandler(action) != null;

  bool hasHandler(DesktopHotkeyAction action) =>
      _handlers[action]?.isNotEmpty ?? false;

  bool invoke(DesktopHotkeyAction action) {
    final handler = _enabledHandler(action);
    if (handler == null) return false;
    unawaited(Future<void>.sync(handler.callback));
    return true;
  }

  _DesktopHotkeyHandler? _enabledHandler(DesktopHotkeyAction action) {
    final handlers = _handlers[action];
    if (handlers == null) return null;
    for (final handler in handlers.reversed) {
      if (handler.isEnabled?.call() ?? true) return handler;
    }
    return null;
  }

  void _unregister(DesktopHotkeyAction action, Object identity) {
    final handlers = _handlers[action];
    if (handlers == null) return;
    handlers.removeWhere((handler) => identical(handler.identity, identity));
    if (handlers.isEmpty) _handlers.remove(action);
    _notifyHandlersChanged();
  }

  void _notifyHandlersChanged() {
    if (_disposed || _notificationQueued) return;
    _notificationQueued = true;
    scheduleMicrotask(() {
      _notificationQueued = false;
      if (_disposed) return;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _DesktopHotkeyHandler {
  const _DesktopHotkeyHandler(this.identity, this.callback, this.isEnabled);

  final Object identity;
  final DesktopHotkeyCallback callback;
  final DesktopHotkeyEnabled? isEnabled;
}
