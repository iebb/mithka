enum ProfileIdentityKind { phoneNumber, telegramId, username }

typedef ProfileIdentityLine = ({
  ProfileIdentityKind kind,
  String text,
  String copyText,
});

/// The identity rows under a name on a profile page.
///
/// [text] is what the row shows, [copyText] what the clipboard gets when it is
/// tapped: the same value without its on-screen decoration, because a grouped
/// phone number or a `TG:` prefix is not what a phone field, a bot command or
/// a mention wants. [rawPhone] is TDLib's undecorated number and only feeds the
/// copy value — [formattedPhone] stays the displayed one.
List<ProfileIdentityLine> fullProfileIdentityLines({
  required String formattedPhone,
  required List<String> usernames,
  required int userId,
  String rawPhone = '',
  bool hidePhone = false,
}) => [
  if (!hidePhone && formattedPhone.isNotEmpty)
    (
      kind: ProfileIdentityKind.phoneNumber,
      text: formattedPhone,
      copyText: e164PhoneNumber(rawPhone) ?? formattedPhone,
    ),
  if (userId > 0)
    (
      kind: ProfileIdentityKind.telegramId,
      text: 'TG: $userId',
      copyText: '$userId',
    ),
  for (final username in usernames)
    (
      kind: ProfileIdentityKind.username,
      text: '@$username',
      copyText: '@$username',
    ),
];

/// `+<digits>` for a pastable phone number, or null when [raw] has no digits.
String? e164PhoneNumber(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  return digits.isEmpty ? null : '+$digits';
}
