import 'package:flutter/widgets.dart';

import 'desktop_video_window_arguments.dart';
import 'desktop_video_window_host_stub.dart'
    if (dart.library.io) 'desktop_video_window_host_io.dart'
    as implementation;

typedef MithkaDesktopVideoWindowBuilder =
    Widget Function(
      BuildContext context,
      MithkaDesktopVideoWindowArguments arguments,
    );

/// Hosts the content of an independent desktop video window.
///
/// Linux retains hidden secondary Flutter engines because repeatedly tearing
/// down GTK Flutter views is unsafe. When an engine is reused, [builder]
/// receives the new arguments in a fresh subtree, so the old player/controller
/// is disposed before a different URI is opened. Other platforms and the
/// portable stub render the initial content directly.
class MithkaDesktopVideoWindowHost extends StatelessWidget {
  const MithkaDesktopVideoWindowHost({
    super.key,
    required this.initialArguments,
    required this.builder,
    this.loadingBuilder,
  });

  final MithkaDesktopVideoWindowArguments initialArguments;
  final MithkaDesktopVideoWindowBuilder builder;
  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) => implementation.buildDesktopWindowHost(
    initialArguments: initialArguments,
    builder: builder,
    loadingBuilder: loadingBuilder,
  );
}
