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

  final Map<(int, int), Map<String, dynamic>> _users = {};

  Map<String, dynamic>? userFor(int slot, int userId) => _users[(slot, userId)];

  void observe(int slot, Map<String, dynamic> object) {
    switch (object.type) {
      case 'user':
        final userId = object.int64('id');
        if (userId == null || userId == 0) return;
        _users[(slot, userId)] = Map<String, dynamic>.unmodifiable(
          Map<String, dynamic>.from(object),
        );
      case 'updateUser':
        final user = object.obj('user');
        if (user != null) observe(slot, user);
    }
  }

  void clearSlot(int slot) {
    _users.removeWhere((key, _) => key.$1 == slot);
  }
}
