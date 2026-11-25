//
//  local_folder_order_store.dart
//
//  The "All chats" tab position on this device when Premium is simulated
//  locally. `reorderChatFolders.main_chat_list_position` is a Premium-only
//  server field: TDLib clamps it to 0 for every account it does not consider
//  Premium, and the local-premium switch is display-only, so the position it
//  unlocks has to live in this app's preference store.
//
//  With local premium off the store is inert: nothing is read, written or
//  exposed, and the server's position wins again. Entries are keyed by the
//  stable Telegram user id, because folder ids are account-scoped.
//

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../settings/local_premium.dart';

class LocalFolderOrderStore extends ChangeNotifier {
  LocalFolderOrderStore();

  /// The app-wide store; the chat list model, the order sheet and the
  /// settings page all read the same positions.
  static final LocalFolderOrderStore shared = LocalFolderOrderStore();

  static const String _prefix = 'mithka.folderOrder.mainPosition.v1.user';

  SharedPreferences? _prefs;
  final Map<int, int> _positions = {};
  bool _listening = false;

  void initialize(SharedPreferences prefs) {
    _prefs = prefs;
    if (_listening) return;
    _listening = true;
    // Turning local premium off must put the server's position back on the
    // tab strip immediately, even before the next getMe/updateChatFolders.
    LocalPremium.shared.addListener(_handlePremiumChanged);
  }

  void _handlePremiumChanged() => notifyListeners();

  /// The locally chosen position for [userId], or null while local premium is
  /// off or this account has never moved the main list.
  int? positionFor(int? userId) {
    if (userId == null || !LocalPremium.shared.enabled) return null;
    final cached = _positions[userId];
    if (cached != null) return cached;
    final stored = _prefs?.getInt('$_prefix$userId');
    if (stored != null) _positions[userId] = stored;
    return stored;
  }

  /// Remembers [position] for this account. Inert without local premium, so a
  /// real-Premium account keeps using the server's copy.
  Future<void> setPosition(int? userId, int position) async {
    if (userId == null || !LocalPremium.shared.enabled) return;
    if (_positions[userId] == position) return;
    _positions[userId] = position;
    notifyListeners();
    await _prefs?.setInt('$_prefix$userId', position);
  }

  /// Drops an override, e.g. when its folder no longer exists.
  Future<void> clearPosition(int? userId) async {
    if (userId == null) return;
    final hadMemory = _positions.remove(userId) != null;
    final key = '$_prefix$userId';
    final hadPreference = _prefs?.containsKey(key) ?? false;
    if (!hadMemory && !hadPreference) return;
    notifyListeners();
    await _prefs?.remove(key);
  }

  @visibleForTesting
  void clearForTesting() {
    _positions.clear();
  }
}
