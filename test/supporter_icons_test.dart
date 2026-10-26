import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/pro/mithka_pro_service.dart';
import 'package:mithka/pro/mithka_pro_view.dart';
import 'package:mithka/settings/app_icon_controller.dart';
import 'package:mithka/settings/appearance_view.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const iconChannel = MethodChannel('mithka/app_icon');
  final nativeChanges = <String>[];
  String currentIcon = 'default';
  bool failNative = false;
  Completer<void>? nativeWait;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    nativeChanges.clear();
    currentIcon = 'default';
    failNative = false;
    nativeWait = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(iconChannel, (call) async {
          switch (call.method) {
            case 'isSupported':
              return true;
            case 'currentIcon':
              return currentIcon;
            case 'setIcon':
              final key = (call.arguments as Map)['name'] as String;
              nativeChanges.add(key);
              await nativeWait?.future;
              if (failNative) throw PlatformException(code: 'app_icon_failed');
              currentIcon = key;
              return null;
          }
          throw MissingPluginException();
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(iconChannel, null);
  });

  Future<_Fixture> fixture({
    _Gateway? gateway,
    TargetPlatform platform = TargetPlatform.iOS,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final store = gateway ?? _Gateway();
    final service = MithkaProService(gateway: store, platform: platform);
    final controller = AppIconController(
      prefs,
      proService: service,
      platform: platform,
    );
    addTearDown(controller.dispose);
    addTearDown(service.dispose);
    await service.initialize();
    await controller.initialize();
    return _Fixture(prefs, store, service, controller);
  }

  test(
    'eight existing icons stay free and twelve mobile outfits keep their order',
    () {
      expect(
        AppIconVariant.values
            .where((icon) => !icon.requiresSupporter)
            .map((icon) => icon.key),
        [
          'default',
          'white',
          'blue',
          'purple',
          'pixel',
          'aurora',
          'prism',
          'signal',
        ],
      );
      expect(
        AppIconVariant.values
            .where((icon) => icon.requiresSupporter)
            .map((icon) => icon.key),
        [
          'pilot',
          'headphones',
          'winter',
          'astronaut',
          'crown',
          'party',
          'sleepy',
          'heart',
          'coffee',
          'detective',
          'gamer',
          'fishing',
        ],
      );
      for (final platform in TargetPlatform.values) {
        final mobile =
            platform == TargetPlatform.iOS ||
            platform == TargetPlatform.android;
        expect(
          AppIconVariant.forPlatform(platform),
          hasLength(mobile ? 20 : 8),
        );
        expect(supporterIconsAvailableForPlatform(platform), mobile);
        expect(
          supporterIconsAvailableForPlatform(platform, isWeb: true),
          isFalse,
        );
      }
      expect(
        AppIconVariant.pilot.previewAsset(Brightness.dark),
        'assets/app_icons/pilot_dark.png',
      );
      expect(
        AppIconVariant.pilot.previewAsset(Brightness.light),
        'assets/app_icons/pilot.png',
      );
      expect(
        AppIconVariant.blue.previewAsset(Brightness.dark),
        AppIconVariant.blue.asset,
      );
    },
  );

  test(
    'every free icon is selectable without entitlement or billing connectivity',
    () async {
      final f = await fixture();
      f.gateway.failState = true;
      final queries = f.gateway.stateQueries;
      for (final icon in AppIconVariant.values.where(
        (icon) => !icon.requiresSupporter,
      )) {
        expect(await f.controller.setVariant(icon), isTrue);
      }
      expect(f.gateway.stateQueries, queries);
      expect(f.controller.variant, AppIconVariant.signal);
    },
  );

  test(
    'central controller denies paid icons even without the picker UI',
    () async {
      final f = await fixture();
      expect(await f.controller.setVariant(AppIconVariant.pilot), isFalse);
      expect(nativeChanges, isEmpty);
      expect(f.controller.variant, AppIconVariant.defaultIcon);
      expect(f.prefs.getString('selected_app_icon'), 'default');
    },
  );

  test(
    'a cached active flag cannot authorize a refunded or expired selection',
    () async {
      final f = await fixture(gateway: _Gateway(pro: true));
      expect(f.service.isPro, isTrue);
      f.gateway.pro = false; // Refunded since the last screen refresh.
      expect(await f.controller.setVariant(AppIconVariant.pilot), isFalse);
      f.gateway.pro = true;
      f.gateway.expiration = DateTime.now().subtract(
        const Duration(seconds: 1),
      );
      expect(await f.controller.setVariant(AppIconVariant.pilot), isFalse);
      expect(nativeChanges, isEmpty);
      expect(f.service.isPro, isFalse);
    },
  );

  test(
    'cancellation keeps access through paid expiry without checking auto-renew',
    () async {
      final f = await fixture(gateway: _Gateway(pro: true));
      // Provider reports verified access until expiry, irrespective of renewal intent.
      expect(await f.controller.setVariant(AppIconVariant.pilot), isTrue);
      expect(nativeChanges, ['pilot']);
      expect(f.prefs.getString('selected_app_icon'), 'pilot');
    },
  );

  test(
    'expiry retains selected paid icon; choosing free prevents paid reselection',
    () async {
      currentIcon = 'pilot';
      final f = await fixture();
      expect(f.controller.variant, AppIconVariant.pilot);
      expect(f.controller.isLocked(AppIconVariant.pilot), isFalse);
      expect(f.controller.isLocked(AppIconVariant.heart), isTrue);
      await f.service.refreshEntitlement();
      expect(
        nativeChanges,
        isEmpty,
        reason: 'expiry must never reset the launcher',
      );
      expect(await f.controller.setVariant(AppIconVariant.pilot), isFalse);
      expect(f.controller.variant, AppIconVariant.pilot);
      expect(await f.controller.setVariant(AppIconVariant.white), isTrue);
      expect(await f.controller.setVariant(AppIconVariant.pilot), isFalse);
      expect(nativeChanges, ['white']);
      expect(f.prefs.getString('selected_app_icon'), 'white');
    },
  );

  test(
    'active paid reselect still queries native entitlement without changing the launcher',
    () async {
      currentIcon = 'pilot';
      final f = await fixture(gateway: _Gateway(pro: true));
      final before = f.gateway.stateQueries;
      expect(await f.controller.setVariant(AppIconVariant.pilot), isTrue);
      expect(f.gateway.stateQueries, before + 1);
      expect(nativeChanges, isEmpty);
    },
  );

  test(
    'state errors fail closed even after a previous active entitlement',
    () async {
      final f = await fixture(gateway: _Gateway(pro: true));
      f.gateway.failState = true;
      expect(await f.controller.setVariant(AppIconVariant.pilot), isFalse);
      expect(f.service.isPro, isFalse);
      expect(nativeChanges, isEmpty);
    },
  );

  test(
    'native entitlement event invalidates immediately and rejects an older query',
    () async {
      final f = await fixture(gateway: _Gateway(pro: true));
      final old = Completer<Map<Object?, Object?>>();
      f.gateway.stateQuery = () => old.future;
      final selecting = f.controller.setVariant(AppIconVariant.pilot);
      f.gateway.stateQuery = null;
      f.gateway.pro = false;
      f.gateway.entitlementChanged!();
      expect(f.service.isPro, isFalse);
      await Future<void>.delayed(Duration.zero);
      old.complete(_state(pro: true));
      expect(await selecting, isFalse);
      expect(f.service.isPro, isFalse);
      expect(nativeChanges, isEmpty);
    },
  );

  test(
    'background invalidation prevents a suspended old authorization from winning',
    () async {
      final f = await fixture(gateway: _Gateway(pro: true));
      final old = Completer<Map<Object?, Object?>>();
      f.gateway.stateQuery = () => old.future;
      final selecting = f.controller.setVariant(AppIconVariant.pilot);
      f.service.invalidateEntitlement();
      old.complete(_state(pro: true));
      expect(await selecting, isFalse);
      expect(nativeChanges, isEmpty);
    },
  );

  test(
    'double taps cannot race entitlement checks or report a skipped change as success',
    () async {
      final f = await fixture(gateway: _Gateway(pro: true));
      nativeWait = Completer<void>();
      final first = f.controller.setVariant(AppIconVariant.pilot);
      await Future<void>.delayed(Duration.zero);
      expect(await f.controller.setVariant(AppIconVariant.heart), isFalse);
      nativeWait!.complete();
      expect(await first, isTrue);
      expect(nativeChanges, ['pilot']);
      expect(f.controller.variant, AppIconVariant.pilot);
    },
  );

  test(
    'native change failure leaves selection and persisted preference unchanged',
    () async {
      final f = await fixture(gateway: _Gateway(pro: true));
      failNative = true;
      expect(await f.controller.setVariant(AppIconVariant.pilot), isFalse);
      expect(f.controller.variant, AppIconVariant.defaultIcon);
      expect(f.prefs.getString('selected_app_icon'), 'default');
      expect(f.controller.loading, isFalse);
    },
  );

  test(
    'desktop cannot select paid icons even with an active native flag',
    () async {
      final f = await fixture(
        gateway: _Gateway(pro: true),
        platform: TargetPlatform.macOS,
      );
      expect(f.controller.availableVariants, hasLength(8));
      expect(f.service.storeAvailable, isFalse);
      expect(f.service.isPro, isFalse);
      expect(await f.controller.setVariant(AppIconVariant.pilot), isFalse);
      expect(await f.controller.setVariant(AppIconVariant.blue), isTrue);
      expect(f.gateway.stateQueries, 0);
      expect(nativeChanges, ['blue']);
    },
  );

  test(
    'new verified transaction event reconciles a superseded purchase or restore query',
    () async {
      for (final restore in [false, true]) {
        final f = await fixture();
        final old = Completer<Map<Object?, Object?>>();
        f.gateway.stateQuery = () => old.future;
        final transaction = restore
            ? f.service.restore()
            : f.service.purchase(mithkaProYearlyProductId);
        await Future<void>.delayed(Duration.zero);
        expect(f.service.working, isTrue);
        f.gateway.stateQuery = null;
        f.gateway.pro = true;
        f.gateway.entitlementChanged!();
        await Future<void>.delayed(Duration.zero);
        expect(f.service.isPro, isTrue);
        expect(f.service.working, isTrue);
        old.complete(_state(pro: false));
        expect(await transaction, isTrue);
        expect(f.service.working, isFalse);
        expect(f.service.isPro, isTrue);
      }
    },
  );

  test(
    'resume entitlement refresh is independent of a pre-background catalog request',
    () async {
      final f = await fixture();
      final old = Completer<Map<Object?, Object?>>();
      f.gateway.stateQuery = () => old.future;
      f.gateway.productsWait = Completer<void>();
      final catalog = f.service.refresh();
      f.service.invalidateEntitlement();
      f.gateway.stateQuery = null;
      f.gateway.pro = true;
      // This is the separate authorization refresh used by main on resume.
      expect(await f.service.refreshEntitlement(), isTrue);
      expect(
        f.service.loading,
        isTrue,
        reason: 'the old catalog remains suspended',
      );
      old.complete(_state(pro: false));
      f.gateway.productsWait!.complete();
      await catalog;
      expect(
        f.service.isPro,
        isTrue,
        reason: 'old state cannot replace the resumed snapshot',
      );
    },
  );

  for (final restore in [false, true]) {
    testWidgets(
      'superseding native event during ${restore ? 'restore' : 'purchase'} returns and applies once',
      (tester) async {
        final f = await fixture();
        await _pump(tester, f);
        await _tap(tester, find.byKey(const ValueKey('app-icon-heart')));
        final old = Completer<Map<Object?, Object?>>();
        f.gateway.stateQuery = () => old.future;
        final action = find.text(restore ? 'Restore purchases' : 'Subscribe');
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pump();
        f.gateway.stateQuery = null;
        f.gateway.pro = true;
        f.gateway.entitlementChanged!();
        await tester.pump();
        expect(f.service.isPro, isTrue);
        expect(f.service.working, isTrue);
        expect(find.byType(MithkaProView), findsOneWidget);
        expect(nativeChanges, isEmpty);
        old.complete(_state(pro: false));
        await tester.pumpAndSettle();
        expect(find.byType(MithkaProView), findsNothing);
        expect(nativeChanges, ['heart']);
        expect(f.controller.variant, AppIconVariant.heart);
      },
    );
  }

  testWidgets(
    'pending retry suspends old completion and cancellation dismisses only once',
    (tester) async {
      final observer = _PopObserver();
      final f = await fixture(
        gateway: _Gateway(purchaseError: 'pro_purchase_pending'),
      );
      await _pump(tester, f, observer: observer);
      await _tap(tester, find.byKey(const ValueKey('app-icon-pilot')));
      await _tap(tester, find.text('Subscribe'));
      f.gateway.purchaseError = 'pro_purchase_cancelled';
      f.gateway.purchaseWait = Completer<void>();
      await tester.ensureVisible(find.text('Subscribe'));
      await tester.tap(find.text('Subscribe'));
      await tester.pump();
      f.gateway.pro =
          true; // The original pending purchase completes during retry.
      f.gateway.entitlementChanged!();
      await tester.pump();
      expect(f.service.isPro, isTrue);
      expect(find.byType(MithkaProView), findsOneWidget);
      expect(observer.pops, 0);
      f.gateway.purchaseWait!.complete();
      await tester.pumpAndSettle();
      expect(observer.pops, 1);
      expect(find.byType(MithkaProView), findsNothing);
      expect(find.byType(AppIconSettingsView), findsOneWidget);
      expect(
        nativeChanges,
        isEmpty,
        reason: 'cancel must discard the pending tapped icon',
      );
    },
  );

  testWidgets('Supporter caption aligns with its section heading', (
    tester,
  ) async {
    final f = await fixture();
    await _pump(tester, f);
    final heading = find.text(AppStrings.t(AppStringKeys.supporterIcons));
    final caption = find.text(
      AppStrings.t(AppStringKeys.supporterIconsCaption),
    );
    await tester.ensureVisible(caption);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(caption).dx, tester.getTopLeft(heading).dx);
  });

  testWidgets(
    'locked full-color tiles have a 28-point contrast badge and system-dark previews',
    (tester) async {
      final f = await fixture();
      await _pump(tester, f, dark: true);
      final badge = find.byKey(const ValueKey('icon-locked-pilot'));
      await tester.ensureVisible(badge);
      await tester.pumpAndSettle();
      expect(tester.getSize(badge), const Size(28, 28));
      final box = tester.widget<Container>(badge).decoration! as BoxDecoration;
      expect(box.color, const Color(0xFFEDEDED));
      final image = tester.widget<Image>(
        find.descendant(
          of: find.byKey(const ValueKey('app-icon-pilot')),
          matching: find.byType(Image),
        ),
      );
      final provider = image.image as ResizeImage;
      expect(
        (provider.imageProvider as AssetImage).assetName,
        'assets/app_icons/pilot_dark.png',
      );
    },
  );

  testWidgets(
    'expired selected tile keeps its check and other paid tiles lock',
    (tester) async {
      currentIcon = 'pilot';
      final f = await fixture();
      await _pump(tester, f);
      expect(find.byKey(const ValueKey('icon-selected-pilot')), findsOneWidget);
      expect(find.byKey(const ValueKey('icon-locked-pilot')), findsNothing);
      expect(find.byKey(const ValueKey('icon-locked-heart')), findsOneWidget);
      expect(nativeChanges, isEmpty);
    },
  );

  testWidgets(
    'verified purchase returns to picker and applies exactly the tapped icon once',
    (tester) async {
      final f = await fixture(gateway: _Gateway(purchaseGrants: true));
      await _pump(tester, f);
      await _tap(tester, find.byKey(const ValueKey('app-icon-heart')));
      expect(find.byType(MithkaProView), findsOneWidget);
      expect(nativeChanges, isEmpty);
      await _tap(tester, find.text('Subscribe'));
      expect(find.byType(MithkaProView), findsNothing);
      expect(nativeChanges, ['heart']);
      expect(f.controller.variant, AppIconVariant.heart);
    },
  );

  testWidgets('verified restore consumes the pending tapped icon once', (
    tester,
  ) async {
    final f = await fixture(gateway: _Gateway(restoreGrants: true));
    await _pump(tester, f);
    await _tap(tester, find.byKey(const ValueKey('app-icon-fishing')));
    await _tap(tester, find.text('Restore purchases'));
    expect(find.byType(MithkaProView), findsNothing);
    expect(nativeChanges, ['fishing']);
  });

  testWidgets(
    'pending purchase never unlocks until a verified native update arrives',
    (tester) async {
      final gateway = _Gateway(purchaseError: 'pro_purchase_pending');
      final f = await fixture(gateway: gateway);
      await _pump(tester, f);
      await _tap(tester, find.byKey(const ValueKey('app-icon-pilot')));
      await _tap(tester, find.text('Subscribe'));
      expect(
        find.text(
          'Your purchase is pending. Supporter will unlock once it’s confirmed.',
        ),
        findsOneWidget,
      );
      expect(nativeChanges, isEmpty);
      expect(f.service.isPro, isFalse);
      gateway.pro = true;
      gateway.entitlementChanged!();
      await tester.pumpAndSettle();
      expect(find.byType(MithkaProView), findsNothing);
      expect(nativeChanges, ['pilot']);
    },
  );

  testWidgets(
    'back discards pending icon and later entitlement never changes it',
    (tester) async {
      final gateway = _Gateway(purchaseError: 'pro_purchase_pending');
      final f = await fixture(gateway: gateway);
      await _pump(tester, f);
      await _tap(tester, find.byKey(const ValueKey('app-icon-pilot')));
      await _tap(tester, find.text('Subscribe'));
      Navigator.of(tester.element(find.byType(MithkaProView))).pop();
      await tester.pumpAndSettle();
      gateway.pro = true;
      gateway.entitlementChanged!();
      await tester.pumpAndSettle();
      expect(f.controller.variant, AppIconVariant.defaultIcon);
      expect(nativeChanges, isEmpty);
    },
  );

  testWidgets(
    'store cancellation dismisses without changing icon or showing success',
    (tester) async {
      final f = await fixture(
        gateway: _Gateway(purchaseError: 'pro_purchase_cancelled'),
      );
      await _pump(tester, f);
      await _tap(tester, find.byKey(const ValueKey('app-icon-pilot')));
      await _tap(tester, find.text('Subscribe'));
      expect(find.byType(MithkaProView), findsNothing);
      expect(nativeChanges, isEmpty);
      expect(find.text('Thanks for supporting Mithka.'), findsNothing);
    },
  );

  testWidgets(
    'empty restore and failed purchase do not apply the pending icon',
    (tester) async {
      final f = await fixture(
        gateway: _Gateway(purchaseError: 'pro_purchase_failed'),
      );
      await _pump(tester, f);
      await _tap(tester, find.byKey(const ValueKey('app-icon-pilot')));
      await _tap(tester, find.text('Restore purchases'));
      expect(
        find.text(
          'No active Supporter subscription was found for this Apple Account.',
        ),
        findsOneWidget,
      );
      await _tap(tester, find.text('Subscribe'));
      expect(
        find.text('Couldn’t complete your purchase. Try again.'),
        findsOneWidget,
      );
      expect(nativeChanges, isEmpty);
      expect(f.prefs.getString('selected_app_icon'), 'default');
    },
  );

  testWidgets(
    'unavailable catalog has retry and never advertises invented USD prices',
    (tester) async {
      final gateway = _Gateway(productsAvailable: false);
      final f = await fixture(gateway: gateway);
      await _pump(tester, f, home: MithkaProView(service: f.service));
      expect(
        find.text('Plans aren’t available right now. Try again later.'),
        findsOneWidget,
      );
      expect(find.text(r'$0.69 / month'), findsNothing);
      expect(find.text(r'$3.99 / year'), findsNothing);
      gateway.productsAvailable = true;
      await _tap(tester, find.text('Try again'));
      expect(find.text(r'$0.69 / month'), findsOneWidget);
      expect(find.text(r'$3.99 / year'), findsOneWidget);
      expect(find.textContaining('next yearly renewal'), findsNothing);
    },
  );

  testWidgets(
    'loading and purchase progress are visible without granting access',
    (tester) async {
      final f = await fixture();
      f.gateway.productsWait = Completer<void>();
      final refreshing = f.service.refresh();
      // Do not settle while the deliberately pending operation animates.
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ThemeController(f.prefs)),
          ],
          child: MaterialApp(
            theme: ThemeData(extensions: [AppColors.light]),
            home: MithkaProView(service: f.service),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Loading plans…'), findsOneWidget);
      f.gateway.productsWait!.complete();
      await refreshing;
      await tester.pumpAndSettle();
      f.gateway.purchaseWait = Completer<void>();
      await tester.ensureVisible(find.text('Subscribe'));
      await tester.tap(find.text('Subscribe'));
      await tester.pump();
      expect(find.text('Completing purchase…'), findsOneWidget);
      expect(f.service.isPro, isFalse);
      f.gateway.purchaseWait!.complete();
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Your purchase is pending. Supporter will unlock once it’s confirmed.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'restore progress and failure remain on plans and preserve the icon',
    (tester) async {
      final f = await fixture();
      await _pump(tester, f);
      await _tap(tester, find.byKey(const ValueKey('app-icon-pilot')));
      f.gateway.restoreWait = Completer<void>();
      f.gateway.restoreError = 'restore_failed';
      await tester.ensureVisible(find.text('Restore purchases'));
      await tester.tap(find.text('Restore purchases'));
      await tester.pump();
      expect(find.text('Restoring purchases…'), findsOneWidget);
      expect(nativeChanges, isEmpty);
      f.gateway.restoreWait!.complete();
      await tester.pumpAndSettle();
      expect(
        find.text('Couldn’t restore purchases. Try again.'),
        findsOneWidget,
      );
      expect(f.controller.variant, AppIconVariant.defaultIcon);
      expect(nativeChanges, isEmpty);
    },
  );

  test(
    'method gateway preserves Google Play pending and cancelled statuses',
    () async {
      const channel = MethodChannel('mithka/pro');
      String status = 'pending';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => {'status': status});
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      const gateway = MethodChannelMithkaProGateway();
      await expectLater(
        gateway.purchase(mithkaProYearlyProductId),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'purchase_pending',
          ),
        ),
      );
      status = 'cancelled';
      await expectLater(
        gateway.purchase(mithkaProYearlyProductId),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'purchase_cancelled',
          ),
        ),
      );
    },
  );

  testWidgets('desktop picker contains eight free icons and no paid prompt', (
    tester,
  ) async {
    final f = await fixture(platform: TargetPlatform.macOS);
    await _pump(tester, f);
    expect(find.text('Supporter icons'), findsNothing);
    expect(find.byKey(const ValueKey('app-icon-pilot')), findsNothing);
    expect(find.byKey(const ValueKey('app-icon-signal')), findsOneWidget);
    expect(find.text('Support us'), findsNothing);
  });
}

