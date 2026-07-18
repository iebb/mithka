import 'dart:convert';
import 'dart:io';

import 'package:mithka/l10n/messages/en.dart';

/// Adds missing English fallback entries to every bundled locale table.
///
/// This keeps new UI keys safe while translators work on native wording. It
/// never overwrites an existing translation and is deterministic.
void main() {
  const files = [
    'lib/l10n/messages/zh_hans.dart',
    'lib/l10n/messages/zh_hant.dart',
    'lib/l10n/messages/ja.dart',
    'lib/l10n/messages/ko.dart',
    'lib/l10n/messages/fr.dart',
    'lib/l10n/messages/es.dart',
    'lib/l10n/messages/de.dart',
  ];
  final keyPattern = RegExp(r"^\s*'([^']+)':", multiLine: true);
  for (final path in files) {
    final file = File(path);
    var source = file.readAsStringSync();
    final existing = keyPattern
        .allMatches(source)
        .map((match) => match.group(1)!)
        .toSet();
    final missing =
        enMessages.keys.where((key) => !existing.contains(key)).toList()
          ..sort();
    if (missing.isEmpty) continue;
    final entries = StringBuffer();
    for (final key in missing) {
      final value = jsonEncode(enMessages[key]!).replaceAll(r'$', r'\$');
      entries.writeln("  '$key': $value,");
    }
    final close = source.lastIndexOf('};');
    if (close < 0) throw FormatException('No map terminator in $path');
    source = source.replaceRange(close, close, entries.toString());
    file.writeAsStringSync(source);
    stdout.writeln('$path: added ${missing.length} keys');
  }
}
