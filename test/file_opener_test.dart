import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/file_opener.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:open_filex/open_filex.dart';

class _FakeGateway implements InstallPackagesGateway {
  _FakeGateway(this.granted);

  bool granted;
  int checks = 0;
  int requests = 0;

  @override
  Future<bool> isGranted() async {
    checks++;
    return granted;
  }

  @override
  Future<bool> request() async {
    requests++;
    // The system settings toggle flips the switch while the request is away.
    granted = true;
    return granted;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    downloadedFileOpen = (path, {type}) async => OpenResult();
  });

  tearDown(() {
    installPackagesGateway = const SystemInstallPackagesGateway();
    downloadedFileOpen = OpenFilex.open;
  });

  testWidgets(
    'a denied APK gate explains the switch before opening',
    (tester) async {
      final gateway = _FakeGateway(false);
      installPackagesGateway = gateway;
      await tester.pumpWidget(_app());
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pump();
      expect(find.text('Allow app installs?'), findsOneWidget);
      expect(gateway.requests, 0);
      await tester.tap(find.text('Open Settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(gateway.requests, 1);
      expect(
        find.text(
          'Install permission granted. Open the file again to install.',
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'cancelling the APK gate never reaches the installer',
    (tester) async {
      final gateway = _FakeGateway(false);
      installPackagesGateway = gateway;
      await tester.pumpWidget(_app());
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(gateway.requests, 0);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'an already-granted switch opens without prompting',
    (tester) async {
      final gateway = _FakeGateway(true);
      installPackagesGateway = gateway;
      await tester.pumpWidget(_app());
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pump();
      expect(find.text('Allow app installs?'), findsNothing);
      expect(gateway.checks, 1);
      expect(gateway.requests, 0);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'desktop opens APKs without the install gate',
    (tester) async {
      final gateway = _FakeGateway(true);
      installPackagesGateway = gateway;
      await tester.pumpWidget(_app());
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pump();
      expect(find.text('Allow app installs?'), findsNothing);
      // The gate must not even query permission_handler on non-Android hosts.
      expect(gateway.checks, 0);
      expect(gateway.requests, 0);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'the opener survives its page unmounting during the grant',
    (tester) async {
      final gateway = _FakeGateway(false);
      installPackagesGateway = gateway;
      await tester.pumpWidget(_app());
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pump();
      await tester.tap(find.text('Open Settings'));
      await tester.pump();
      // The originating page goes away while the settings screen is up.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
      expect(gateway.requests, 1);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  test('the MIME map routes installs and common documents', () {
    expect(mimeForExtension('APK'), apkMime);
    expect(mimeForExtension('apk'), apkMime);
    expect(mimeForExtension('pdf'), 'application/pdf');
    expect(mimeForExtension('docx'), startsWith('application/vnd.'));
    expect(mimeForExtension(''), isNull);
    expect(mimeForExtension('madeup'), isNull);
  });
}

Widget _app() => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [AppLocalizations.delegate],
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData(extensions: [AppColors.light]),
  home: Builder(
    builder: (context) => Scaffold(
      body: GestureDetector(
        key: const ValueKey('open'),
        onTap: () => openDownloadedFile(
          context,
          '/tmp/downloads/update.apk',
          mimeType: mimeForExtension('apk'),
        ),
        child: const Text('open'),
      ),
    ),
  ),
);
