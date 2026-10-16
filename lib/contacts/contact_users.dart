//
//  contact_users.dart
//
//  Loads the account's contact list together with each contact's TDLib user.
//

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';

/// Runs [request] against the account that owns [accountSlot].
///
/// Contacts are account-scoped exactly like chat ids: a view that keeps
/// running for the account it was opened from must not re-resolve whichever
/// account happens to be active by the time the request goes out. A null
/// [accountSlot] keeps the historical active-account behaviour.
Future<Map<String, dynamic>> _queryAccount(
  TdClient client,
  int? accountSlot,
  Map<String, dynamic> request,
) => accountSlot == null
    ? client.query(request)
    : client.queryForSlot(request, accountSlot);

/// The first [limit] contacts with their `user` objects, in contact-list
/// order. The `getUser` lookups run concurrently instead of one round trip at
/// a time; a contact whose user fails to load is left out.
Future<List<(int, TdObject)>> fetchContactUsers(
  TdClient client, {
  int? limit,
  int? accountSlot,
}) async {
  final result = await _queryAccount(client, accountSlot, {
    '@type': 'getContacts',
  });
  Iterable<int> ids = result.int64Array('user_ids') ?? const <int>[];
  if (limit != null) ids = ids.take(limit);
  final users = await Future.wait(
    ids.map((id) async {
      try {
        return (
          id,
          await _queryAccount(client, accountSlot, {
            '@type': 'getUser',
            'user_id': id,
          }),
        );
      } catch (_) {
        return null;
      }
    }),
  );
  return users.nonNulls.toList(growable: false);
}

/// A picker row for [user], with its editable username.
Contact contactFromUser(int id, TdObject user) => Contact(
  id: id,
  name: TDParse.userName(user),
  username: user.obj('usernames')?.str('editable_username'),
  statusText: TDParse.userStatus(user),
  photo: TDParse.smallPhoto(user.obj('profile_photo')),
  isOnline: TDParse.isUserOnline(user),
);

/// [fetchContactUsers] as picker rows sorted by name.
Future<List<Contact>> fetchSortedContacts(
  TdClient client, {
  int? limit,
  int? accountSlot,
}) async {
  final users = await fetchContactUsers(
    client,
    limit: limit,
    accountSlot: accountSlot,
  );
  return [for (final (id, user) in users) contactFromUser(id, user)]
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}
