import 'dart:io';

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
  const contactManagementKeys = <String>{
    AppStringKeys.profileContactManagementAddContact,
    AppStringKeys.profileContactManagementBirthdateSuggestionSent,
    AppStringKeys.profileContactManagementContactAddedValue1,
    AppStringKeys.profileContactManagementContactDetails,
    AppStringKeys.profileContactManagementContactDetailsSubtitle,
    AppStringKeys.profileContactManagementContactListSection,
    AppStringKeys.profileContactManagementContactNote,
    AppStringKeys.profileContactManagementContactRemovedValue1,
    AppStringKeys.profileContactManagementContactSection,
    AppStringKeys.profileContactManagementContactUpdated,
    AppStringKeys.profileContactManagementDay,
    AppStringKeys.profileContactManagementDeleteFromContacts,
    AppStringKeys.profileContactManagementEditContact,
    AppStringKeys.profileContactManagementMonth,
    AppStringKeys.profileContactManagementNoteRemoved,
    AppStringKeys.profileContactManagementNoteSaved,
    AppStringKeys.profileContactManagementNoteVisibleOnly,
    AppStringKeys.profileContactManagementOnlyYouCanSeeIt,
    AppStringKeys.profileContactManagementPersonalPhotoDescription,
    AppStringKeys.profileContactManagementPersonalPhotoRemoved,
    AppStringKeys.profileContactManagementPersonalPhotoUpdated,
    AppStringKeys.profileContactManagementPhoneShared,
    AppStringKeys.profileContactManagementPhotoCurrent,
    AppStringKeys.profileContactManagementPhotoPersonal,
    AppStringKeys.profileContactManagementPhotoPublic,
    AppStringKeys.profileContactManagementPhotoSuggestionSent,
    AppStringKeys.profileContactManagementPrivacyExceptionSubtitleValue1,
    AppStringKeys.profileContactManagementPrivateNote,
    AppStringKeys.profileContactManagementProfileSuggestionsSection,
    AppStringKeys.profileContactManagementRemoveContact,
    AppStringKeys.profileContactManagementRemoveContactMessage,
    AppStringKeys.profileContactManagementRemoveContactRow,
    AppStringKeys.profileContactManagementRemovePersonalPhoto,
    AppStringKeys.profileContactManagementReturnOriginalPhotoValue1,
    AppStringKeys.profileContactManagementSetPersonalPhotoValue1,
    AppStringKeys.profileContactManagementSharePhone,
    AppStringKeys.profileContactManagementSharePhoneMessage,
    AppStringKeys.profileContactManagementSharePhonePrivacyExceptionValue1,
    AppStringKeys.profileContactManagementShareYourPhoneNumber,
    AppStringKeys.profileContactManagementSuggestBirthdate,
    AppStringKeys.profileContactManagementSuggestBirthdateDescriptionValue1,
    AppStringKeys.profileContactManagementSuggestProfilePhotoDescriptionValue1,
    AppStringKeys.profileContactManagementSuggestProfilePhotoValue1,
    AppStringKeys.profileContactManagementTitle,
    AppStringKeys.profileContactManagementYear,
  };

  test('contact management has a fallback in every supported locale', () {
    const localeTables = <String, Map<String, String>>{
      'en': enMessages,
      'de': deMessages,
      'es': esMessages,
      'fr': frMessages,
      'ja': jaMessages,
      'ko': koMessages,
      'zhHans': zhHansMessages,
      'zhHant': zhHantMessages,
    };

    for (final locale in localeTables.entries) {
      for (final key in contactManagementKeys) {
        expect(
          locale.value[key],
          isNotNull,
          reason: '${locale.key} is missing $key',
        );
        expect(
          locale.value[key],
          isNot(equals(key)),
          reason: '${locale.key} exposes the key $key',
        );
      }
    }
  });

  test('contact management placeholder contracts match every locale', () {
    const localeTables = <Map<String, String>>[
      enMessages,
      deMessages,
      esMessages,
      frMessages,
      jaMessages,
      koMessages,
      zhHansMessages,
      zhHantMessages,
    ];
    final placeholderKeys = contactManagementKeys.where(
      (key) => key.endsWith('Value1'),
    );

    for (final table in localeTables) {
      for (final key in placeholderKeys) {
        expect(table[key], contains('{value1}'), reason: key);
      }
    }
  });

  test('contact management surfaces contain no original English literals', () {
    final managementSource = File(
      'lib/profile/profile_contact_management_view.dart',
    ).readAsStringSync();
    final detailSource = File(
      'lib/profile/profile_detail_view.dart',
    ).readAsStringSync();
    const originalLabels = <String>[
      'Contact tools',
      'Contact updated',
      'Contact added',
      'Contact removed',
      'Phone number shared',
      'Only you can see this note',
      'Note removed',
      'Note saved',
      'Personal photo updated',
      'Personal photo removed',
      'Photo suggestion sent',
      'Birthdate suggestion sent',
      'Edit contact',
      'Add contact',
      'Share my phone number',
      'Private note',
      'Set personal photo',
      'Remove personal photo',
      'Suggest profile photo',
      'Suggest birthdate',
      'Remove contact',
      'First name',
      'Last name',
      'Phone number',
    ];

    for (final label in originalLabels) {
      expect(managementSource, isNot(contains("'$label'")), reason: label);
      expect(detailSource, isNot(contains("'$label'")), reason: label);
    }
  });
}
