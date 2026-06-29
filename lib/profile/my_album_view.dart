//
//  my_album_view.dart
//
//  我的相册: a grid of the current user's profile photos (getUserProfilePhotos),
//  mapped from the reference app's personal album. Tap a photo to view it full-screen.
//

import 'package:flutter/material.dart';

import '../chat/full_image_viewer.dart';
import '../components/photo_avatar.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';

class MyAlbumView extends StatefulWidget {
  const MyAlbumView({super.key, required this.userId});
  final int userId;

  @override
  State<MyAlbumView> createState() => _MyAlbumViewState();
}

class _MyAlbumViewState extends State<MyAlbumView> {
  final TdClient _client = TdClient.shared;
  List<TdFileRef> _photos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _client.query({
        '@type': 'getUserProfilePhotos',
        'user_id': widget.userId,
        'offset': 0,
        'limit': 100,
      });
      final photos = <TdFileRef>[];
      for (final p in res.objects('photos') ?? const <Map<String, dynamic>>[]) {
        final sizes = p.objects('sizes');
        if (sizes == null || sizes.isEmpty) continue;
        // Largest available size is last.
        final ref = TDParse.fileRef(sizes.last.obj('photo'));
        if (ref != null) photos.add(ref);
      }
      _photos = photos;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          _header(),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _header() {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: FaIcon(
                    FontAwesomeIcons.chevronLeft,
                    size: 22,
                    color: c.textPrimary,
                  ),
                ),
              ),
            ),
            Text(
              '相册',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    final c = context.colors;
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator.adaptive(strokeWidth: 2),
        ),
      );
    }
    if (_photos.isEmpty) {
      return Center(
        child: Text(
          '暂无照片',
          style: TextStyle(fontSize: 14, color: c.textSecondary),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: _photos.length,
      itemBuilder: (context, i) => GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => FullImageViewer(items: _photos, startIndex: i),
          ),
        ),
        child: TDImage(photo: _photos[i]),
      ),
    );
  }
}
