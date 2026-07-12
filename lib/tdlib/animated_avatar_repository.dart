import 'avatar_animation_index.dart';
import 'json_helpers.dart';
import 'td_client.dart';
import 'td_models.dart';

class AnimatedAvatarRepository {
  AnimatedAvatarRepository._();

  static final AnimatedAvatarRepository shared = AnimatedAvatarRepository._();

  final Map<(int, int), Future<TdFileRef?>> _cache = {};

  Future<TdFileRef?> resolve(TdFileRef staticPhoto) {
    if (!staticPhoto.hasAnimation) return Future.value();
    final slot = TdClient.shared.activeSlot;
    return _cache.putIfAbsent((
      slot,
      staticPhoto.id,
    ), () => _resolve(slot, staticPhoto));
  }

  Future<TdFileRef?> _resolve(int slot, TdFileRef staticPhoto) async {
    final owner = AvatarAnimationIndex.shared.ownerFor(slot, staticPhoto.id);
    if (owner == null || slot != TdClient.shared.activeSlot) return null;
    try {
      final photo = switch (owner.kind) {
        AvatarOwnerKind.user => await _userPhoto(owner.id, staticPhoto.photoId),
        AvatarOwnerKind.chat => await _chatPhoto(owner.id, staticPhoto.photoId),
      };
      return animatedAvatarFileFromChatPhoto(photo);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _userPhoto(int userId, int? photoId) async {
    final full = await TdClient.shared.query({
      '@type': 'getUserFullInfo',
      'user_id': userId,
    });
    return _matchingPhoto(full, photoId);
  }

  Future<Map<String, dynamic>?> _chatPhoto(int chatId, int? photoId) async {
    final chat = await TdClient.shared.query({
      '@type': 'getChat',
      'chat_id': chatId,
    });
    final type = chat.obj('type');
    final full = switch (type?.type) {
      'chatTypePrivate' || 'chatTypeSecret' => await TdClient.shared.query({
        '@type': 'getUserFullInfo',
        'user_id': type?.int64('user_id'),
      }),
      'chatTypeBasicGroup' => await TdClient.shared.query({
        '@type': 'getBasicGroupFullInfo',
        'basic_group_id': type?.int64('basic_group_id'),
      }),
      'chatTypeSupergroup' => await TdClient.shared.query({
        '@type': 'getSupergroupFullInfo',
        'supergroup_id': type?.int64('supergroup_id'),
      }),
      _ => null,
    };
    return full == null ? null : _matchingPhoto(full, photoId);
  }

  Map<String, dynamic>? _matchingPhoto(
    Map<String, dynamic> full,
    int? photoId,
  ) {
    final candidates = <Map<String, dynamic>>[
      ?full.obj('personal_photo'),
      ?full.obj('photo'),
      ?full.obj('public_photo'),
    ];
    if (photoId != null) {
      for (final photo in candidates) {
        if (photo.int64('id') == photoId) return photo;
      }
    }
    return candidates.isEmpty ? null : candidates.first;
  }
}

TdFileRef? animatedAvatarFileFromChatPhoto(Map<String, dynamic>? photo) {
  for (final key in const ['small_animation', 'animation']) {
    final animation = photo?.obj(key);
    final ref = TDParse.fileRef(animation?.obj('file'));
    if (ref != null) return ref;
  }
  return null;
}
