import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../tdlib/td_client.dart';

typedef ApplicationShutdown = Future<bool> Function();

/// Participates in Flutter's cancelable desktop application-exit handshake.
///
/// FlutterAppDelegate forwards every normal macOS Quit request through
/// [WidgetsBindingObserver.didRequestAppExit]. Keeping this observer alive for
/// the primary engine's full lifetime ensures TDLib is drained even when Quit
/// is requested before the root widget finishes mounting.
final class ApplicationExitCoordinator with WidgetsBindingObserver {
  ApplicationExitCoordinator._(this._shutdown);

  static const MethodChannel _lifecycleChannel = MethodChannel(
    'mithka/application_lifecycle',
  );
  static Future<void>? _installOperation;

  final ApplicationShutdown _shutdown;

  static Future<void> install() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) {
      return Future<void>.value();
    }
    return _installOperation ??= _install();
  }

  static Future<void> _install() async {
    final coordinator = ApplicationExitCoordinator._(TdClient.shared.shutdown);
    WidgetsBinding.instance.addObserver(coordinator);
    _lifecycleChannel.setMethodCallHandler(coordinator._handleLifecycleCall);

    // The app delegate owns the termination decision and pins this channel to
    // the primary engine. A secondary desktop window therefore cannot replace
    // the handler that must drain the process-wide TDLib runtime.
    await _lifecycleChannel.invokeMethod<void>('ready');

    // Flutter sends this notification during ServicesBinding initialization,
    // but does not await it. Until the native delegate receives it, an early
    // macOS Quit is treated as mandatory and bypasses didRequestAppExit.
    // Awaiting the idempotent acknowledgement here closes that launch window
    // before AuthManager is allowed to create a TDLib client.
    await SystemChannels.platform.invokeMethod<void>(
      'System.initializationComplete',
    );
  }

  Future<bool> _handleLifecycleCall(MethodCall call) async {
    if (call.method != 'requestExit') {
      throw MissingPluginException('Unknown application lifecycle method');
    }
    return await applicationExitResponse(_shutdown) == AppExitResponse.exit;
  }

  @override
  Future<AppExitResponse> didRequestAppExit() {
    return applicationExitResponse(_shutdown);
  }
}

@visibleForTesting
Future<AppExitResponse> applicationExitResponse(
  ApplicationShutdown shutdown,
) async {
  try {
    return await shutdown() ? AppExitResponse.exit : AppExitResponse.cancel;
  } catch (error) {
    debugPrint('Application shutdown failed; Quit was cancelled: $error');
    return AppExitResponse.cancel;
  }
}
