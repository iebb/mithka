import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:multi_window_manager/multi_window_manager.dart';

import 'desktop_video_window_arguments.dart';
import 'desktop_video_window_layout.dart';

Widget buildDesktopWindowHost({
  required MithkaDesktopVideoWindowArguments initialArguments,
  required Widget Function(
    BuildContext context,
    MithkaDesktopVideoWindowArguments arguments,
  )
  builder,
  WidgetBuilder? loadingBuilder,
}) {
  if (!Platform.isLinux) {
    return Builder(builder: (context) => builder(context, initialArguments));
  }
  return ReusableWindow(
    initialArgs: [initialArguments.encode()],
    windowOptions: WindowOptions(
      size: preferredDesktopVideoWindowSize(
        initialArguments.width,
        initialArguments.height,
      ),
      minimumSize: desktopVideoMinimumWindowSize,
      center: true,
      title: MithkaDesktopVideoWindowArguments.normalizeTitle(
        initialArguments.title,
      ),
    ),
    loadingBuilder:
        loadingBuilder ?? (_) => const ColoredBox(color: Color(0xFF000000)),
    builder: (context, source) {
      final arguments =
          _tryParseArguments(source, windowType: initialArguments.windowType) ??
          initialArguments;
      return _ConfiguredWindow(
        key: ValueKey(arguments.encode()),
        arguments: arguments,
        builder: builder,
      );
    },
  );
}

MithkaDesktopVideoWindowArguments? _tryParseArguments(
  Object? source, {
  required String windowType,
}) {
  final encoded = switch (source) {
    final String value => value,
    final List values when values.isNotEmpty && values.first is String =>
      values.first! as String,
    _ => null,
  };
  return encoded == null
      ? null
      : MithkaDesktopVideoWindowArguments.tryParse(
          encoded,
          windowType: windowType,
        );
}

class _ConfiguredWindow extends StatefulWidget {
  const _ConfiguredWindow({
    super.key,
    required this.arguments,
    required this.builder,
  });

  final MithkaDesktopVideoWindowArguments arguments;
  final Widget Function(
    BuildContext context,
    MithkaDesktopVideoWindowArguments arguments,
  )
  builder;

  @override
  State<_ConfiguredWindow> createState() => _ConfiguredWindowState();
}

class _ConfiguredWindowState extends State<_ConfiguredWindow> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_configure());
    });
  }

  Future<void> _configure() async {
    try {
      final window = MultiWindowManager.current;
      await window.setMinimumSize(desktopVideoMinimumWindowSize);
      await window.setSize(
        preferredDesktopVideoWindowSize(
          widget.arguments.width,
          widget.arguments.height,
        ),
      );
      await window.setTitle(
        MithkaDesktopVideoWindowArguments.normalizeTitle(
          widget.arguments.title,
        ),
      );
      await window.center();
    } on Object {
      // Some compositors do not allow applications to reposition windows.
      // The player remains usable at the compositor-selected bounds.
    }
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, widget.arguments);
}
