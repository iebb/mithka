import 'dart:async';
import 'dart:io';
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

  test('primary installs exit coordination before starting TDLib', () {
    final source = File('lib/main.dart').readAsStringSync();
    final bootstrap = source.substring(
      source.indexOf('Future<void> _bootstrapAndRunApp()'),
      source.indexOf('bool _shouldUseFvp()'),
    );

    expect(
      bootstrap.indexOf('await ApplicationExitCoordinator.install()'),
      lessThan(bootstrap.indexOf('final auth = AuthManager()..start()')),
    );

    final coordinator = File(
      'lib/platform/application_exit_coordinator.dart',
    ).readAsStringSync();
    expect(coordinator, contains("'System.initializationComplete'"));
    expect(coordinator, contains("'mithka/application_lifecycle'"));
    expect(coordinator, contains("invokeMethod<void>('ready')"));
    expect(coordinator, contains("call.method != 'requestExit'"));
    expect(
      coordinator.indexOf('WidgetsBinding.instance.addObserver(coordinator)'),
      lessThan(coordinator.indexOf("invokeMethod<void>('ready')")),
    );
    expect(
      coordinator.indexOf("invokeMethod<void>('ready')"),
      lessThan(coordinator.indexOf("'System.initializationComplete'")),
    );
  });

  test('TDLib shutdown preserves accounts and joins its receive isolate', () {
    final source = File('lib/tdlib/td_client.dart').readAsStringSync();
    final shutdown = source.substring(
      source.indexOf('Future<bool> shutdown()'),
      source.indexOf('// MARK: - Account management'),
    );
    final close = source.substring(
      source.indexOf('Future<bool> _closeClientForSlot('),
      source.indexOf('Future<void> _releaseAccountLease('),
    );

    expect(shutdown, contains('preserveBotApiAccount: true'));
    expect(
      shutdown,
      contains('_startClosingSlotResult(slot, preserveBotApiAccount: true)'),
    );
    expect(
      shutdown,
      contains('closing.timeout(const Duration(seconds: 16))'),
    );
    expect(shutdown, contains('await Future.wait(exits).timeout'));
    expect(close, contains('if (!preserveBotApiAccount)'));
    expect(close, contains('BotApiAccountRegistry.remove'));
    expect(source, contains('onExit: exitPort.sendPort'));
  });

  test('shutdown latch blocks delayed client creation and FFI work', () {
    final source = File('lib/tdlib/td_client.dart').readAsStringSync();
    final addBot = source.substring(
      source.indexOf('Future<int> addBotApiAccount('),
      source.indexOf('BotApiTdBackend _createBotApiBackend('),
    );
    final replaceEndpoint = source.substring(
      source.indexOf('Future<void> _replaceGlobalBotApiEndpoint('),
      source.indexOf('int _syntheticBotApiClientId('),
    );
    final restore = source.substring(
      source.indexOf('Future<int> _restoreImportedSessionSlot('),
      source.indexOf(
        'Future<TdFreshSessionResult> _createFreshSessionWithQrLogin(',
      ),
    );
    final addSave = addBot.indexOf('await BotApiAccountRegistry.save');
    final addGuard = addBot.indexOf('_ensureAcceptingNewClients();', addSave);
    final replaceSave = replaceEndpoint.indexOf(
      'await BotApiAccountRegistry.replaceMetadata',
    );
    final replaceGuard = replaceEndpoint.indexOf(
      '_ensureAcceptingNewClients();',
      replaceSave,
    );
    final importGuard = restore.indexOf('_ensureAcceptingNewClients();');
    final importCall = restore.indexOf('_bindings.importSessionString');

    expect(addGuard, greaterThan(addSave));
    expect(
      addGuard,
      lessThan(addBot.indexOf('_botApiBackendForClient[clientId] = backend')),
    );
    expect(replaceGuard, greaterThan(replaceSave));
    expect(
      replaceGuard,
      lessThan(replaceEndpoint.indexOf('_botApiBackendForClient.addAll')),
    );
    expect(importGuard, isNonNegative);
    expect(importGuard, lessThan(importCall));
  });
}
