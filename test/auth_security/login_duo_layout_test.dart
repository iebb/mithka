import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/scaled_app_view.dart';
import 'package:mithka/app/top_corner_cluster.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/auth/login_view.dart';
import 'package:mithka/l10n/app_locale_controller.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/l10n_fixtures.dart';

/// Writes PNGs of each layout to build/login-duo-captures when set.
const _capture = bool.fromEnvironment('CAPTURE_LOGIN_DUO');

/// Directory holding Roboto-*.ttf (the Flutter SDK's material_fonts), so the
/// captures and line counts use real glyphs instead of the test font.
const _fontDir = String.fromEnvironment('LOGIN_DUO_FONT_DIR');

/// An opened iPhone Duo as the platform reports it, in window points.
const _openedDuo = TopOcclusionData(
  safeTop: 82,
  statusBarBottom: 2,
  windowWidth: 951,
  regions: [Rect.fromLTWH(807, 0, 144, 82)],
);

/// A closed iPhone Duo: the camera nested inside the status cluster.
const _closedDuo = TopOcclusionData(
  safeTop: 82,
  statusBarBottom: 2,
  windowWidth: 466,
  regions: [Rect.fromLTWH(266, 0, 200, 82), Rect.fromLTWH(399.7, 29.3, 37, 37)],
);

/// A regular iPhone: a full-width status bar around the Dynamic Island.
const _iPhone = TopOcclusionData(
  safeTop: 62,
  statusBarBottom: 54,
  windowWidth: 440,
  regions: [Rect.fromLTWH(157, 11, 126, 37)],
);

const _openedSize = Size(951, 669);
const _bottomInset = 34.0;

class _PhoneStepAuth extends AuthManager {
  @override
  AuthStep get step => const AuthWaitPhoneNumber();
}

bool _realFonts = false;

