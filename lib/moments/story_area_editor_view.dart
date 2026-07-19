import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../theme/app_theme.dart';
import 'story_service.dart';

StoryAreaPositionDraft applyStoryAreaGesture({
  required StoryAreaPositionDraft initial,
  required Offset movement,
  required Size canvasSize,
  double scale = 1,
  double rotationRadians = 0,
}) {
  if (canvasSize.width <= 0 || canvasSize.height <= 0) return initial;
  final width = (initial.widthPercentage * scale).clamp(8.0, 95.0);
  final height = (initial.heightPercentage * scale).clamp(5.0, 60.0);
  final halfWidth = width / 2;
  final halfHeight = height / 2;
  final x = (initial.xPercentage + movement.dx / canvasSize.width * 100).clamp(
    halfWidth,
    100 - halfWidth,
  );
  final y = (initial.yPercentage + movement.dy / canvasSize.height * 100).clamp(
    halfHeight,
    100 - halfHeight,
  );
  var rotation =
      initial.rotationAngle + rotationRadians * 180 / 3.141592653589793;
  rotation %= 360;
  if (rotation < 0) rotation += 360;
  return initial.copyWith(
    xPercentage: x,
    yPercentage: y,
    widthPercentage: width,
    heightPercentage: height,
    rotationAngle: rotation,
  );
}

class StoryAreaEditorView extends StatefulWidget {
  const StoryAreaEditorView({
    super.key,
    required this.areas,
    this.mediaPath,
    this.isVideo = false,
  });

  final List<StoryAreaDraft> areas;
  final String? mediaPath;
  final bool isVideo;

  @override
  State<StoryAreaEditorView> createState() => _StoryAreaEditorViewState();
}

class _StoryAreaEditorViewState extends State<StoryAreaEditorView> {
  late final List<StoryAreaDraft> _areas = [...widget.areas];
  int _selected = 0;
  StoryAreaPositionDraft? _gestureStartPosition;
  Offset? _gestureStartFocalPoint;
  Size _canvasSize = Size.zero;

  void _done() =>
      Navigator.of(context).pop(List<StoryAreaDraft>.unmodifiable(_areas));

  void _removeSelected() {
    if (_areas.isEmpty) return;
    setState(() {
      _areas.removeAt(_selected);
      _selected = _areas.isEmpty ? 0 : _selected.clamp(0, _areas.length - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.groupedBackground,
      child: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.storyAreaEditorArrangeStoryAreas),
            onBack: () => Navigator.of(context).pop(),
            trailing: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _done,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(
                  AppStrings.t(AppStringKeys.addMembersDone),
                  style: TextStyle(
                    color: AppTheme.brand,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Center(
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      _canvasSize = constraints.biggest;
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _background(),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.22),
                                ),
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            for (var i = 0; i < _areas.length; i++)
                              _area(i, constraints.biggest),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          Container(
            color: c.background,
            padding: EdgeInsets.fromLTRB(
              14,
              10,
              14,
              MediaQuery.paddingOf(context).bottom + 12,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppStrings.t(
                    AppStringKeys.storyAreaEditorDragToMovePinchToResizeTwistTo,
                  ),
                  style: TextStyle(color: c.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 9),
                if (_areas.isNotEmpty)
                  SizedBox(
                    height: 38,
                    child: Row(
                      children: [
                        Expanded(
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _areas.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 7),
                            itemBuilder: (context, index) => GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => setState(() => _selected = index),
                              child: Container(
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 11,
                                ),
                                decoration: BoxDecoration(
                                  color: index == _selected
                                      ? AppTheme.brand
                                      : c.searchFill,
                                  borderRadius: BorderRadius.circular(19),
                                ),
                                child: Text(
                                  storyAreaDraftLabel(_areas[index]),
                                  style: TextStyle(
                                    color: index == _selected
                                        ? Colors.white
                                        : c.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _removeSelected,
                          child: Container(
                            width: 38,
                            height: 38,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppTheme.tagRed.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: AppIcon(
                              HeroAppIcons.trash,
                              size: 18,
                              color: AppTheme.tagRed,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _background() {
    final path = widget.mediaPath;
    if (!widget.isVideo && path != null && File(path).existsSync()) {
      return Image.file(File(path), fit: BoxFit.cover);
    }
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF27354A), Color(0xFF111723)],
        ),
      ),
      child: Center(
        child: AppIcon(
          widget.isVideo ? HeroAppIcons.video : HeroAppIcons.image,
          size: 46,
          color: Colors.white54,
        ),
      ),
    );
  }

  Widget _area(int index, Size size) {
    final area = _areas[index];
    final position = area.position;
    final width = size.width * position.widthPercentage / 100;
    final height = size.height * position.heightPercentage / 100;
    final centerX = size.width * position.xPercentage / 100;
    final centerY = size.height * position.yPercentage / 100;
    final selected = index == _selected;
    return Positioned(
      left: centerX - width / 2,
      top: centerY - height / 2,
      width: width,
      height: height,
      child: Transform.rotate(
        angle: position.rotationAngle * 3.141592653589793 / 180,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _selected = index),
          onScaleStart: (details) {
            setState(() => _selected = index);
            _gestureStartPosition = _areas[index].position;
            _gestureStartFocalPoint = details.focalPoint;
          },
          onScaleUpdate: (details) {
            final initial = _gestureStartPosition;
            final focal = _gestureStartFocalPoint;
            if (initial == null || focal == null || _canvasSize.isEmpty) return;
            setState(() {
              _areas[index] = _areas[index].copyWith(
                position: applyStoryAreaGesture(
                  initial: initial,
                  movement: details.focalPoint - focal,
                  canvasSize: _canvasSize,
                  scale: details.scale,
                  rotationRadians: details.rotation,
                ),
              );
            });
          },
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: selected ? 0.58 : 0.4),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: selected ? AppTheme.brand : Colors.white54,
                width: selected ? 2 : 1,
              ),
            ),
            child: Text(
              storyAreaDraftLabel(area),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String storyAreaDraftLabel(StoryAreaDraft area) => switch (area.type['@type']) {
  'inputStoryAreaTypeLink' => area.type['url'] as String? ?? 'Link',
  'inputStoryAreaTypeSuggestedReaction' =>
    ((area.type['reaction_type'] as Map?)?['emoji'] as String?) ?? 'Reaction',
  'inputStoryAreaTypeMessage' => 'Message',
  'inputStoryAreaTypeLocation' => 'Location',
  'inputStoryAreaTypeFoundVenue' => 'Venue',
  'inputStoryAreaTypePreviousVenue' => 'Venue',
  'inputStoryAreaTypeWeather' =>
    '${area.type['emoji'] ?? '☀️'} ${area.type['temperature'] ?? ''}°',
  'inputStoryAreaTypeUpgradedGift' => 'Gift',
  _ => 'Story area',
};
