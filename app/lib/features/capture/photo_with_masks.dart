import 'package:flutter/material.dart';

import 'package:ephemera_ai/models/segmentation.dart';
import 'package:ephemera_ai/theme.dart';

const _keptOpacity = 0.5;
const _discardedOpacity = 0.12;

/// The segmented photo with tinted, numbered mask overlays. Taps are reported
/// in photo pixel coordinates so they can be sent straight to SAM.
class PhotoWithMasks extends StatelessWidget {
  const PhotoWithMasks({
    super.key,
    required this.result,
    required this.kept,
    required this.onTapPhoto,
  });

  final SegmentResult result;
  final Set<String> kept;
  final ValueChanged<Offset> onTapPhoto;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: result.width / result.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = constraints.maxWidth / result.width;
          return GestureDetector(
            onTapUp: (details) => onTapPhoto(details.localPosition / scale),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(
                  result.photoJpeg,
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                ),
                for (final (index, mask) in result.masks.indexed)
                  _MaskOverlay(
                    mask: mask,
                    number: index + 1,
                    scale: scale,
                    tint: Palette.maskTints[index % Palette.maskTints.length],
                    isKept: kept.contains(mask.id),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MaskOverlay extends StatelessWidget {
  const _MaskOverlay({
    required this.mask,
    required this.number,
    required this.scale,
    required this.tint,
    required this.isKept,
  });

  final MaskCandidate mask;
  final int number;
  final double scale;
  final Color tint;
  final bool isKept;

  @override
  Widget build(BuildContext context) {
    final rect = Rect.fromLTWH(
      mask.bbox.left * scale,
      mask.bbox.top * scale,
      mask.bbox.width * scale,
      mask.bbox.height * scale,
    );
    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: isKept ? _keptOpacity : _discardedOpacity,
              child: ColorFiltered(
                colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
                child: Image.memory(
                  mask.previewPng,
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                ),
              ),
            ),
            Align(
              alignment: Alignment.topLeft,
              child: CircleAvatar(
                radius: 11,
                backgroundColor: isKept ? tint : Colors.white70,
                child: Text(
                  '$number',
                  style: const TextStyle(fontSize: 12, color: Palette.ink),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
