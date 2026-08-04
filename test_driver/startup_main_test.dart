//
//  startup_main_test.dart
//
//  Driver side of the startup benchmark: waits for the first rasterized
//  frame (flushing start_up_info.json) and exits.
//

import 'package:flutter_driver/flutter_driver.dart';

Future<void> main() async {
  final driver = await FlutterDriver.connect();
  await driver.waitUntilFirstFrameRasterized();
  await driver.close();
}
