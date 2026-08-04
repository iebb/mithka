//
//  startup_main.dart
//
//  Instrumented entrypoint for the startup benchmark:
//    flutter drive --profile --trace-startup \
//      -t test_driver/startup_main.dart -d macos
//  Writes build/start_up_info.json (time to first frame / rasterized).
//

import 'package:flutter_driver/driver_extension.dart';
import 'package:mithka/main.dart' as app;

void main() {
  enableFlutterDriverExtension();
  app.main(const <String>[]);
}
