import 'json_helpers.dart';

/// Account-scoped cache of the user objects delivered by TDLib.
///
/// TDLib guarantees that [updateUser] is emitted before a user identifier is
/// exposed to the application. Keeping those objects here lets message views
/// bind sender names and avatars synchronously, including when the discovery
/// update arrived before the view was created.
class TdUserIndex {
  TdUserIndex._();

  static final TdUserIndex shared = TdUserIndex._();

  /// TDLib pushes an `updateUser` for every sender a large group exposes, and
  /// only logout used to clear them, so a session that visited a few big groups
  /// retained tens of thousands of user graphs. Every reader tolerates a miss
  /// (they fall back to a `getUser` query or a cached sender), so entries past
  /// this bound are dropped in insertion order.
  static const _capacity = 4096;

  final Map<(int, int), Map<String, dynamic>> _users = {};

  Map<String, dynamic>? userFor(int slot, int userId) => _users[(slot, userId)];

  void observe(int slot, Map<String, dynamic> object) {
    switch (object.type) {
      case 'user':
        final userId = object.int64('id');
        if (userId == null || userId == 0) return;
        // Map.unmodifiable already copies its argument; a Map.from around it
        // built a second full copy per updateUser, all of it garbage.
        _users[(slot, userId)] = Map<String, dynamic>.unmodifiable(object);
        if (_users.length > _capacity) _users.remove(_users.keys.first);
      case 'updateUser':
        final user = object.obj('user');
        if (user != null) observe(slot, user);
    }
  }

  void clearSlot(int slot) {
    _users.removeWhere((key, _) => key.$1 == slot);
  }
}
