//
//  Local premium read sites (Telegram §1.4 self-build feature): every
//  client-side premium answer for the OWN account flows through
//  LocalPremium.premiumForMe. This suite pins the wiring with source scans —
//  a new premium read that bypasses the overlay silently breaks the switch.
//

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/config/build_flags.dart';

void main() {
  if (!allowTelegramTosViolations) {
    test('skipped: this file requires I_DONT_FUCKING_CARE_ABOUT_TOS', () {});
    return;
  }

  test('every own-account premium read overlays LocalPremium', () async {
    // Each entry: a file and a substring that MUST appear beside the raw
    // read — the overlay call in place.
    final pinned = <String, List<String>>{
      // account summaries: read-time overlay, raw value cached underneath
      'lib/auth/account_store.dart': [
        'bool get premiumForView => LocalPremium.shared.premiumForMe',
        'bool get activeIsPremium =>\n      LocalPremium.shared.premiumForMe',
        'isPremium: me.boolean(\'is_premium\') ?? false,',
      ],
      // the emoji store's getOption read
      'lib/chat/emoji_store.dart': ['LocalPremium.shared.premiumForMe'],
      // folder tag entitlement
      'lib/chats/chat_folder_tag_controller.dart': [
        'LocalPremium.shared.premiumForMe',
      ],
      // chat list own badges
      'lib/chats/chat_list_view.dart': ['LocalPremium.shared.premiumForMe'],
      // own profile detail page
      'lib/profile/profile_detail_view.dart': [
        'LocalPremium.shared.premiumForMe',
      ],
      // the "我" drawer / profile view model applies the overlay at read time
      'lib/profile/profile_view.dart': [
        'bool isPremiumForView(CurrentUser? candidate)',
        'isPremium: me.boolean(\'is_premium\') ?? false,',
      ],
      // business tools entitlement
      'lib/settings/business_service.dart': [
        'LocalPremium.shared.premiumForMe',
      ],
      // edit-profile surface
      'lib/settings/edit_profile_view.dart': [
        'LocalPremium.shared.premiumForMe',
      ],
      // the desktop profile card's status button reads the summary overlay
      'lib/app/content_view.dart': ['activeAccount?.premiumForView ?? false'],
    };
    for (final entry in pinned.entries) {
      final source = File(entry.key).readAsStringSync();
      for (final needle in entry.value) {
        expect(
          source.contains(needle),
          isTrue,
          reason:
              '${entry.key} lost the LocalPremium overlay (expected "$needle")',
        );
      }
    }
  });

  test('the raw premium field never reads at display sites', () async {
    // Sites that MUST NOT read the raw field directly (the overlay getter
    // exists for them).
    final forbidden = <String, List<String>>{
      'lib/app/content_view.dart': ['activeAccount?.isPremium == true'],
    };
    for (final entry in forbidden.entries) {
      final source = File(entry.key).readAsStringSync();
      for (final needle in entry.value) {
        expect(
          source.contains(needle),
          isFalse,
          reason:
              '${entry.key} reads the raw premium field instead of the overlay',
        );
      }
    }
  });

  test('child desktop windows seed the §1.4 controllers', () async {
    final utility = File(
      'lib/app/desktop_utility_window.dart',
    ).readAsStringSync();
    expect(
      utility.contains('GhostModeController.shared.initialize(widget.prefs)'),
      isTrue,
      reason: 'the settings window reaches the kept hub; ghost mode must seed',
    );
    expect(
      utility.contains('LocalPremium.shared.initialize(widget.prefs)'),
      isTrue,
      reason: 'edit-profile and settings read premium surfaces there',
    );
  });
}
