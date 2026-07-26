import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka_video_player/mithka_video_player.dart';
import 'package:multi_window_manager/multi_window_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Linux reuse replaces URI content and disposes the old subtree', (
    tester,
  ) async {
    if (!Platform.isLinux) return;

    const bootstrap = MethodChannel('multi_window_manager');
    const window = MethodChannel('multi_window_manager_0');
    const screen = MethodChannel('multi_window_manager/screen_retriever');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(bootstrap, (call) async {
      expect(call.method, 'ensureInitialized');
      return true;
    });
    messenger.setMockMethodCallHandler(window, (call) async {
      return switch (call.method) {
        'isFullScreen' || 'isMaximized' || 'isMinimized' => false,
        'getBounds' => {'x': 0.0, 'y': 0.0, 'width': 880.0, 'height': 495.0},
        _ => null,
      };
    });
    messenger.setMockMethodCallHandler(screen, (call) async {
      return switch (call.method) {
        'getPrimaryDisplay' => _display,
        'getAllDisplays' => {
          'displays': [_display],
        },
        'getCursorScreenPoint' => {'dx': 600.0, 'dy': 400.0},
        _ => null,
      };
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(bootstrap, null);
      messenger.setMockMethodCallHandler(window, null);
      messenger.setMockMethodCallHandler(screen, null);
    });

    final initialized = <Uri>[];
    final disposed = <Uri>[];
    final first = _arguments('first');
    final second = _arguments('second');
    expect(await MithkaDesktopVideoWindows.initialize(const []), isNull);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MithkaDesktopVideoWindowHost(
          initialArguments: first,
          loadingBuilder: (_) => const SizedBox.shrink(),
          builder: (context, arguments) => _LifecycleProbe(
            uri: arguments.uri,
            onInitialized: initialized.add,
            onDisposed: disposed.add,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(initialized, [first.uri]);
    expect(disposed, isEmpty);

    final reusable = tester.state<ReusableWindowState>(
      find.byType(ReusableWindow),
    );
    unawaited(reusable.onShowWindow([second.encode()]));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(initialized, [first.uri, second.uri]);
    expect(disposed, [first.uri]);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(disposed, [first.uri, second.uri]);
  });
}

const _display = <String, Object>{
  'id': 'display-1',
  'size': {'width': 1440.0, 'height': 900.0},
  'visiblePosition': {'dx': 0.0, 'dy': 0.0},
  'visibleSize': {'width': 1440.0, 'height': 860.0},
};

MithkaDesktopVideoWindowArguments _arguments(String id) =>
    MithkaDesktopVideoWindowArguments(
      uri: Uri.parse('https://media.example/$id.mp4'),
      title: '$id video',
      width: 1920,
      height: 1080,
      muted: false,
    );

class _LifecycleProbe extends StatefulWidget {
  const _LifecycleProbe({
    required this.uri,
    required this.onInitialized,
    required this.onDisposed,
  });

  final Uri uri;
  final ValueChanged<Uri> onInitialized;
  final ValueChanged<Uri> onDisposed;

  @override
  State<_LifecycleProbe> createState() => _LifecycleProbeState();
}

class _LifecycleProbeState extends State<_LifecycleProbe> {
  @override
  void initState() {
    super.initState();
    widget.onInitialized(widget.uri);
  }

  @override
  void dispose() {
    widget.onDisposed(widget.uri);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(widget.uri.toString());
}
