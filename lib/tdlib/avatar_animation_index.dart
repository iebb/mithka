import 'json_helpers.dart';

enum AvatarOwnerKind { user, chat }

class AvatarOwner {
  const AvatarOwner(this.kind, this.id);

  final AvatarOwnerKind kind;
  final int id;
}

/// Associates a profile-photo file with its owner without changing every
/// avatar call site. TDLib file ids are scoped to an account slot.
class AvatarAnimationIndex {
  AvatarAnimationIndex._();

  static final AvatarAnimationIndex shared = AvatarAnimationIndex._();

  final Map<(int, int), AvatarOwner> _owners = {};

  AvatarOwner? ownerFor(int slot, int fileId) => _owners[(slot, fileId)];

  void observe(int slot, Map<String, dynamic> object) {
    switch (object.type) {
      case 'user':
        _record(
          slot,
          object.obj('profile_photo'),
          AvatarOwner(AvatarOwnerKind.user, object.int64('id') ?? 0),
        );
      case 'chat':
        _record(
          slot,
          object.obj('photo'),
          AvatarOwner(AvatarOwnerKind.chat, object.int64('id') ?? 0),
        );
      case 'updateUser':
        final user = object.obj('user');
        if (user != null) observe(slot, user);
      case 'updateChatPhoto':
        _record(
          slot,
          object.obj('photo'),
          AvatarOwner(AvatarOwnerKind.chat, object.int64('chat_id') ?? 0),
        );
      case 'users':
        for (final user in object.objects('users') ?? const []) {
          observe(slot, user);
        }
      case 'chats':
        for (final chat in object.objects('chats') ?? const []) {
          observe(slot, chat);
        }
    }
  }

  void _record(int slot, Map<String, dynamic>? photo, AvatarOwner owner) {
    if (owner.id == 0 || photo == null) return;
    if (!(photo.boolean('has_animation') ?? false)) return;
    final fileId = photo.obj('small')?.integer('id');
    if (fileId == null || fileId == 0) return;
    _owners[(slot, fileId)] = owner;
  }
}
