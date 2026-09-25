import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:provider/provider.dart';

import '../auth/account_store.dart';
import '../l10n/app_localizations.dart';
import '../settings/desktop_hotkey_controller.dart';
import 'desktop_utility_window.dart';

/// Replaceable boundary around the native system-wide hotkey plugin.
///
/// The boundary keeps widget tests deterministic and lets the focused Flutter
/// shortcut layer remain available if the OS rejects a reserved combination.
abstract class DesktopSystemHotkeyBackend {
  Future<void> replaceAll(
    Map<DesktopHotkeyAction, DesktopHotkeyGesture> bindings,
    ValueChanged<DesktopHotkeyAction> onPressed,
  );

  Future<void> dispose();
}

class PluginDesktopSystemHotkeyBackend implements DesktopSystemHotkeyBackend {
  PluginDesktopSystemHotkeyBackend({HotKeyManager? manager})
    : _manager = manager ?? hotKeyManager;

  final HotKeyManager _manager;
  final Map<DesktopHotkeyAction, HotKey> _registered = {};
  bool _disposed = false;

  @override
  Future<void> replaceAll(
    Map<DesktopHotkeyAction, DesktopHotkeyGesture> bindings,
    ValueChanged<DesktopHotkeyAction> onPressed,
  ) async {
    await _unregisterCurrent();
    if (_disposed) return;
    for (final entry in bindings.entries) {
      final hotKey = HotKey(
        identifier: 'mithka.${entry.key.name}',
        key: entry.value.key,
        modifiers: [
          if (entry.value.control) HotKeyModifier.control,
          if (entry.value.alt) HotKeyModifier.alt,
          if (entry.value.shift) HotKeyModifier.shift,
          if (entry.value.meta) HotKeyModifier.meta,
        ],
      );
      try {
        await _manager.register(
          hotKey,
          keyDownHandler: (_) {
            if (!_disposed) onPressed(entry.key);
          },
        );
        if (_disposed) {
          await _manager.unregister(hotKey);
          return;
        }
        _registered[entry.key] = hotKey;
      } on Object {
        // Reserved or unavailable OS shortcuts stay functional while Mithka is
        // focused through the shortcut handler below.
      }
    }
  }

  Future<void> _unregisterCurrent() async {
    final current = _registered.values.toList(growable: false);
    _registered.clear();
    for (final hotKey in current) {
      try {
        await _manager.unregister(hotKey);
      } on Object {
        // A disappearing native window can invalidate a registration before
        // Dart receives its disposal callback.
      }
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _unregisterCurrent();
  }
}

/// Installs focused-window shortcuts for actions with a live handler. Only
/// screenshot capture also registers a system-wide hotkey.
///
/// Search, new chat, and settings are ordinary application commands and must
/// never swallow another application's keyboard shortcuts.
class DesktopHotkeyHost extends StatefulWidget {
  const DesktopHotkeyHost({
    super.key,
    required this.controller,
    required this.child,
    this.registry,
    this.systemBackend,
    this.enabled = true,
  });

  final DesktopHotkeyController controller;
  final DesktopHotkeyRegistry? registry;
  final DesktopSystemHotkeyBackend? systemBackend;
  final bool enabled;
  final Widget child;

  @override
  State<DesktopHotkeyHost> createState() => _DesktopHotkeyHostState();
}

class _DesktopHotkeyHostState extends State<DesktopHotkeyHost> {
  late DesktopSystemHotkeyBackend _systemBackend;
  Future<void> _systemSync = Future<void>.value();
  Map<DesktopHotkeyAction, DesktopHotkeyGesture>? _systemBindings;

  DesktopHotkeyRegistry get _registry =>
      widget.registry ?? DesktopHotkeyRegistry.instance;

  @override
  void initState() {
    super.initState();
    _systemBackend = widget.systemBackend ?? PluginDesktopSystemHotkeyBackend();
    _attachSources();
    _scheduleSystemSync();
  }

  void _attachSources() {
    widget.controller.addListener(_scheduleSystemSync);
    _registry.addListener(_scheduleSystemSync);
  }

  void _detachSources() {
    widget.controller.removeListener(_scheduleSystemSync);
    _registry.removeListener(_scheduleSystemSync);
  }

