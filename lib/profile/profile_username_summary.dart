List<String> compactProfileUsernameLabels(List<String> usernames) {
  if (usernames.isEmpty) return const [];
  return [
    '@${usernames.first}',
    if (usernames.length > 1) '+${usernames.length - 1}',
  ];
}
