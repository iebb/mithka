import 'dart:async';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import 'forward_options.dart';

typedef MusicPlaylistQuery =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);
typedef MusicPlaylistFolderUpdate = Map<String, dynamic>? Function();

/// Resolves a folder list that has not been pushed yet. Takes the snapshot the
/// caller already has and returns the first one that differs, or that snapshot
/// again once the wait gives up.
typedef MusicPlaylistFolderWait =
    Future<Map<String, dynamic>?> Function(Map<String, dynamic>? cached);

class MusicPlaylist {
  const MusicPlaylist({
    required this.chatId,
    required this.title,
    this.tracks = const [],
  });

  final int chatId;
  final String title;
  final List<ChatMessage> tracks;

  MusicPlaylist copyWith({List<ChatMessage>? tracks}) => MusicPlaylist(
    chatId: chatId,
    title: title,
    tracks: tracks ?? this.tracks,
  );
}

/// Stores playlists as Telegram chats inside a dedicated `_Playlist` folder.
/// Tracks are ordinary audio messages, so the library follows the account and
/// can be inspected or recovered without Mithka-specific local state.
class MusicPlaylistService {
  MusicPlaylistService({
    MusicPlaylistQuery? query,
    MusicPlaylistFolderUpdate? folderUpdate,
    this._folderWait,
  }) : _query = query ?? TdClient.shared.query,
       _folderUpdate =
           folderUpdate ?? (() => TdClient.shared.latestChatFoldersUpdate);

  static const folderTitle = '_Playlist';

  /// How long a cold folder cache is waited on before the library is read as
  /// empty. Long enough for `getDifference` to finish on a warm session, short
  /// enough that a genuinely folder-less account does not stall the sheet.
  static const folderWaitTimeout = Duration(seconds: 3);

  final MusicPlaylistQuery _query;
  final MusicPlaylistFolderUpdate _folderUpdate;
  final MusicPlaylistFolderWait? _folderWait;

  Future<List<MusicPlaylist>> loadPlaylists() async {
    final chatIds = <int>{};
    for (final folder in await _readFolders()) {
      chatIds.addAll(folder.int64Array('included_chat_ids') ?? const <int>[]);
    }
    if (chatIds.isEmpty) return const [];
    final playlists = await Future.wait(
      chatIds.map((chatId) async {
        try {
          final chat = await _query({'@type': 'getChat', 'chat_id': chatId});
          return MusicPlaylist(
            chatId: chatId,
            title: chat.str('title')?.trim().isNotEmpty == true
                ? chat.str('title')!.trim()
                : 'Playlist',
            tracks: await loadTracks(chatId),
          );
        } catch (_) {
          return null;
        }
      }),
    );
    return playlists.whereType<MusicPlaylist>().toList(growable: false);
  }