  @override
  void didUpdateWidget(DesktopHotkeyHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controllerChanged = oldWidget.controller != widget.controller;
    final registryChanged = oldWidget.registry != widget.registry;
    final backendChanged = oldWidget.systemBackend != widget.systemBackend;
    if (controllerChanged || registryChanged) {
      final oldRegistry = oldWidget.registry ?? DesktopHotkeyRegistry.instance;
      oldWidget.controller.removeListener(_scheduleSystemSync);
      oldRegistry.removeListener(_scheduleSystemSync);
      _attachSources();
    }
    if (backendChanged) {
      final previousBackend = _systemBackend;
      _systemSync = _systemSync.then((_) => previousBackend.dispose());
      _systemBackend =
          widget.systemBackend ?? PluginDesktopSystemHotkeyBackend();
      _systemBindings = null;
    }
    if (controllerChanged ||
        registryChanged ||
        backendChanged ||
        oldWidget.enabled != widget.enabled) {
      _scheduleSystemSync();
    }
  }

  void _scheduleSystemSync() {
    final backend = _systemBackend;
    _systemSync = _systemSync
        .then((_) async {
          if (!mounted || !identical(backend, _systemBackend)) return;
          final bindings = <DesktopHotkeyAction, DesktopHotkeyGesture>{};
          if (widget.enabled &&
              widget.controller.available &&
              !widget.controller.isRecording &&
              _registry.hasEnabledHandler(DesktopHotkeyAction.screenshot)) {
            bindings[DesktopHotkeyAction.screenshot] = widget.controller
                .bindingFor(DesktopHotkeyAction.screenshot);
          }
          if (!mapEquals(_systemBindings, bindings)) {
            await backend.replaceAll(bindings, _invokeSystemHotkey);
            if (identical(backend, _systemBackend)) _systemBindings = bindings;
          }
        })
        .catchError((Object _) {
          // Native registration failures retain the focused-window fallback.
        });
  }

  void _invokeSystemHotkey(DesktopHotkeyAction action) {
    if (mounted && widget.enabled && !widget.controller.isRecording) {
      _registry.invoke(action);
    }
  }

  @override
  void dispose() {
    _detachSources();
    unawaited(_systemBackend.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (_, event) {
        if (!widget.enabled ||
            !widget.controller.available ||
            widget.controller.isRecording) {
          return KeyEventResult.ignored;
        }
        for (final action in DesktopHotkeyAction.values) {
          if (widget.controller
                  .bindingFor(action)
                  .activator
                  .accepts(event, HardwareKeyboard.instance) &&
              _registry.invoke(action)) {
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: widget.child,
    );
  }
}

/// Registers primary-window actions that do not depend on a selected tab.
/// Chat-list and composer surfaces register their own focus-sensitive actions.
class DesktopPrimaryHotkeyBindings extends StatefulWidget {
  const DesktopPrimaryHotkeyBindings({
    super.key,
    required this.controller,
    required this.child,
    this.registry,
  });

  final DesktopHotkeyController controller;
  final Widget child;
  final DesktopHotkeyRegistry? registry;

  @override
  State<DesktopPrimaryHotkeyBindings> createState() =>
      _DesktopPrimaryHotkeyBindingsState();
}

class _DesktopPrimaryHotkeyBindingsState
    extends State<DesktopPrimaryHotkeyBindings> {
  DesktopHotkeyRegistration? _settingsRegistration;

  DesktopHotkeyRegistry get _registry =>
      widget.registry ?? DesktopHotkeyRegistry.instance;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && widget.controller.available) {
      _registerActions();
    }
  }

  void _registerActions() {
    _settingsRegistration = _registry.register(
      DesktopHotkeyAction.openSettings,
      _openSettings,
    );
  }

  @override
  void didUpdateWidget(DesktopPrimaryHotkeyBindings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.registry == widget.registry) return;
    _settingsRegistration?.dispose();
    _registerActions();
  }

  @override
  void dispose() {
    _settingsRegistration?.dispose();
    super.dispose();
  }

  Future<void> _openSettings() async {
    if (!mounted) return;
    final accounts = context.read<AccountStore>();
    await DesktopUtilityWindowService.instance.open(
      DesktopUtilityWindowArguments(
        kind: DesktopUtilityWindowKind.settings,
        accountSlot: accounts.activeSlot,
        accountUserId: accounts.activeUserId,
        title: AppStrings.t(AppStringKeys.profileSettings),
        localeTag: Localizations.localeOf(context).toLanguageTag(),
        dark: Theme.of(context).brightness == Brightness.dark,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
