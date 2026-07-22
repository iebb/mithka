import 'package:flutter/widgets.dart';

/// Runs [callback] after layout and guarantees that an idle UI produces the
/// frame needed to deliver the post-frame callback.
void scheduleChatPostFrame(VoidCallback callback) {
  final binding = WidgetsBinding.instance;
  binding.addPostFrameCallback((_) => callback());
  binding.ensureVisualUpdate();
}
