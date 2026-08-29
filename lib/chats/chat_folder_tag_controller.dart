//
//  chat_folder_tag_controller.dart
//
//  文件夹标签 — the folder names drawn on a chat-list row, between the chat's
//  name and its message preview.
//
//  Telegram puts `toggleChatFolderTags` behind Premium, so the preference has
//  two homes: a Premium account writes it to the server the way every other
//  client does, and everyone else keeps it on this device. Drawing the tags is
//  local either way, so a non-Premium account loses only the cross-device sync
//  it was never entitled to.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../theme/app_theme.dart';

/// Telegram's folder palette, indexed by `chatFolderInfo.color_id`.
const List<Color> chatFolderTagColors = [
  Color(0xFFE85D5D),
  Color(0xFFF09A44),
  Color(0xFF8C6AD8),
  Color(0xFF57A957),
  Color(0xFF45AEB8),
  Color(0xFF4B8CD8),
  Color(0xFFD85C9D),
];

/// Null for a folder that carries no colour of its own (`color_id` -1), which
/// the row then draws in the app accent.
Color? chatFolderTagColor(int colorId) =>
    colorId >= 0 && colorId < chatFolderTagColors.length
    ? chatFolderTagColors[colorId]
    : null;

/// One folder as it is drawn on a chat row.
@immutable
class ChatFolderTag {
  const ChatFolderTag({
    required this.id,
    required this.title,
    required this.color,
  });

  final int id;
  final String title;
  final Color? color;

  @override
  bool operator ==(Object other) =>
      other is ChatFolderTag &&
      other.id == id &&
      other.title == title &&
      other.color == color;

  @override
  int get hashCode => Object.hash(id, title, color);
}

typedef ChatFolderTagQuery =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

class ChatFolderTagController extends ChangeNotifier {
  ChatFolderTagController(
    this._preferences, {
    ChatFolderTagQuery? query,
    Stream<Map<String, dynamic>>? folderUpdates,
    Map<String, dynamic>? initialFolders,
  }) : _query = query ?? TdClient.shared.query {
    _enabled = _preferences?.getBool(preferenceKey) ?? false;
    final seed =
        initialFolders ??
        (folderUpdates == null
            ? TdClient.shared.latestChatFoldersUpdate
            : null);
    if (seed != null) _applyFolders(seed, notify: false);
    _updates = (folderUpdates ?? TdClient.shared.updatesOf('updateChatFolders'))
        .listen(_applyFolders);
  }

  /// Named after Telegram's own setting so the local mirror is recognisable in
  /// a preferences dump, even though only Premium accounts get the server one.
  static const preferenceKey = 'mithka.chatFolderTags.v1';

  final SharedPreferences? _preferences;
  final ChatFolderTagQuery _query;
  StreamSubscription<Map<String, dynamic>>? _updates;

  Map<int, ChatFolderTag> _folders = const {};
  bool _enabled = false;
  bool _isPremium = false;

  /// The server's own `are_tags_enabled`, once TDLib has reported it. Only a
  /// Premium account is allowed to change it, so it is a read-only hint for
  /// everyone else.
  bool? _serverEnabled;

  /// Whether rows should draw folder tags at all.
  bool get enabled => _enabled;

  /// True once TDLib confirms Premium; decides where [setEnabled] writes.
  bool get isPremium => _isPremium;

  /// Every folder the account has, by id, in the account's own folder order.
  Map<int, ChatFolderTag> get folders => _folders;

  /// The tags for one chat. Empty while the preference is off, so a row can
  /// call this unconditionally.
  List<ChatFolderTag> tagsFor(Set<int> folderIds) {
    if (!_enabled || _folders.isEmpty || folderIds.isEmpty) {
      return const <ChatFolderTag>[];
    }
    return [
      for (final entry in _folders.entries)
        if (folderIds.contains(entry.key)) entry.value,
    ];
  }

  /// Reads Premium entitlement, then adopts the server's setting for a Premium
  /// account and this device's for everyone else.
  Future<void> refresh() async {
    final isPremium = await _optionBool('is_premium') ?? false;
    final enabled = isPremium
        ? (_serverEnabled ?? _preferences?.getBool(preferenceKey) ?? false)
        : _preferences?.getBool(preferenceKey) ?? false;
    if (_isPremium == isPremium && _enabled == enabled) return;
    _isPremium = isPremium;
    _enabled = enabled;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    // The device preference is written for every account, Premium included:
    // it is what the next launch reads before TDLib has answered.
    await _preferences?.setBool(preferenceKey, value);
    if (!_isPremium) return;
    try {
      await _query({
        '@type': 'toggleChatFolderTags',
        'are_tags_enabled': value,
      });
    } catch (_) {
      // The device preference already holds the user's choice; a server that
      // refuses the write must not undo what they just asked for.
    }
  }

  void _applyFolders(Map<String, dynamic> update, {bool notify = true}) {
    final raw =
        update.objects('chat_folders') ??
        update.objects('chat_folder_infos') ??
        const <Map<String, dynamic>>[];
    final folders = <int, ChatFolderTag>{};
    for (final folder in raw) {
      final id = folder.integer('id') ?? folder.integer('chat_folder_id');
      if (id == null) continue;
      final title =
          folder.obj('name')?.obj('text')?.str('text') ??
          folder.obj('title')?.str('text') ??
          folder.str('title') ??
          '';
      if (title.trim().isEmpty) continue;
      folders[id] = ChatFolderTag(
        id: id,
        title: title,
        color: chatFolderTagColor(folder.integer('color_id') ?? -1),
      );
    }

    final serverEnabled = update.boolean('are_tags_enabled');
    var changed = false;
    if (serverEnabled != null && serverEnabled != _serverEnabled) {
      _serverEnabled = serverEnabled;
      // Only a Premium account's server value is authoritative; a locked one
      // is always false and would silently undo the local choice.
      if (_isPremium && _enabled != serverEnabled) {
        _enabled = serverEnabled;
        changed = true;
      }
    }
    if (!_sameFolders(folders)) {
      _folders = folders;
      changed = true;
    }
    if (changed && notify) notifyListeners();
  }

  bool _sameFolders(Map<int, ChatFolderTag> next) {
    if (next.length != _folders.length) return false;
    for (final entry in next.entries) {
      if (_folders[entry.key] != entry.value) return false;
    }
    return true;
  }

  Future<bool?> _optionBool(String name) async {
    try {
      final option = await _query({'@type': 'getOption', 'name': name});
      return option.boolean('value');
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    unawaited(_updates?.cancel());
    _updates = null;
    super.dispose();
  }
}

/// The chat-list row extent, told whether rows are currently drawing a folder
/// tag line. Everything that virtualizes against the extent has to agree with
/// the row itself, so they all read it from here rather than each deciding.
///
/// Pass `listen: false` outside a build — a scroll callback, a tap handler.
double chatListRowExtentFor(BuildContext context, {bool listen = true}) =>
    AppMetric.chatListRowExtent(
      context,
      null,
      (listen
                  ? context.watch<ChatFolderTagController?>()
                  : context.read<ChatFolderTagController?>())
              ?.enabled ??
          false,
    );
