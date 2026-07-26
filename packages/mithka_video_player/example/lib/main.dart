import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mithka_video_player/mithka_video_player.dart';

const sampleVideo =
    'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4';

Future<void> main(List<String> arguments) async {
  final child = await MithkaDesktopVideoWindows.initialize(arguments);
  if (child != null) {
    runApp(_ExampleWindow(arguments: child));
    return;
  }
  runApp(const _ExampleApp());
}

class _ExampleApp extends StatelessWidget {
  const _ExampleApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(),
    home: Scaffold(
      backgroundColor: const Color(0xFF111318),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Responsive video player',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Resize the window to see compact and wide controls. '
                    'Keyboard shortcuts work while the player is focused.',
                    style: TextStyle(color: Color(0xFFB6BBC6), fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: MithkaVideoPlayer(
                        source: const MithkaVideoSource.network(sampleVideo),
                        width: 1280,
                        height: 720,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Builder(
                      builder: (context) => TextButton(
                        onPressed: mithkaSupportsDesktopVideoWindows
                            ? () => unawaited(_openWindow(context))
                            : null,
                        child: const Text('Open in an independent window'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  static Future<void> _openWindow(BuildContext context) async {
    await MithkaDesktopVideoWindows.instance.open(
      MithkaDesktopVideoWindowArguments(
        uri: Uri.parse(sampleVideo),
        title: 'Video player example',
        width: 1280,
        height: 720,
        muted: false,
      ),
    );
  }
}

class _ExampleWindow extends StatefulWidget {
  const _ExampleWindow({required this.arguments});

  final MithkaDesktopVideoWindowArguments arguments;

  @override
  State<_ExampleWindow> createState() => _ExampleWindowState();
}

class _ExampleWindowState extends State<_ExampleWindow> {
  @override
  void initState() {
    super.initState();
    unawaited(
      MithkaDesktopVideoWindows.configureCurrentWindow(
        title: widget.arguments.title,
        videoWidth: widget.arguments.width,
        videoHeight: widget.arguments.height,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: MithkaVideoPlayer(
      source: MithkaVideoSource.uri(widget.arguments.uri),
      width: widget.arguments.width,
      height: widget.arguments.height,
      initialMuted: widget.arguments.muted,
      onClose: MithkaDesktopVideoWindows.closeCurrentWindow,
      onToggleFullscreen:
          MithkaDesktopVideoWindows.toggleCurrentWindowFullscreen,
    ),
  );
}
