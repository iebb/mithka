import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/l10n/messages/de.dart';
import 'package:mithka/l10n/messages/en.dart';
import 'package:mithka/l10n/messages/es.dart';
import 'package:mithka/l10n/messages/fr.dart';
import 'package:mithka/l10n/messages/ja.dart';
import 'package:mithka/l10n/messages/ko.dart';
import 'package:mithka/l10n/messages/zh_hans.dart';
import 'package:mithka/l10n/messages/zh_hant.dart';

void main() {
  test('diagnostic feedback copy exists in every supported locale', () {
    const tables = [
      enMessages,
      deMessages,
      esMessages,
      frMessages,
      jaMessages,
      koMessages,
      zhHansMessages,
      zhHantMessages,
    ];
    const keys = [
      AppStringKeys.aboutReportProblem,
      AppStringKeys.aboutReportProblemDetail,
      AppStringKeys.feedbackReportDescription,
      AppStringKeys.feedbackReportFailed,
      AppStringKeys.feedbackReportPlaceholder,
      AppStringKeys.feedbackReportPrivacy,
      AppStringKeys.feedbackReportSend,
      AppStringKeys.feedbackReportSending,
      AppStringKeys.feedbackReportSent,
      AppStringKeys.feedbackReportTitle,
    ];

    for (final table in tables) {
      for (final key in keys) {
        expect(table[key]?.trim(), isNotEmpty, reason: 'missing $key');
      }
      expect(table[AppStringKeys.feedbackReportSent], contains('{value1}'));
    }
  });
}