void main() {
  setUpAll(() async {
    L10nFixtures.load().install();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async => request['@type'] == 'getProxies'
            ? {'@type': 'proxies', 'proxies': <Map<String, dynamic>>[]}
            : {'@type': 'ok'},
        send: (_) async {},
        updates: const Stream<Map<String, dynamic>>.empty(),
      ),
    );
    _realFonts = await _loadRealFonts();
  });

  setUp(() {
    // iCloud Keychain backup offered, as on the device, so the form shows
    // its consent row.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('mithka/account_backup'),
          (call) async => switch (call.method) {
            'isSupported' => true,
            'isLocalStorageSupported' => false,
            _ => null,
          },
        );
  });

  for (final s in const [1.0, 0.9, 2.2]) {
    testWidgets(
      'opened Duo login: menu column, brand on the clock line, centred form '
      'at s=$s',
      (tester) async {
        await _pump(
          tester,
          size: _openedSize,
          top: 82,
          data: _openedDuo,
          scale: s,
        );
        await _captureIfEnabled(tester, 'opened-duo-${(s * 100).round()}');

        // 1. A full-height column flush with the left edge, 280pt wide.
        final menu = tester.getRect(
          find.byKey(const ValueKey('login-duo-menu')),
        );
        expect(menu.left, moreOrLessEquals(0));
        expect(menu.top, moreOrLessEquals(0));
        expect(menu.width, moreOrLessEquals(280, epsilon: 0.01));
        expect(menu.bottom, moreOrLessEquals(_openedSize.height));
        expect(_menuTint(tester), isNot(Colors.transparent));
        // No card: the tint is the column itself, not a rounded inset panel.
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('login-duo-menu')),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is DecoratedBox &&
                  w.decoration is BoxDecoration &&
                  (w.decoration as BoxDecoration).borderRadius != null &&
                  w.child is CustomScrollView,
            ),
          ),
          findsNothing,
        );

        // 2. The brand row shares the status cluster's vertical centre.
        final brand = tester.getRect(find.byKey(const ValueKey('login-brand')));
        final cluster = _openedDuo.regions.single;
        expect(
          brand.center.dy,
          moreOrLessEquals(cluster.center.dy, epsilon: 0.5),
        );

        // Labels wrap rather than truncate.
        for (final key in const [
          'login-restore',
          'login-method-phoneNumber',
          'login-method-qrCode',
          'login-method-botToken',
          'login-language',
          'login-proxy',
          'login-terms',
        ]) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find
                .descendant(
                  of: find.byKey(ValueKey(key)),
                  matching: find.byType(RichText),
                )
                .last,
          );
          expect(paragraph.maxLines, isNull, reason: key);
          expect(paragraph.didExceedMaxLines, isFalse, reason: key);
          expect(paragraph.overflow, isNot(TextOverflow.ellipsis), reason: key);
        }
        final restoreLines = _lines(tester, 'login-restore');

        // 3. The form: 420pt wide, centred in the right side; centred
        // vertically when it fits, else 24pt below the clock line.
        final form = tester.getRect(
          find.byKey(const ValueKey('login-duo-form')),
        );
        expect(form.width, moreOrLessEquals(420, epsilon: 0.01));
        expect(
          form.center.dx,
          moreOrLessEquals((menu.right + _openedSize.width) / 2, epsilon: 0.01),
        );
        const clear = 82.0 + 24;
        final fits = form.height <= _openedSize.height - clear * 2;
        if (fits) {
          expect(
            form.center.dy,
            moreOrLessEquals(_openedSize.height / 2, epsilon: 0.01),
          );
        } else {
          expect(form.top, moreOrLessEquals(clear, epsilon: 0.01));
        }
        expect(form.top, greaterThanOrEqualTo(clear - 0.01));
        expect(form.left, greaterThanOrEqualTo(menu.right));

        // 4. Terms of Service ends at the bottom inset + 16pt, scrolled to
        // the end when the column is taller than the window.
        final menuScroll = tester
            .state<ScrollableState>(
              find.descendant(
                of: find.byKey(const ValueKey('login-sidebar-scroll')),
                matching: find.byType(Scrollable),
              ),
            )
            .position;
        final menuOverflow = menuScroll.maxScrollExtent;
        menuScroll.jumpTo(menuOverflow);
        await tester.pump();
        final terms = tester.getRect(find.byKey(const ValueKey('login-terms')));
        final gap = _openedSize.height - terms.bottom;
        expect(gap, moreOrLessEquals(_bottomInset + 16, epsilon: 0.01));
        if (s > 2) {
          await _captureIfEnabled(
            tester,
            'opened-duo-${(s * 100).round()}-menu-end',
          );
        }

        // ignore: avoid_print
        print(
          'MEASURE opened s=$s fonts=$_realFonts '
          'menu=${menu.width.toStringAsFixed(2)}x${menu.height.toStringAsFixed(2)} '
          'brandCenterY=${brand.center.dy.toStringAsFixed(2)} '
          'clusterCenterY=${cluster.center.dy.toStringAsFixed(2)} '
          'form=${_rect(form)} formCenter=(${form.center.dx.toStringAsFixed(2)},'
          '${form.center.dy.toStringAsFixed(2)}) fits=$fits '
          'termsBottom=${terms.bottom.toStringAsFixed(2)} '
          'termsGap=${gap.toStringAsFixed(2)} restoreLines=$restoreLines '
          'menuScroll=${menuOverflow.toStringAsFixed(2)}',
        );
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }

  testWidgets(
    'opened Duo without cluster geometry keeps the inset sidebar',
    (tester) async {
      await _pump(tester, size: _openedSize, top: 82, data: null, scale: 1);
      expect(find.byKey(const ValueKey('login-duo-menu')), findsNothing);
      expect(
        tester.getRect(find.byKey(const ValueKey('login-sidebar-scroll'))).top,
        moreOrLessEquals(82),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  for (final (name, size, top, data) in const [
    ('closed-duo', Size(466, 1000), 82.0, _closedDuo),
    ('iphone', Size(440, 956), 62.0, _iPhone),
  ]) {
    testWidgets(
      '$name login keeps the single lane, with or without cluster geometry',
      (tester) async {
        await _pump(tester, size: size, top: top, data: data, scale: 1);
        await _captureIfEnabled(tester, '$name-100');
        expect(find.byKey(const ValueKey('login-duo-menu')), findsNothing);
        expect(
          find.byKey(const ValueKey('login-sidebar-scroll')),
          findsNothing,
        );
        final withData = _laneRects(tester);
        await _pump(tester, size: size, top: top, data: null, scale: 1);
        expect(_laneRects(tester), withData);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }

  testWidgets(
    'an iPad window keeps the inset sidebar',
    (tester) async {
      await _pump(
        tester,
        size: const Size(1180, 820),
        top: 24,
        data: null,
        scale: 1,
      );
      await _captureIfEnabled(tester, 'ipad-100');
      expect(find.byKey(const ValueKey('login-duo-menu')), findsNothing);
      final sidebar = tester.getRect(
        find.byKey(const ValueKey('login-sidebar-scroll')),
      );
      expect(sidebar.width, moreOrLessEquals(184));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}

String _rect(Rect r) =>
    '(${r.left.toStringAsFixed(2)},${r.top.toStringAsFixed(2)},'
    '${r.width.toStringAsFixed(2)}x${r.height.toStringAsFixed(2)})';

Color _menuTint(WidgetTester tester) => tester
    .widget<ColoredBox>(
      find
          .descendant(
            of: find.byKey(const ValueKey('login-duo-menu')),
            matching: find.byType(ColoredBox),
          )
          .first,
    )
    .color;

/// Lines the row's label takes, from its laid-out height.
int _lines(WidgetTester tester, String key) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find
        .descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(RichText),
        )
        // The icon glyph is a RichText too; the label follows it.
        .last,
  );
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(
      baseOffset: 0,
      extentOffset: paragraph.text.toPlainText().length,
    ),
  );
  return boxes.map((b) => b.top.round()).toSet().length;
}

List<Rect> _laneRects(WidgetTester tester) => [
  for (final finder in [
    find.text('Mithka'),
    find.byType(TextField),
    find.byKey(const ValueKey('login-method-phoneNumber')),
  ])
    tester.getRect(finder.first),
];

Future<bool> _loadRealFonts() async {
  if (_fontDir.isEmpty) return false;
  final dir = Directory(_fontDir);
  if (!dir.existsSync()) return false;
  final roboto = FontLoader('Roboto');
  var any = false;
  for (final file in dir.listSync().whereType<File>()) {
    final name = file.uri.pathSegments.last;
    if (!name.startsWith('Roboto-') || !name.endsWith('.ttf')) continue;
    final bytes = file.readAsBytesSync();
    roboto.addFont(Future.value(ByteData.sublistView(bytes)));
    any = true;
  }
  if (!any) return false;
  await roboto.load();
  // Icon fonts and any bundled families, so glyphs draw as on the device.
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json'));
  for (final entry in manifest as List<dynamic>) {
    final loader = FontLoader(entry['family'] as String);
    for (final font in entry['fonts'] as List<dynamic>) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
  return true;
}

const _boundaryKey = ValueKey('login-duo-capture');

Future<void> _captureIfEnabled(WidgetTester tester, String name) async {
  if (!_capture) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundaryKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = data!;
      final directory = Directory('build/login-duo-captures');
      await directory.create(recursive: true);
      await File('${directory.path}/$name.png').writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
    } finally {
      image.dispose();
    }
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  required double top,
  required TopOcclusionData? data,
  required double scale,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(top: top, bottom: _bottomInset);
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final accounts = AccountStore(prefs);
  final localeController = AppLocaleController(prefs);
  final themeController = ThemeController(prefs);
  final auth = _PhoneStepAuth();
  addTearDown(accounts.dispose);
  addTearDown(localeController.dispose);
  addTearDown(themeController.dispose);
  addTearDown(auth.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AccountStore>.value(value: accounts),
        ChangeNotifierProvider<AuthManager>.value(value: auth),
        ChangeNotifierProvider<AppLocaleController>.value(
          value: localeController,
        ),
        ChangeNotifierProvider<ThemeController>.value(value: themeController),
      ],
      child: MaterialApp(
        // A new key per pump starts each layout from a fresh state.
        key: UniqueKey(),
        debugShowCheckedModeBanner: false,
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          extensions: [AppColors.light],
          fontFamily: _realFonts ? 'Roboto' : null,
        ),
        builder: (context, child) => RepaintBoundary(
          key: _boundaryKey,
          child: ScaledAppView(
            textScale: 1,
            interfaceScale: scale,
            child: Builder(
              builder: (context) => TopOcclusionGeometry(
                data: data?.inViewScale(ScaledAppView.scaleOf(context)),
                child: child!,
              ),
            ),
          ),
        ),
        home: const LoginView(),
      ),
    ),
  );
  if (_capture) {
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/penguin.png'),
        tester.element(find.byType(LoginView)),
      ),
    );
  }
  // Panes and the brand row measure themselves after their first frame.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}
