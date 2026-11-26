import '../../tdlib/td_client.dart';

Map<String, dynamic> buildOptimizeStorageRequest({
  required int size,
  required int ttl,
  int count = 1000000000,
  int immunityDelay = 3600,
  List<Map<String, dynamic>> fileTypes = const [],
  List<int> chatIds = const [],
  List<int> excludeChatIds = const [],
  bool returnDeletedStatistics = false,
  int chatLimit = 100,
}) => {
  '@type': 'optimizeStorage',
  'size': size,
  'ttl': ttl,
  'count': count,
  'immunity_delay': immunityDelay,
  'file_types': fileTypes,
  'chat_ids': chatIds,
  'exclude_chat_ids': excludeChatIds,
  'return_deleted_file_statistics': returnDeletedStatistics,
  'chat_limit': chatLimit,
};

Map<String, dynamic> buildSearchDownloadsRequest({
  String query = '',
  bool onlyActive = false,
  bool onlyCompleted = false,
  String offset = '',
  int limit = 100,
}) => {
  '@type': 'searchFileDownloads',
  'query': query,
  'only_active': onlyActive,
  'only_completed': onlyCompleted,
  'offset': offset,
  'limit': limit,
};

class DataStorageService {
  const DataStorageService([this._client, this.accountSlot]);

  final TdClient? _client;
  final int? accountSlot;
  TdClient get client => _client ?? TdClient.shared;

  Future<Map<String, dynamic>> fastStorageStatistics() =>
      client.query({'@type': 'getStorageStatisticsFast'});

  Future<Map<String, dynamic>> storageStatistics({int chatLimit = 100}) =>
      client.query({'@type': 'getStorageStatistics', 'chat_limit': chatLimit});

  Future<Map<String, dynamic>> chat(int chatId) =>
      client.query({'@type': 'getChat', 'chat_id': chatId});

  Future<Map<String, dynamic>> optimize({
    required int size,
    required int ttl,
    List<Map<String, dynamic>> fileTypes = const [],
    List<int> chatIds = const [],
    List<int> excludeChatIds = const [],
    bool returnDeletedStatistics = false,
    int count = 1000000000,
    int immunityDelay = 3600,
    int chatLimit = 100,
  }) => client.query(
    buildOptimizeStorageRequest(
      size: size,
      ttl: ttl,
      count: count,
      immunityDelay: immunityDelay,
      fileTypes: fileTypes,
      chatIds: chatIds,
      excludeChatIds: excludeChatIds,
      returnDeletedStatistics: returnDeletedStatistics,
      chatLimit: chatLimit,
    ),
  );

  Future<Map<String, dynamic>> networkStatistics({bool currentOnly = false}) =>
      client.query({
        '@type': 'getNetworkStatistics',
        'only_current': currentOnly,
      });

  Future<void> resetNetworkStatistics() async {
    await client.query({'@type': 'resetNetworkStatistics'});
  }

  Future<Map<String, dynamic>> searchDownloads({
    String query = '',
    bool onlyActive = false,
    bool onlyCompleted = false,
    String offset = '',
  }) => client.queryForSlot(
    buildSearchDownloadsRequest(
      query: query,
      onlyActive: onlyActive,
      onlyCompleted: onlyCompleted,
      offset: offset,
    ),
    accountSlot ?? client.activeSlot,
  );

  /// Only explicit whole-file downloads belong in the persistent task list.
  /// Playback ranges and automatic previews must not register here.
  Future<Map<String, dynamic>> addDownload({
    required int fileId,
    required int chatId,
    required int messageId,
  }) => client.queryForSlot({
    '@type': 'addFileToDownloads',
    'file_id': fileId,
    'chat_id': chatId,
    'message_id': messageId,
    'priority': 32,
  }, accountSlot ?? client.activeSlot);

  Future<void> toggleDownload(int fileId, {required bool paused}) async {
    await client.queryForSlot({
      '@type': 'toggleDownloadIsPaused',
      'file_id': fileId,
      'is_paused': paused,
    }, accountSlot ?? client.activeSlot);
  }

  /// A whole-file task and a playback range can both own the same transfer.
  /// Explicit pause stops both, without removing already cached bytes.
  Future<void> pauseDownload(int fileId) async {
    try {
      await toggleDownload(fileId, paused: true);
    } on TdError catch (error) {
      // Playback-only files have no managed task. Other errors must surface.
      if (error.code != 400 || error.message != "Can't find file") rethrow;
    }
    await client.queryForSlot({
      '@type': 'cancelDownloadFile',
      'file_id': fileId,
      'only_if_pending': false,
    }, accountSlot ?? client.activeSlot);
  }

  Future<void> toggleAllDownloads({required bool paused}) async {
    await client.queryForSlot({
      '@type': 'toggleAllDownloadsArePaused',
      'are_paused': paused,
    }, accountSlot ?? client.activeSlot);
  }

  Future<void> removeDownload(
    int fileId, {
    bool deleteFromCache = false,
  }) async {
    await client.queryForSlot({
      '@type': 'removeFileFromDownloads',
      'file_id': fileId,
      'delete_from_cache': deleteFromCache,
    }, accountSlot ?? client.activeSlot);
  }

  Future<void> clearDownloads({
    required bool active,
    required bool completed,
    bool deleteFromCache = false,
  }) async {
    await client.queryForSlot({
      '@type': 'removeAllFilesFromDownloads',
      'only_active': active,
      'only_completed': completed,
      'delete_from_cache': deleteFromCache,
    }, accountSlot ?? client.activeSlot);
  }
}
