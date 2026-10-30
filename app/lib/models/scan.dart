import 'dart:typed_data';
import 'dart:ui';

import 'package:ephemera_ai/models/segmentation.dart';

/// One piece the detector found in a scanned photo. Not cut out yet.
class ScanPiece {
  const ScanPiece({
    required this.id,
    required this.imageId,
    required this.label,
    required this.thumbJpeg,
    this.parentId,
    this.box,
    this.photoSize,
  });

  final String id;
  final String imageId;
  final String label;
  final Uint8List thumbJpeg;

  /// Set for design elements split out of a whole piece.
  final String? parentId;

  /// Where the piece sits on the photo, in the detector's working pixels.
  final Rect? box;

  /// Size of the detector's working copy of the photo.
  final Size? photoSize;

  bool get isElement => parentId != null;

  /// [box] as fractions of the photo (0..1), for drawing over any size.
  Rect? get area {
    final b = box;
    final size = photoSize;
    if (b == null || size == null || size.isEmpty) return null;
    return Rect.fromLTRB(
      b.left / size.width,
      b.top / size.height,
      b.right / size.width,
      b.bottom / size.height,
    );
  }

  /// Unique across a whole scan session.
  String get key => '$imageId:$id';
}

class ScanPhoto {
  const ScanPhoto({required this.imageId, required this.pieces});

  final String imageId;
  final List<ScanPiece> pieces;

  /// Inserts [elements] right after their parent piece.
  ScanPhoto withElements(String parentId, List<ScanPiece> elements) {
    return ScanPhoto(
      imageId: imageId,
      pieces: List.unmodifiable([
        for (final p in pieces) ...[p, if (p.id == parentId) ...elements],
      ]),
    );
  }
}

class ScanCutResult {
  const ScanCutResult({
    required this.scraps,
    required this.missedCount,
    required this.samRequests,
    this.roughCount = 0,
  });

  /// Cutouts; [CutoutScrap.maskId] holds the piece id, keyed by image below.
  final List<({String imageId, CutoutScrap scrap})> scraps;
  final int missedCount;
  final int samRequests;

  /// Of [missedCount]: pieces SAM cut but that came out as broken fragments.
  final int roughCount;
}

/// One photo in the session: detected cheaply, its pieces chosen later.
class SessionPhoto {
  const SessionPhoto({
    required this.key,
    required this.bytes,
    required this.filename,
    this.scan,
    this.error,
  });

  final int key;
  final Uint8List bytes;
  final String filename;
  final ScanPhoto? scan;
  final String? error;

  bool get isLoading => scan == null && error == null;

  SessionPhoto withScan(ScanPhoto scan) =>
      SessionPhoto(key: key, bytes: bytes, filename: filename, scan: scan);

  SessionPhoto withError(String error) =>
      SessionPhoto(key: key, bytes: bytes, filename: filename, error: error);

  SessionPhoto retrying() =>
      SessionPhoto(key: key, bytes: bytes, filename: filename);
}