class _Fixture {
  _Fixture(this.prefs, this.gateway, this.service, this.controller);
  final SharedPreferences prefs;
  final _Gateway gateway;
  final MithkaProService service;
  final AppIconController controller;
}

Future<void> _pump(
  WidgetTester tester,
  _Fixture fixture, {
  Widget? home,
  bool dark = false,
  NavigatorObserver? observer,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeController(fixture.prefs)),
        ChangeNotifierProvider.value(value: fixture.controller),
        ChangeNotifierProvider.value(value: fixture.service),
      ],
      child: MaterialApp(
        navigatorObservers: [?observer],
        theme: ThemeData(
          platform: TargetPlatform.iOS,
          extensions: [AppColors.light],
        ),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(800, 600),
            platformBrightness: dark ? Brightness.dark : Brightness.light,
          ),
          child: home ?? const AppIconSettingsView(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Map<Object?, Object?> _state({required bool pro, DateTime? expiration}) => {
  'storeAvailable': true,
  'isPro': pro,
  'distribution': 'app_store',
  'expirationDateMillis': expiration?.millisecondsSinceEpoch,
};

class _Gateway implements MithkaProGateway, MithkaProEntitlementEvents {
  _Gateway({
    this.pro = false,
    this.purchaseGrants = false,
    this.restoreGrants = false,
    this.purchaseError,
    this.productsAvailable = true,
  });
  bool pro;
  bool failState = false;
  bool productsAvailable;
  bool purchaseGrants;
  bool restoreGrants;
  String? purchaseError;
  String? restoreError;
  Completer<void>? productsWait;
  Completer<void>? purchaseWait;
  Completer<void>? restoreWait;
  DateTime? expiration;
  int stateQueries = 0;
  VoidCallback? entitlementChanged;
  Future<Map<Object?, Object?>> Function()? stateQuery;

  @override
  void setEntitlementChangedHandler(VoidCallback? handler) =>
      entitlementChanged = handler;

  @override
  Future<Map<Object?, Object?>> getState() async {
    stateQueries++;
    if (failState) throw PlatformException(code: 'offline');
    if (stateQuery != null) return stateQuery!();
    return _state(pro: pro, expiration: expiration);
  }

  @override
  Future<List<Object?>> getProducts() async {
    await productsWait?.future;
    return !productsAvailable
        ? []
        : [
            {
              'id': mithkaProMonthlyProductId,
              'displayPrice': r'$0.69',
              'period': 'monthly',
            },
            {
              'id': mithkaProYearlyProductId,
              'displayPrice': r'$3.99',
              'period': 'yearly',
            },
          ];
  }

  @override
  Future<void> purchase(String productId) async {
    await purchaseWait?.future;
    if (purchaseError != null) throw PlatformException(code: purchaseError!);
    pro = purchaseGrants;
  }

  @override
  Future<void> restore() async {
    await restoreWait?.future;
    if (restoreError != null) throw PlatformException(code: restoreError!);
    pro = restoreGrants;
  }

  @override
  Future<void> manage({String? productId}) async {}
}

class _PopObserver extends NavigatorObserver {
  int pops = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pops++;
    super.didPop(route, previousRoute);
  }
}