  Future<MusicPlaylist> createPlaylist(String title) async {
    final normalized = title.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(title, 'title', 'must not be empty');
    }
    // Validate the folder catalog BEFORE creating the chat: if the snapshot
    // lists a `_Playlist` folder that cannot be read, proceeding would create
    // a supergroup and then a REPLACEMENT folder — splitting the library and
    // leaving an orphaned group behind. An unreadable known folder is an
    // error, not a folder-less account.
    await _findFolderStrict();
    final chat = await _query({
      '@type': 'createNewSupergroupChat',
      'title': normalized,
      'is_forum': false,
      'is_channel': false,
      'description': '',
      'location': null,
      'message_auto_delete_time': 0,
      'for_import': false,
    });
    final chatId = chat.int64('id') ?? chat.int64('chat_id');
    if (chatId == null) {
      throw const FormatException('TDLib did not return a playlist chat');
    }
    await _includeChatInFolder(chatId);
    return MusicPlaylist(chatId: chatId, title: normalized);
  }

  Future<ChatMessage> addTrack(
    MusicPlaylist playlist,
    ChatMessage source,
  ) async {
    final music = source.music;
    final sourceChatId = source.chatId;
    if (music?.file == null) {
      throw const FormatException('Message has no playable audio');
    }
    if (sourceChatId == null || sourceChatId == 0 || source.id == 0) {
      throw const FormatException('Message has no Telegram source');
    }
    await assertForwardAllowed(
      query: _query,
      fromChatId: sourceChatId,
      messageIds: [source.id],
      options: const ForwardOptions(removeSender: true),
    );
    final sent = await _query({
      '@type': 'forwardMessages',
      'chat_id': playlist.chatId,
      'from_chat_id': sourceChatId,
      'message_ids': [source.id],
      'options': {'@type': 'messageSendOptions'},
      'send_copy': true,
      'remove_caption': false,
    });
    final parsed = (sent.objects('messages') ?? const [])
        .map(TDParse.message)
        .whereType<ChatMessage>()
        .firstOrNull;
    if (parsed?.music?.file == null) {
      throw const FormatException('TDLib did not return the playlist track');
    }
    return parsed!;
  }

  Future<void> removeTrack(MusicPlaylist playlist, ChatMessage track) async {
    if (track.id == 0) return;
    await _query({
      '@type': 'deleteMessages',
      'chat_id': playlist.chatId,
      'message_ids': [track.id],
      'revoke': true,
    });
  }

  Future<List<ChatMessage>> loadTracks(int chatId) async {
    final result = <ChatMessage>[];
    var fromMessageId = 0;
    for (var page = 0; page < 10; page++) {
      final response = await _query({
        '@type': 'searchChatMessages',
        'chat_id': chatId,
        'query': '',
        'sender_id': null,
        'from_message_id': fromMessageId,
        'offset': 0,
        'limit': 100,
        'filter': {'@type': 'searchMessagesFilterAudio'},
      });
      final messages = (response.objects('messages') ?? const [])
          .map(TDParse.message)
          .whereType<ChatMessage>()
          .toList();
      if (messages.isEmpty) break;
      result.addAll(messages);
      final oldestId = messages
          .map((message) => message.id)
          .reduce((a, b) => a < b ? a : b);
      if (messages.length < 100 || oldestId == fromMessageId) break;
      fromMessageId = oldestId;
    }
    final seen = <int>{};
    final unique = result.where((message) => seen.add(message.id)).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return unique;
  }

  /// The account's `_Playlist` folders, each already read through
  /// `getChatFolder` so callers get the authoritative `included_chat_ids`.
  ///
  /// Every matching folder is returned, ordered by id. More than one can
  /// exist, and the first alone is not enough: reading only the first left the
  /// playlists written to the other halves invisible, which is exactly how a
  /// library came to look deleted.
  ///
  /// A folder the snapshot knows about but `getChatFolder` cannot read is
  /// dropped here, not escalated: the display path must keep working when one
  /// folder is temporarily unreadable. The WRITE paths must not make the same
  /// trade — they resolve through [_readFoldersStrict] instead, because an
  /// unreadable KNOWN folder is an error state, not evidence of absence.
  Future<List<Map<String, dynamic>>> _readFolders() async {
    final ids = await _playlistFolderIds();
    final folders = <Map<String, dynamic>>[];
    for (final id in ids) {
      try {
        final folder = await _query({
          '@type': 'getChatFolder',
          'chat_folder_id': id,
        });
        folders.add({...folder, '_folder_id': id});
      } catch (_) {
        // One unreadable folder must not blank the rest of the library.
      }
    }
    return folders;
  }

  /// Resolves the WRITE target: every known `_Playlist` folder must be
  /// readable, or the catalog is not validated and no write may happen.
  ///
  /// When the snapshot lists a `_Playlist` folder but `getChatFolder` fails
  /// for it, proceeding would treat a read error as "the account has no
  /// folder" — creating a replacement folder, splitting the library, and
  /// leaving an orphaned supergroup behind. That is an error state, so this
  /// throws before any chat or folder is touched.
  Future<List<Map<String, dynamic>>> _readFoldersStrict() async {
    final ids = await _playlistFolderIds(requireSnapshot: true);
    final folders = <Map<String, dynamic>>[];
    for (final id in ids) {
      try {
        final folder = await _query({
          '@type': 'getChatFolder',
          'chat_folder_id': id,
        });
        folders.add({...folder, '_folder_id': id});
      } catch (error) {
        // The snapshot says this folder exists, so a read failure is a state
        // error, not absence. Swallowing it here is what used to mint a
        // replacement folder (and an orphaned group) on the next create.
        throw StateError('Playlist folder $id is unreadable: $error');
      }
    }
    return folders;
  }

  /// The pushed `_Playlist` folder ids, waiting for the push when TDLib has
  /// not sent one yet this session. The pushed list is authoritative for
  /// EXISTENCE; the per-folder `getChatFolder` read is authoritative for
  /// CONTENT and may fail independently.
  ///
  /// The lowest id is canonical, so a create always joins the same folder
  /// rather than starting a third one.
  Future<List<int>> _playlistFolderIds({bool requireSnapshot = false}) async {
    final ids = <int>{};
    for (final info in await _folderInfos(requireSnapshot: requireSnapshot)) {
      if (_title(info) != folderTitle) continue;
      final id = info.integer('id') ?? info.integer('chat_folder_id');
      if (id != null) ids.add(id);
    }
    return ids.toList()..sort();
  }

  /// The pushed folder list, waiting for the push when TDLib has not sent one
  /// yet this session.
  Future<List<Map<String, dynamic>>> _folderInfos({
    bool requireSnapshot = false,
  }) async {
    var snapshot = _folderUpdate();
    var infos = _infosFrom(snapshot);
    final folderWait = _folderWait;
    if (infos.isEmpty && folderWait != null) {
      // TDLib pushes `updateChatFolders` only when the folder list changes, so
      // a session that has just finished `getDifference` can still have an
      // empty cache. Reading the library in that window used to answer "no
      // playlists" — and the next create then started a second `_Playlist`
      // folder, splitting the library and hiding the half written earlier.
      // Wait for the push, bounded, before concluding anything.
      snapshot = await folderWait(snapshot);
      infos = _infosFrom(snapshot);
    }
    // A bounded wait limits how long the UI waits; it does not prove that
    // the account has no folders. Only a received snapshot can authorize
    // creation. Display reads may still return an empty loading result.
    if (requireSnapshot && snapshot == null) {
      throw StateError('Playlist folder catalog is not available yet');
    }
    return infos;
  }

  static List<Map<String, dynamic>> _infosFrom(Map<String, dynamic>? snapshot) {
    if (snapshot == null) return const <Map<String, dynamic>>[];
    return (snapshot.objects('chat_folders') ??
            snapshot.objects('chat_folder_infos') ??
            const <Map<String, dynamic>>[])
        .toList(growable: false);
  }

  static String _snapshotSignature(Map<String, dynamic>? snapshot) =>
      _infosFrom(snapshot)
          .map(
            (info) =>
                '${info.integer('id') ?? info.integer('chat_folder_id')}:'
                '${_title(info)}',
          )
          .join('|');

  /// A waiter bound to one TDLib client: returns the first folder snapshot
  /// that differs from [cached], or whatever is cached once [timeout] elapses.
  ///
  /// The pinned TDLib 1.8.69 exposes no request that lists folders, so the
  /// pushed update is the only source. This mirrors the wait the country
  /// blocker already performs for its own `_Blocked` folder.
  ///
  /// The subscription is owned and always cancelled: `firstWhere` +
  /// `Future.timeout` leaks it — a timeout completes the future but never
  /// detaches the listener, so every cold-cache wait left a subscriber on the
  /// broadcast stream for the life of the session.
  static MusicPlaylistFolderWait waiterForClient(
    int? clientId, {
    Duration timeout = folderWaitTimeout,
  }) => (cached) async {
    if (clientId == null) return cached;
    final client = TdClient.shared;
    final before = _snapshotSignature(cached);
    final current = client.latestChatFoldersUpdateForClient(clientId);
    if (_snapshotSignature(current) != before) return current;
    final completer = Completer<Map<String, dynamic>?>();
    late final StreamSubscription<Map<String, dynamic>> subscription;
    subscription = client.subscribeAll().listen((update) {
      if (completer.isCompleted) return;
      if (update.type != 'updateChatFolders') return;
      if (update.integer('@client_id') != clientId) return;
      if (_snapshotSignature(update) == before) return;
      completer.complete(update);
    });
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.complete(client.latestChatFoldersUpdateForClient(clientId));
      }
    });
    try {
      return await completer.future;
    } finally {
      timer.cancel();
      // Cancellation lands on a later microtask edge; a push arriving between
      // resolution and cancellation is dropped by the isCompleted guard.
      unawaited(subscription.cancel());
    }
  };

  /// The write-path folder resolution: strict, because treating an unreadable
  /// KNOWN folder as "no folder" would create a replacement folder and split
  /// the library. [_readFoldersStrict] throws in that case instead.
  Future<Map<String, dynamic>?> _findFolderStrict() async {
    final folders = await _readFoldersStrict();
    return folders.isEmpty ? null : folders.first;
  }

  Future<void> _includeChatInFolder(int chatId) async {
    // Chat creation is an await boundary. Re-read the folder before editing
    // it so membership changed during that request is not overwritten by
    // the earlier validation snapshot.
    final folder = await _findFolderStrict();
    if (folder == null) {
      await _query({
        '@type': 'createChatFolder',
        'folder': _folderPayload(const {}, includedChatIds: {chatId}),
      });
      return;
    }
    final folderId =
        folder.integer('_folder_id') ??
        folder.integer('id') ??
        folder.integer('chat_folder_id');
    if (folderId == null) {
      throw const FormatException('Playlist folder has no identifier');
    }
    await _editFolder(folderId, folder, chatId);
  }

  Future<void> _editFolder(
    int folderId,
    Map<String, dynamic> folder,
    int chatId,
  ) async {
    final included =
        (folder.int64Array('included_chat_ids') ?? const <int>[]).toSet()
          ..add(chatId);
    await _query({
      '@type': 'editChatFolder',
      'chat_folder_id': folderId,
      'folder': _folderPayload(folder, includedChatIds: included),
    });
  }

  static Map<String, dynamic> _folderPayload(
    Map<String, dynamic> folder, {
    required Set<int> includedChatIds,
  }) {
    final title = _title(folder).isEmpty ? folderTitle : _title(folder);
    final existingName = folder.obj('name');
    return {
      '@type': 'chatFolder',
      'name': {
        '@type': 'chatFolderName',
        'text': {
          '@type': 'formattedText',
          'text': title,
          'entities':
              existingName?.obj('text')?.objects('entities') ?? const [],
        },
        'animate_custom_emoji':
            existingName?.boolean('animate_custom_emoji') ?? false,
      },
      if (folder.obj('icon') != null) 'icon': folder.obj('icon'),
      'color_id': folder.integer('color_id') ?? -1,
      'is_shareable': false,
      'pinned_chat_ids': folder.int64Array('pinned_chat_ids') ?? const <int>[],
      'included_chat_ids': includedChatIds.toList()..sort(),
      'excluded_chat_ids':
          folder.int64Array('excluded_chat_ids') ?? const <int>[],
      'exclude_muted': folder.boolean('exclude_muted') ?? false,
      'exclude_read': folder.boolean('exclude_read') ?? false,
      'exclude_archived': folder.boolean('exclude_archived') ?? false,
      'include_contacts': false,
      'include_non_contacts': false,
      'include_bots': false,
      'include_groups': false,
      'include_channels': false,
    };
  }

  static String _title(Map<String, dynamic> object) =>
      object.str('title') ??
      object.obj('title')?.str('text') ??
      object.obj('name')?.obj('text')?.str('text') ??
      object.str('name') ??
      '';
}
