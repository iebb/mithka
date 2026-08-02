enum ProfileIdentityKind { phoneNumber, telegramId, username }

typedef ProfileIdentityLine = ({ProfileIdentityKind kind, String text});

List<ProfileIdentityLine> fullProfileIdentityLines({
  required String formattedPhone,
  required List<String> usernames,
  required int userId,
  bool hidePhone = false,
}) => [
  if (!hidePhone && formattedPhone.isNotEmpty)
    (kind: ProfileIdentityKind.phoneNumber, text: formattedPhone),
  if (userId > 0) (kind: ProfileIdentityKind.telegramId, text: 'TG: $userId'),
  for (final username in usernames)
    (kind: ProfileIdentityKind.username, text: '@$username'),
];
