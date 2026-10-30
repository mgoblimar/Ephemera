import 'dart:typed_data';
import 'dart:ui';

enum CutStyle { tight, sticker, margin }

enum CutSize { s, m, l }

/// One object SAM found in the photo. [bbox] is in photo pixel coordinates.
class MaskCandidate {
  const MaskCandidate({
    required this.id,
    required this.bbox,
    required this.score,
    required this.previewPng,
    this.label,
  });

  final String id;
  final Rect bbox;
  final double score;

  /// Scrap type the detector suggested, e.g. "sticker"; null for tap-added masks.
  final String? label;

  /// White RGBA image of the mask, cropped to [bbox], tinted by the app.
  final Uint8List previewPng;
}

class SegmentResult {
  const SegmentResult({
    required this.imageId,
    required this.width,
    required this.height,
    required this.photoJpeg,
    required this.masks,
  });

  final String imageId;
  final int width;
  final int height;

  /// The upright, downscaled photo that [masks] refer to.
  final Uint8List photoJpeg;
  final List<MaskCandidate> masks;

  SegmentResult withMask(MaskCandidate mask) => SegmentResult(
    imageId: imageId,
    width: width,
    height: height,
    photoJpeg: photoJpeg,
    masks: List.unmodifiable([...masks, mask]),
  );
}

class TapPoint {
  const TapPoint(this.x, this.y, {this.positive = true});

  final double x;
  final double y;
  final bool positive;

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'positive': positive};
}

class CutoutScrap {
  const CutoutScrap({
    required this.maskId,
    required this.png,
    required this.width,
    required this.height,
    required this.palette,
    this.label,
  });

  final String maskId;
  final Uint8List png;
  final int width;
  final int height;
  final List<String> palette;

  /// Scrap type carried over from the mask it was cut from.
  final String? label;

  CutoutScrap withLabel(String? label) => CutoutScrap(
    maskId: maskId,
    png: png,
    width: width,
    height: height,
    palette: palette,
    label: label,
  );
}
