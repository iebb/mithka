import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
        await hotKeyManager.register(
          hotKey,
          keyDownHandler: (_) => onPressed(entry.key),
        );
        _registered[entry.key] = hotKey;
      } on Object {
        // Reserved or unavailable OS shortcuts stay functional while Mithka is
        // focused through CallbackShortcuts below.
      }
    }
  }

  Future<void> _unregisterCurrent() async {
    final current = _registered.values.toList(growable: false);
    _registered.clear();
    for (final hotKey in current) {
      try {
        await hotKeyManager.unregister(hotKey);
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

/// Installs system-wide and focused-window shortcuts only for actions that
/// currently have a live handler.
///
/// This keeps a configurable shortcut from swallowing an ordinary platform or
/// text-editing command while its destination is not mounted.
class DesktopHotkeyHost extends StatefulWidget {
  const DesktopHotkeyHost({
    super.key,
    required this.controller,
    required this.child,
    this.registry,
    this.systemBackend,
  });

  final DesktopHotkeyController controller;
  final DesktopHotkeyRegistry? registry;
  final DesktopSystemHotkeyBackend? systemBackend;
  final Widget child;

  @override
  State<DesktopHotkeyHost> createState() => _DesktopHotkeyHostState();
}

class _DesktopHotkeyHostState extends State<DesktopHotkeyHost> {
  late DesktopSystemHotkeyBackend _systemBackend;
  Future<void> _systemSync = Future<void>.value();

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
      unawaited(_systemBackend.dispose());
      _systemBackend =
          widget.systemBackend ?? PluginDesktopSystemHotkeyBackend();
    }
    if (controllerChanged || registryChanged || backendChanged) {
      _scheduleSystemSync();
    }
  }

  void _scheduleSystemSync() {
    _systemSync = _systemSync
        .then((_) async {
          if (!mounted) return;
          final bindings = <DesktopHotkeyAction, DesktopHotkeyGesture>{};
          if (widget.controller.available) {
            for (final action in DesktopHotkeyAction.values) {
              if (_registry.hasHandler(action)) {
                bindings[action] = widget.controller.bindingFor(action);
              }
            }
          }
          await _systemBackend.replaceAll(bindings, _invokeSystemHotkey);
        })
        .catchError((Object _) {
          // Native registration failures retain the focused-window fallback.
        });
  }

  void _invokeSystemHotkey(DesktopHotkeyAction action) {
    if (mounted) _registry.invoke(action);
  }

  @override
  void dispose() {
    _detachSources();
    unawaited(_systemBackend.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actions = _registry;
    if (!widget.controller.available) return widget.child;
    return AnimatedBuilder(
      animation: Listenable.merge([widget.controller, actions]),
      child: widget.child,
      builder: (context, child) {
        final bindings = <ShortcutActivator, VoidCallback>{};
        for (final action in DesktopHotkeyAction.values) {
          if (!actions.hasHandler(action)) continue;
          bindings[widget.controller.bindingFor(action).activator] = () =>
              actions.invoke(action);
        }
        return CallbackShortcuts(bindings: bindings, child: child!);
      },
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
