import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/settings/app_icon_controller.dart';

void main() {
  test(
    'abstract Icon Composer variants are exposed to the app icon picker',
    () {
      final variants = {
        for (final variant in AppIconVariant.values) variant.key: variant,
      };

      for (final key in ['aurora', 'prism', 'signal']) {
        final variant = variants[key];
        expect(variant, isNotNull);
        expect(File(variant!.asset).lengthSync(), greaterThan(10 * 1024));
        expect(variant.asset, endsWith('$key.png'));
      }
    },
  );

  test('abstract variants have valid native Icon Composer packages', () {
    const nativeNames = {
      'aurora': 'MithkaAurora',
      'prism': 'MithkaPrism',
      'signal': 'MithkaSignal',
    };
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    for (final entry in nativeNames.entries) {
      final package = Directory('ios/Runner/${entry.value}.icon');
      final definition = File('${package.path}/icon.json');
      final json = jsonDecode(definition.readAsStringSync()) as Map;
      final groups = json['groups'] as List;
      final layer = (groups.single as Map)['layers'] as List;
      final imageName = (layer.single as Map)['image-name'] as String;

      expect(File('${package.path}/Assets/$imageName').existsSync(), isTrue);
      expect(
        delegate,
        contains('case "${entry.key}": return "${entry.value}"'),
      );
      expect(
        delegate,
        contains('case "${entry.value}": return "${entry.key}"'),
      );
      expect(project, contains('${entry.value}.icon in Resources'));
    }
  });
}
