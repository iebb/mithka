import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/pro/mithka_pro_service.dart';
import 'package:mithka/pro/mithka_pro_view.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Pro surface shows both plans with an owned selection control', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = MithkaProService(gateway: _ViewGateway());
    await service.initialize();

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>(
        create: (_) => ThemeController(prefs),
        child: MaterialApp(
          theme: ThemeData(extensions: [AppColors.light]),
          home: MithkaProView(service: service),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(r'$0.69 per month'), findsOneWidget);
    expect(find.text(r'$4.99 per year'), findsOneWidget);
    expect(find.byType(AppCheckbox), findsNWidgets(2));
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(Radio<String>), findsNothing);
    expect(find.text('Unlimited cloud session syncs'), findsOneWidget);
    expect(find.text('Unlimited accounts'), findsNothing);
  });

  testWidgets('active Pro primary action opens subscription management', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final gateway = _ViewGateway(pro: true);
    final service = MithkaProService(gateway: gateway);
    await service.initialize();

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>(
        create: (_) => ThemeController(prefs),
        child: MaterialApp(
          theme: ThemeData(extensions: [AppColors.light]),
          home: MithkaProView(service: service),
        ),
      ),
    );
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -650));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage subscription'));
    await tester.pumpAndSettle();

    expect(gateway.managedProductId, mithkaProYearlyProductId);
  });

  testWidgets('Pro header owns the system inset like other settings pages', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = MithkaProService(gateway: _ViewGateway());
    await service.initialize();

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>(
        create: (_) => ThemeController(prefs),
        child: MaterialApp(
          theme: ThemeData(extensions: [AppColors.light]),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(390, 844),
              padding: EdgeInsets.only(top: 44, bottom: 34),
            ),
            child: MithkaProView(service: service),
          ),
        ),
      ),
    );
    await tester.pump();

    final header = find.byType(NavHeader);
    final list = find.byType(ListView);
    expect(tester.getTopLeft(header).dy, 0);
    expect(tester.getTopLeft(list).dy, tester.getBottomLeft(header).dy);
  });

  test('new Pro and login surfaces avoid stock platform controls and icons', () {
    final files = [
      File('lib/pro/mithka_pro_view.dart'),
      File('lib/auth/login_view.dart'),
      File('lib/profile/profile_view.dart'),
      File('lib/settings/account_backup_view.dart'),
      File('lib/auth/account_store.dart'),
    ];
    final forbidden = RegExp(
      r'\b(?:Checkbox|CheckboxListTile|Switch|SwitchListTile|Radio|RadioListTile|Slider|RangeSlider|ElevatedButton|FilledButton|OutlinedButton|TextButton|IconButton|CupertinoButton|CupertinoSwitch|CupertinoCheckbox)\s*(?:<[^>]+>)?\s*\(',
    );
    final builtInIcon = RegExp(r'\b(?:Icon|CupertinoIcon)\s*\(');

    final proSource = files.first.readAsStringSync();
    expect(forbidden.allMatches(proSource), isEmpty);
    expect(builtInIcon.allMatches(proSource), isEmpty);
    expect(proSource, isNot(contains('package:flutter/material.dart')));
    expect(proSource, isNot(contains('package:flutter/cupertino.dart')));
    expect(proSource, isNot(contains('SafeArea(')));

    final backupSource = files[3].readAsStringSync();
    expect(forbidden.allMatches(backupSource), isEmpty);
    expect(builtInIcon.allMatches(backupSource), isEmpty);
    expect(backupSource, isNot(contains('package:flutter/material.dart')));
    expect(backupSource, isNot(contains('package:flutter/cupertino.dart')));
    expect(backupSource, isNot(contains('read<AccountStore>().canAddAccount')));

    final loginAddedSurface = files[1].readAsStringSync();
    expect(loginAddedSurface, contains('AppCheckbox('));
    expect(loginAddedSurface, contains('accountBackupLoginICloud'));
    expect(loginAddedSurface, contains('accountBackupLoginAndroid'));
    expect(
      loginAddedSurface,
      isNot(
        contains(
          'MaterialPageRoute<void>(builder: (_) => const MithkaProView())',
        ),
      ),
    );

    final accountSwitcherSource = files[2].readAsStringSync();
    expect(accountSwitcherSource, isNot(contains('accounts.canAddAccount')));
    expect(accountSwitcherSource, isNot(contains('MithkaProView()')));
    expect(
      accountSwitcherSource,
      contains('AppStrings.t(AppStringKeys.savedMessages)'),
    );
    expect(
      accountSwitcherSource,
      isNot(contains('AppStringKeys.chatInfoAlbum')),
    );
    expect(accountSwitcherSource, isNot(contains("'my_album_view.dart'")));
    expect(
      accountSwitcherSource,
      isNot(
        contains(
          'CupertinoPageRoute<void>(builder: (_) => const MithkaProView())',
        ),
      ),
    );

    final accountStoreSource = files[4].readAsStringSync();
    expect(accountStoreSource, isNot(contains('MithkaProService')));
    expect(accountStoreSource, isNot(contains('canAddAccount')));
    expect(accountStoreSource, contains('TdClient.shared.addSlot()'));
  });
}

class _ViewGateway implements MithkaProGateway {
  _ViewGateway({this.pro = false});

  bool pro;
  String? managedProductId;

  @override
  Future<Map<Object?, Object?>> getState() async => {
    'storeAvailable': true,
    'isPro': pro,
    'distribution': 'app_store',
    'isLimitExempt': false,
    'expirationDateMillis': null,
  };

  @override
  Future<List<Object?>> getProducts() async => [
    {
      'id': mithkaProMonthlyProductId,
      'title': 'Monthly',
      'description': '',
      'displayPrice': r'$0.69',
      'period': 'monthly',
    },
    {
      'id': mithkaProYearlyProductId,
      'title': 'Yearly',
      'description': '',
      'displayPrice': r'$4.99',
      'period': 'yearly',
    },
  ];

  @override
  Future<void> purchase(String productId) async {}

  @override
  Future<void> manage({String? productId}) async {
    managedProductId = productId;
  }

  @override
  Future<void> restore() async {}
}
