import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/platform/application_exit_coordinator.dart';

void main() {
  test('application exit waits for a successful graceful shutdown', () async {
    final shutdown = Completer<bool>();
    var completed = false;

    final response = applicationExitResponse(() => shutdown.future);
    unawaited(response.then((_) => completed = true));
    await Future<void>.delayed(Duration.zero);

    expect(completed, isFalse);
    shutdown.complete(true);
    expect(await response, AppExitResponse.exit);
  });

  test(
    'application exit is cancelled when native clients remain open',
    () async {
      expect(
        await applicationExitResponse(() async => false),
        AppExitResponse.cancel,
      );
    },
  );

  test('application exit is cancelled when shutdown throws', () async {
    expect(
      await applicationExitResponse(() async => throw StateError('failed')),
      AppExitResponse.cancel,
    );
  });
}
