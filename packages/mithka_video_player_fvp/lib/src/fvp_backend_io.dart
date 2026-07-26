import 'dart:io';

import 'package:fvp/fvp.dart' as fvp;

bool get isAvailableOnCurrentPlatform =>
    Platform.isAndroid ||
    Platform.isIOS ||
    Platform.isLinux ||
    Platform.isMacOS ||
    Platform.isWindows;

void register(Map<String, Object> options) {
  fvp.registerWith(options: options);
}
