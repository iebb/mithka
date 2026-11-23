//
//  desktop_child_window_startup_test.dart
//
//  On Linux a child window is created hidden, and the window manager lists a
//  hidden window as "not active" — the same answer it gives for a window the
//  user closed. The primary engine drops a registration that is not active, so
//  it dropped every Linux child before the child could subscribe to its TDLib
//  transport: Settings, Saved Messages and Files opened as blank windows.
//
//  The window plugin below is a stand-in that answers the way the Linux one
//  does, so the real primary bridge runs against the real event order.
//

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/desktop_child_window_startup.dart';
import 'package:mithka/app/desktop_utility_window_io.dart';
import 'package:mithka/app/desktop_utility_window_models.dart';
import 'package:mithka/tdlib/td_bindings.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:multi_window_manager/multi_window_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _codec = StandardMethodCodec();
const _primaryChannel = 'multi_window_manager_0';
const _subscribe = 'mithka.utility.td.subscribe';

/// Answers the window plugin's channels the way its Linux implementation does.
///
/// A created child is registered hidden and announces itself with
/// `initialized`. It only counts as active once `show` has been called, and
/// closing it hides it again (`reuse-close`) instead of destroying it.
class _LinuxWindowPlugin {
  /// Registered children, and whether each one is on screen.
  final Map<int, bool> visible = {};
  int _lastId = 0;

  TestDefaultBinaryMessenger get _messenger =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void install() {
    _messenger
      ..setMockMethodCallHandler(
        const MethodChannel('multi_window_manager'),
        (_) async => true,
      )
      ..setMockMethodCallHandler(
        const MethodChannel('multi_window_manager_static'),
        _static,
      )
      ..setMockMethodCallHandler(const MethodChannel(_primaryChannel), _window)
      ..setMockMethodCallHandler(
        const MethodChannel('multi_window_manager/screen_retriever'),
        _screen,
      );
  }

  Future<Object?> _static(MethodCall call) async {
    switch (call.method) {
      case 'createWindow':
        final id = ++_lastId;
        // The child engine boots, then registers itself while still hidden.
        Timer(const Duration(milliseconds: 20), () {
          visible[id] = false;
          emit('initialized', id);
        });
        return id;
      case 'getActiveWindowIds':
        return [
          0,
          for (final entry in visible.entries)
            if (entry.value) entry.key,
        ];
      case 'getHiddenWindowIds':
        return [
          for (final entry in visible.entries)
            if (!entry.value) entry.key,
        ];
    }
    return null;
  }

  Future<Object?> _window(MethodCall call) async {
    final arguments = call.arguments;
    final target = arguments is Map ? arguments['windowId'] as int? : null;
    switch (call.method) {
      case 'show':
        if (target != null && visible[target] == false) {
          visible[target] = true;
          emit('show', target);
          emit('reuse-show', target);
        }
        return true;
      case 'getBounds':
        return {'x': 0.0, 'y': 0.0, 'width': 800.0, 'height': 600.0};
    }
    return call.method.startsWith('is') ? false : true;
  }

  Future<Object?> _screen(MethodCall call) async {
    const display = {
      'id': 'primary',
      'size': {'width': 1920, 'height': 1080},
      'visiblePosition': {'dx': 0, 'dy': 0},
      'visibleSize': {'width': 1920, 'height': 1080},
    };
    return switch (call.method) {
      'getPrimaryDisplay' => display,
      'getAllDisplays' => {
        'displays': [display],
      },
      'getCursorScreenPoint' => {'dx': 10, 'dy': 10},
      _ => null,
    };
  }

  /// The user closes a shown child: Linux hides it and keeps its engine.
  void closeByUser(int windowId) {
    visible[windowId] = false;
    emit('reuse-close', windowId);
  }

  /// A lifecycle event every engine in the process receives.
  void emit(String eventName, int windowId) {
    unawaited(
      _messenger.handlePlatformMessage(
        _primaryChannel,
        _codec.encodeMethodCall(
          MethodCall('onEvent', {'eventName': eventName, 'windowId': windowId}),
        ),
        (_) {},
      ),
    );
  }

  /// What the primary answers when child [windowId] invokes [method] on it.
  Future<Object?> callPrimary(
    int windowId,
    String method,
    Object? arguments,
  ) async {
    final reply = Completer<ByteData?>();
    await _messenger.handlePlatformMessage(
      _primaryChannel,
      _codec.encodeMethodCall(
        MethodCall('onEvent', {
          'fromWindowId': windowId,
          'eventName': kEventFromWindow,
          'method': method,
          'arguments': arguments,
        }),
      ),
      reply.complete,
    );
    final data = await reply.future;
    return data == null ? null : _codec.decodeEnvelope(data);
  }
}

