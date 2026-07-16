Map<String, dynamic>? animatedProfilePhotoRequest({
  required bool isPremium,
  required String path,
}) {
  if (!isPremium || path.isEmpty) return null;
  return {
    '@type': 'setProfilePhoto',
    'photo': {
      '@type': 'inputChatPhotoAnimation',
      'animation': {'@type': 'inputFileLocal', 'path': path},
      'main_frame_timestamp': 0.0,
    },
    'is_public': false,
  };
}
