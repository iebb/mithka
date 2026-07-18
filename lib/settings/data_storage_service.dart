import '../tdlib/td_client.dart';

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
  const DataStorageService([this._client]);

  final TdClient? _client;
  TdClient get client => _client ?? TdClient.shared;

  Future<Map<String, dynamic>> storageStatistics({int chatLimit = 100}) =>
      client.query({'@type': 'getStorageStatistics', 'chat_limit': chatLimit});

  Future<Map<String, dynamic>> optimize({
    required int size,
    required int ttl,
    List<Map<String, dynamic>> fileTypes = const [],
    List<int> chatIds = const [],
    List<int> excludeChatIds = const [],
    bool returnDeletedStatistics = false,
  }) => client.query(
    buildOptimizeStorageRequest(
      size: size,
      ttl: ttl,
      fileTypes: fileTypes,
      chatIds: chatIds,
      excludeChatIds: excludeChatIds,
      returnDeletedStatistics: returnDeletedStatistics,
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
  }) => client.query(
    buildSearchDownloadsRequest(
      query: query,
      onlyActive: onlyActive,
      onlyCompleted: onlyCompleted,
      offset: offset,
    ),
  );

  Future<void> toggleDownload(int fileId, {required bool paused}) async {
    await client.query({
      '@type': 'toggleDownloadIsPaused',
      'file_id': fileId,
      'is_paused': paused,
    });
  }

  Future<void> toggleAllDownloads({required bool paused}) async {
    await client.query({
      '@type': 'toggleAllDownloadsArePaused',
      'are_paused': paused,
    });
  }

  Future<void> removeDownload(
    int fileId, {
    bool deleteFromCache = false,
  }) async {
    await client.query({
      '@type': 'removeFileFromDownloads',
      'file_id': fileId,
      'delete_from_cache': deleteFromCache,
    });
  }

  Future<void> clearDownloads({
    required bool active,
    required bool completed,
    bool deleteFromCache = false,
  }) async {
    await client.query({
      '@type': 'removeAllFilesFromDownloads',
      'only_active': active,
      'only_completed': completed,
      'delete_from_cache': deleteFromCache,
    });
  }
}
