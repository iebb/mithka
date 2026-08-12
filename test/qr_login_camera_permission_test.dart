import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/platform/camera_permission.dart';
import 'package:mithka/settings/qr_login_scanner_view.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('maps Android camera permission states to recoverable access', () {
    expect(
      cameraPermissionAccessFromStatus(PermissionStatus.granted),
      CameraPermissionAccess.granted,
    );
    expect(
      cameraPermissionAccessFromStatus(PermissionStatus.denied),
      CameraPermissionAccess.denied,
    );
    expect(
      cameraPermissionAccessFromStatus(PermissionStatus.permanentlyDenied),
      CameraPermissionAccess.blocked,
    );
    expect(
      cameraPermissionAccessFromStatus(PermissionStatus.restricted),
      CameraPermissionAccess.blocked,
    );
  });

  testWidgets('does not mount scanner before camera permission is granted', (
    tester,
  ) async {
    final permission = _FakeCameraPermission(CameraPermissionAccess.denied);
    var scannerBuilds = 0;
    await _pumpScanner(
      tester,
      permission: permission,
      scannerBuilder: (context, controller, onDetect) {
        scannerBuilds++;
        return const ColoredBox(
          key: ValueKey('fake-qr-login-scanner'),
          color: Colors.black,
        );
      },
    );

    expect(permission.requestCalls, 1);
    expect(scannerBuilds, 0);
    expect(find.byKey(const ValueKey('qr-login-camera-retry')), findsOneWidget);

    permission.access = CameraPermissionAccess.granted;
    await tester.tap(find.byKey(const ValueKey('qr-login-camera-retry')));
    await tester.pumpAndSettle();

    expect(permission.requestCalls, 2);
    expect(scannerBuilds, 1);
    expect(find.byKey(const ValueKey('fake-qr-login-scanner')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('blocked permission opens settings and recovers on return', (
    tester,
  ) async {
    final permission = _FakeCameraPermission(CameraPermissionAccess.blocked);
    await _pumpScanner(
      tester,
      permission: permission,
      scannerBuilder: (context, controller, onDetect) => const ColoredBox(
        key: ValueKey('fake-qr-login-scanner'),
        color: Colors.black,
      ),
    );

    expect(
      find.byKey(const ValueKey('qr-login-camera-open-settings')),
      findsOneWidget,
    );

    permission.access = CameraPermissionAccess.granted;
    await tester.tap(
      find.byKey(const ValueKey('qr-login-camera-open-settings')),
    );
    await tester.pumpAndSettle();

    expect(permission.openSettingsCalls, 1);
    expect(permission.checkCalls, 1);
    expect(find.byKey(const ValueKey('fake-qr-login-scanner')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpScanner(
  WidgetTester tester, {
  required CameraPermissionGateway permission,
  required QrLoginScannerBuilder scannerBuilder,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final theme = ThemeController(preferences);
  addTearDown(theme.dispose);

  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(extensions: [AppColors.dark]),
        home: QrLoginScannerView(
          cameraPermission: permission,
          scannerBuilder: scannerBuilder,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _FakeCameraPermission implements CameraPermissionGateway {
  _FakeCameraPermission(this.access);

  CameraPermissionAccess access;
  int requestCalls = 0;
  int checkCalls = 0;
  int openSettingsCalls = 0;

  @override
  Future<CameraPermissionAccess> check() async {
    checkCalls++;
    return access;
  }

  @override
  Future<CameraPermissionAccess> request() async {
    requestCalls++;
    return access;
  }

  @override
  Future<bool> openSettings() async {
    openSettingsCalls++;
    return true;
  }
}
