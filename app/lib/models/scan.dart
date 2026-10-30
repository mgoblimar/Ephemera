import 'dart:typed_data';

import 'package:ephemera_ai/models/segmentation.dart';

/// One piece the detector found in a scanned photo. Not cut out yet.
class ScanPiece {
  const ScanPiece({
    required this.id,
    required this.imageId,
    required this.label,
    required this.thumbJpeg,
    this.parentId,
  });

  final String id;
  final String imageId;
  final String label;
  final Uint8List thumbJpeg;

  /// Set for design elements split out of a whole piece.
  final String? parentId;

  bool get isElement => parentId != null;

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
  });

  /// Cutouts; [CutoutScrap.maskId] holds the piece id, keyed by image below.
  final List<({String imageId, CutoutScrap scrap})> scraps;
  final int missedCount;
  final int samRequests;
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
