import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/file_opener.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:open_filex/open_filex.dart';

class _Gate implements InstallPackagesGateway {
  _Gate({required this.status, this.permission});
  final Future<bool> status;
  final Future<bool>? permission;
  int checks = 0;
  int requests = 0;
  @override
  Future<bool> isGranted() {
    checks++;
    return status;
  }

  @override
  Future<bool> request() {
    requests++;
    return permission ?? Future.value(false);
  }
}

Widget _app(void Function(BuildContext) open) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [AppLocalizations.delegate],
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData(extensions: [AppColors.light]),
  home: Builder(
    builder: (context) => GestureDetector(
      key: const ValueKey('open'),
      onTap: () => open(context),
      child: const Text('open'),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final opened = <({String path, String? type})>[];
  setUp(() {
    opened.clear();
    downloadedFileOpen = (path, {type}) async {
      opened.add((path: path, type: type));
      return OpenResult();
    };
  });
  tearDown(() {
    installPackagesGateway = const SystemInstallPackagesGateway();
    downloadedFileOpen = OpenFilex.open;
  });

  testWidgets(
    'APK MIME gates an extensionless Android cache path',
    (tester) async {
      final gate = _Gate(status: Future.value(false));
      installPackagesGateway = gate;
      await tester.pumpWidget(
        _app((context) {
          unawaited(
            openDownloadedFile(context, '/tmp/cache/42', mimeType: apkMime),
          );
        }),
      );
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pump();
      final prompted = find.text('Allow app installs?').evaluate().isNotEmpty;
      if (prompted) {
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
      expect(prompted, isTrue);
      expect(gate.checks, 1);
      expect(opened, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  for (final granted in [false, true]) {
    testWidgets(
      'disposal during initial status check prevents opening: $granted',
      (tester) async {
        final status = Completer<bool>();
        installPackagesGateway = _Gate(status: status.future);
        Object? error;
        await tester.pumpWidget(
          _app((context) {
            unawaited(
              openDownloadedFile(context, '/tmp/cache/review.apk').catchError((
                Object e,
              ) {
                error = e;
              }),
            );
          }),
        );
        await tester.tap(find.byKey(const ValueKey('open')));
        await tester.pumpWidget(const SizedBox());
        status.complete(granted);
        await tester.pump();
        expect(error, isNull);
        expect(opened, isEmpty);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  testWidgets(
    'disposal while returning from settings prevents opening',
    (tester) async {
      final permission = Completer<bool>();
      final gate = _Gate(
        status: Future.value(false),
        permission: permission.future,
      );
      installPackagesGateway = gate;
      await tester.pumpWidget(
        _app((context) {
          unawaited(openDownloadedFile(context, '/tmp/cache/review.apk'));
        }),
      );
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pump();
      await tester.tap(find.text('Open Settings'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      permission.complete(true);
      await tester.pump(const Duration(milliseconds: 500));
      expect(gate.requests, 1);
      expect(opened, isEmpty);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'desktop APK MIME bypasses Android checks and opens once',
    (tester) async {
      final gate = _Gate(status: Future.value(false));
      installPackagesGateway = gate;
      await tester.pumpWidget(
        _app((context) {
          unawaited(
            openDownloadedFile(context, '/tmp/cache/42', mimeType: apkMime),
          );
        }),
      );
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      expect(gate.checks, 0);
      expect(opened, [(path: '/tmp/cache/42', type: apkMime)]);
    },
    variant: TargetPlatformVariant.desktop(),
  );
}