class _FakeBindings implements TdBindings {
  int _nextClientId = 100;

  @override
  int createClientId() => _nextClientId++;

  @override
  void send(int clientId, String request) {
    jsonDecode(request);
  }

  @override
  void importSessionString(String sessionString, String destinationPath) {
    File(destinationPath).writeAsBytesSync(Uint8List.fromList(const [1]));
  }

  @override
  bool get supportsSessionStringBackup => false;

  @override
  bool get supportsTransferBoost => false;

  @override
  String? receive(double timeout) => throw UnimplementedError();

  @override
  Object? receiveJson(double timeout) => throw UnimplementedError();

  @override
  String? execute(String request) => throw UnimplementedError();

  @override
  String exportSessionString(
    String sourcePath, {
    required int apiId,
    required bool testMode,
    required int userId,
  }) => throw UnimplementedError();

  @override
  void configureTransferBoost({
    required int downloadChunkSize,
    required int downloadParallelism,
    required int uploadChunkSize,
    required int uploadParallelism,
  }) {}
}

void main() {
  group('DesktopChildWindowStartup', () {
    test('a window that was never shown stays alive', () {
      final startup = DesktopChildWindowStartup()..begin(7);
      expect(startup.live([0]), {0, 7});
      expect(startup.live([0]), {0, 7}, reason: 'still not shown');
    });

    test('once shown, leaving the active list means closed', () {
      final startup = DesktopChildWindowStartup()..begin(7);
      expect(startup.live([0, 7]), {0, 7});
      expect(startup.live([0]), {0});
    });

    test('a window that failed or closed during startup is forgotten', () {
      final startup = DesktopChildWindowStartup()
        ..begin(7)
        ..begin(8)
        ..end(7);
      expect(startup.live([0]), {0, 8});
      startup.clear();
      expect(startup.live([0]), {0});
    });
  });

  group('a utility window created hidden, as on Linux', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    late Directory supportDir;
    late int slot;
    final plugin = _LinuxWindowPlugin();

    DesktopUtilityWindowArguments utility(DesktopUtilityWindowKind kind) =>
        DesktopUtilityWindowArguments(
          kind: kind,
          accountSlot: slot,
          accountUserId: 1,
          title: 'Utility',
          localeTag: 'en',
          dark: false,
        );

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 60));

    setUpAll(() async {
      supportDir = await Directory.systemTemp.createTemp('mithka-child-window');
      SharedPreferences.setMockInitialValues({});
      TdClient.shared.prepareForTesting(
        prefs: await SharedPreferences.getInstance(),
        supportDir: supportDir.path,
        bindings: _FakeBindings(),
        queryOverride: (_, _) async => {'@type': 'ok'},
      );
      slot = TdClient.shared.addSlot();
      TdClient.shared.setActive(slot);
      plugin.install();
      await MultiWindowManager.ensureInitialized(0);
    });
    tearDownAll(() async {
      detachDesktopUtilityMainProxy();
      await TdClient.shared.closeProxy();
      await supportDir.delete(recursive: true);
    });

    test(
      'the child can subscribe, and closing it ends its transport',
      () async {
        final settings = utility(DesktopUtilityWindowKind.settings);
        expect(await openDesktopUtilityWindow(settings), isTrue);
        await settle();
        final windowId = plugin.visible.keys.single;
        expect(plugin.visible[windowId], isTrue);

        final answer = await plugin.callPrimary(
          windowId,
          _subscribe,
          settings.toIpcJson(),
        );
        expect(
          answer,
          isA<Map>().having((map) => map['ok'], 'ok', true),
          reason: 'the primary must still know the window it just created',
        );

        plugin.closeByUser(windowId);
        await settle();
        expect(
          await plugin.callPrimary(windowId, _subscribe, settings.toIpcJson()),
          isNull,
          reason: 'a closed window no longer reaches the account',
        );
      },
    );

    test('a child is answered before it has been shown', () async {
      final files = utility(DesktopUtilityWindowKind.files);
      // The child engine is up but nothing has shown its window yet.
      const hiddenId = 500;
      plugin.visible[hiddenId] = false;
      addTearDown(() => plugin.visible.remove(hiddenId));

      final opening = openDesktopUtilityWindow(files);
      await settle();
      expect(await opening, isTrue);
      final windowId = plugin.visible.keys.lastWhere((id) => id != hiddenId);

      // Another window's lifecycle event refreshes the active list while the
      // unrelated child above is still hidden; it must not disturb this one.
      plugin.emit('initialized', hiddenId);
      await settle();
      expect(
        await plugin.callPrimary(windowId, _subscribe, files.toIpcJson()),
        isA<Map>().having((map) => map['ok'], 'ok', true),
      );
    });
  });
}
