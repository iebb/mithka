import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka_video_player/src/desktop_video_windows.dart';
import 'package:mithka_video_player/src/desktop_video_windows_stub.dart'
    as stub;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('arguments accept legacy payloads and sanitize optional metadata', () {
    final legacy = MithkaDesktopVideoWindowArguments.tryParse(
      '{"type":"mithka.video","uri":"https://example.test/video.mp4",'
      '"title":"  A\\nvideo  ","width":0,"height":720.0,"muted":true}',
    );

    expect(legacy, isNotNull);
    expect(legacy!.title, 'A video');
    expect(legacy.width, isNull);
    expect(legacy.height, 720);
    expect(legacy.muted, isTrue);
    expect(
      MithkaDesktopVideoWindowArguments.tryParse(
        '{"version":2,"type":"mithka.video",'
        '"uri":"https://example.test/video.mp4"}',
      ),
      isNull,
    );
  });

  test('unsupported platforms do not touch desktop method channels', () async {
    final windows = stub.createDesktopWindowsPlatform();
    var closed = 0;

    expect(windows.isSupported, isFalse);
    expect(windows.currentWindowFullscreen.value, isFalse);
    expect(
      await windows.open(
        MithkaDesktopVideoWindowArguments(
          uri: Uri.parse('https://example.test/video.mp4'),
          title: 'Video',
          width: 1920,
          height: 1080,
          muted: false,
        ),
        onClosed: () => closed++,
        timeout: const Duration(seconds: 1),
      ),
      isNull,
    );
    expect(closed, 1);

    await windows.configureCurrentWindow(title: 'Ignored');
    await windows.hideCurrentWindow();
    await windows.closeCurrentWindow();
    expect(await windows.setCurrentWindowFullscreen(true), isFalse);
    await windows.toggleCurrentWindowFullscreen();
  });

  test(
    'concurrent windows initialize, show, and clean up independently',
    () async {
      const bootstrap = MethodChannel('multi_window_manager');
      const staticChannel = MethodChannel('multi_window_manager_static');
      const screen = MethodChannel('multi_window_manager/screen_retriever');
      const window = MethodChannel('multi_window_manager_0');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final windowCalls = <MethodCall>[];
      var nextWindowId = 40;
      final nativeActiveWindowIds = <int>{};

      messenger.setMockMethodCallHandler(bootstrap, (call) async {
        expect(call.method, 'ensureInitialized');
        return true;
      });
      messenger.setMockMethodCallHandler(staticChannel, (call) async {
        switch (call.method) {
          case 'createWindow':
            final id = nextWindowId++;
            nativeActiveWindowIds.add(id);
            Timer.run(
              () => _sendEvent(messenger, window.name, 'initialized', id),
            );
            return id;
          case 'getActiveWindowIds':
            return nativeActiveWindowIds.toList();
          case 'getHiddenWindowIds':
            return <int>[];
        }
        return null;
      });
      messenger.setMockMethodCallHandler(screen, (call) async {
        switch (call.method) {
          case 'getPrimaryDisplay':
            return _display;
          case 'getAllDisplays':
            return {
              'displays': [_display],
            };
          case 'getCursorScreenPoint':
            return {'dx': 600.0, 'dy': 400.0};
        }
        return null;
      });
      messenger.setMockMethodCallHandler(window, (call) async {
        windowCalls.add(call);
        return switch (call.method) {
          'isFullScreen' => false,
          'getBounds' => {'x': 0.0, 'y': 0.0, 'width': 880.0, 'height': 495.0},
          _ => true,
        };
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(bootstrap, null);
        messenger.setMockMethodCallHandler(staticChannel, null);
        messenger.setMockMethodCallHandler(screen, null);
        messenger.setMockMethodCallHandler(window, null);
      });

      expect(await MithkaDesktopVideoWindows.initialize(const []), isNull);
      var firstClosed = 0;
      var secondClosed = 0;
      final ids = await Future.wait([
        MithkaDesktopVideoWindows.instance.open(
          _arguments('First'),
          onClosed: () => firstClosed++,
        ),
        MithkaDesktopVideoWindows.instance.open(
          _arguments('Second'),
          onClosed: () => secondClosed++,
        ),
      ]);

      expect(ids, [40, 41]);
      expect(MithkaDesktopVideoWindows.instance.activeWindowIds, {40, 41});
      final hostConfiguresWindows = !Platform.isLinux;
      expect(
        windowCalls.where((call) => call.method == 'show'),
        hasLength(hostConfiguresWindows ? 2 : 0),
      );
      expect(
        windowCalls.where((call) => call.method == 'setMinimumSize'),
        hasLength(hostConfiguresWindows ? 2 : 0),
      );

      // Reuse-close is intentionally not forwarded to public global window
      // listeners. The public active-window registry must still release the
      // hidden window's retained URI/stream callback.
      nativeActiveWindowIds.remove(40);
      await _sendEvent(messenger, window.name, 'reuse-close', 40);
      await _flushMicrotasks();
      expect(firstClosed, 1);
      expect(secondClosed, 0);
      expect(MithkaDesktopVideoWindows.instance.activeWindowIds, {41});
      expect(windowCalls.where((call) => call.method == 'destroy'), isEmpty);

      nativeActiveWindowIds.remove(41);
      await _sendEvent(messenger, window.name, 'close', 41);
      await _flushMicrotasks();
      expect(firstClosed, 1);
      expect(secondClosed, 1);
      expect(MithkaDesktopVideoWindows.instance.activeWindowIds, isEmpty);
    },
  );

  test(
    'startup timeout releases resources exactly once after late events',
    () async {
      const staticChannel = MethodChannel('multi_window_manager_static');
      const window = MethodChannel('multi_window_manager_0');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final windowCalls = <MethodCall>[];
      MithkaDesktopVideoWindows.instance.onError = (_, _) {};
      addTearDown(() => MithkaDesktopVideoWindows.instance.onError = null);

      messenger.setMockMethodCallHandler(staticChannel, (call) async {
        return switch (call.method) {
          'createWindow' => 70,
          'getActiveWindowIds' || 'getHiddenWindowIds' => <int>[],
          _ => null,
        };
      });
      messenger.setMockMethodCallHandler(window, (call) async {
        windowCalls.add(call);
        return true;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(staticChannel, null);
        messenger.setMockMethodCallHandler(window, null);
      });

      var closed = 0;
      final id = await MithkaDesktopVideoWindows.instance.open(
        _arguments('Times out'),
        onClosed: () => closed++,
        timeout: const Duration(milliseconds: 5),
      );
      expect(id, isNull);
      expect(closed, 1);

      // The upstream typed API does not expose an ID until initialization.
      // Completing it late releases the orphan window, but must not call the
      // already-released host resource again.
      await _sendEvent(messenger, window.name, 'initialized', 70);
      await _flushMicrotasks();
      final releaseMethod = Platform.isLinux ? 'close' : 'destroy';
      expect(
        windowCalls.where((call) => call.method == releaseMethod),
        hasLength(1),
      );
      await _sendEvent(messenger, window.name, 'close', 70);
      await _flushMicrotasks();
      expect(closed, 1);
      expect(MithkaDesktopVideoWindows.instance.activeWindowIds, isEmpty);
    },
  );
}

const _display = <String, Object>{
  'id': 'display-1',
  'size': {'width': 1440.0, 'height': 900.0},
  'visiblePosition': {'dx': 0.0, 'dy': 0.0},
  'visibleSize': {'width': 1440.0, 'height': 860.0},
};

MithkaDesktopVideoWindowArguments _arguments(String title) =>
    MithkaDesktopVideoWindowArguments(
      uri: Uri.parse('https://example.test/video.mp4'),
      title: title,
      width: 1920,
      height: 1080,
      muted: false,
    );

Future<void> _sendEvent(
  TestDefaultBinaryMessenger messenger,
  String channel,
  String eventName,
  int windowId,
) async {
  final response = Completer<void>();
  await messenger.handlePlatformMessage(
    channel,
    const StandardMethodCodec().encodeMethodCall(
      MethodCall('onEvent', {'eventName': eventName, 'windowId': windowId}),
    ),
    (ByteData? _) => response.complete(),
  );
  await response.future;
}

Future<void> _flushMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
