//
//  gif_preview.dart
//
//  Loops a visible saved GIF/MP4 animation and keeps its thumbnail on screen
//  while TDLib downloads or initializes the animation file.
//

import 'package:flutter/material.dart';

import 'gif_item.dart';
import 'looping_video_view.dart';

class GifPreview extends StatelessWidget {
  const GifPreview({super.key, required this.item});

  final GifItem item;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LoopingVideoView(
        file: item.file,
        fallback: item.thumbnail ?? item.file,
        fit: BoxFit.cover,
      ),
    );
  }
}
