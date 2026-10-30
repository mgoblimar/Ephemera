import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:ephemera_ai/models/blend_plan.dart';
import 'package:ephemera_ai/models/scrap.dart';
import 'package:ephemera_ai/models/segmentation.dart';

abstract interface class ScrapRepository {
  Future<List<Scrap>> getAll();

  /// Saves the capture photo and its cutouts; returns the new scraps.
  Future<List<Scrap>> saveCapture({
    required Uint8List photoJpeg,
    required List<CutoutScrap> cutouts,
  });

  /// Saves a decoration made by the image model (source: generated).
  Future<Scrap> saveGenerated(GeneratedEphemera ephemera);

  /// Replaces a stored scrap's metadata (e.g. after enrichment).
  Future<void> update(Scrap scrap);
}

/// Local-only archive: PNG/JPEG files plus a JSON index in the app documents dir.
/// Simple and fast enough for hundreds of scraps; swap for a DB if it grows.
class FileScrapRepository implements ScrapRepository {
  FileScrapRepository(
    this._root, {
    Uuid uuid = const Uuid(),
    DateTime Function()? clock,
  }) : _uuid = uuid,
       _clock = clock ?? DateTime.now;

  final Directory _root;
  final Uuid _uuid;
  final DateTime Function() _clock;

  /// Writes run one at a time: saving a scan and enrichment updates both
  /// read-modify-write the index, and must not overwrite each other.
  Future<void> _writes = Future.value();

  Future<T> _serially<T>(Future<T> Function() action) {
    final result = _writes.then((_) => action());
    _writes = result.then((_) {}, onError: (_) {});
    return result;
  }

  File get _scrapIndex => File(p.join(_root.path, 'scraps.json'));
  File get _captureIndex => File(p.join(_root.path, 'captures.json'));
  Directory get _scrapDir => Directory(p.join(_root.path, 'scraps'));
  Directory get _captureDir => Directory(p.join(_root.path, 'captures'));

  @override
  Future<List<Scrap>> getAll() async {
    final scraps = (await _readList(_scrapIndex)).map(Scrap.fromJson).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(scraps);
  }

  @override
  Future<List<Scrap>> saveCapture({
    required Uint8List photoJpeg,
    required List<CutoutScrap> cutouts,
  }) => _serially(() => _saveCapture(photoJpeg, cutouts));

  Future<List<Scrap>> _saveCapture(
    Uint8List photoJpeg,
    List<CutoutScrap> cutouts,
  ) async {
    await _scrapDir.create(recursive: true);
    await _captureDir.create(recursive: true);
    final now = _clock();
    final captureId = _uuid.v4();

    final photoPath = p.join(_captureDir.path, '$captureId.jpg');
    await File(photoPath).writeAsBytes(photoJpeg, flush: true);

    // Ids first, so a Split element can link to its parent saved in this batch.
    final ids = {for (final c in cutouts) c.maskId: _uuid.v4()};
    final scraps = <Scrap>[];
    for (final cutout in cutouts) {
      final id = ids[cutout.maskId]!;
      final pngPath = p.join(_scrapDir.path, '$id.png');
      await File(pngPath).writeAsBytes(cutout.png, flush: true);
      scraps.add(
        Scrap(
          id: id,
          pngPath: pngPath,
          width: cutout.width,
          height: cutout.height,
          source: ScrapSource.capture,
          createdAt: now,
          captureId: captureId,
          palette: cutout.palette,
          type: cutout.label ?? 'other',
          splitFromLabel: cutout.parentPieceId == null
              ? null
              : (cutout.parentLabel ?? 'other'),
          parentScrapId: ids[cutout.parentPieceId],
        ),
      );
    }

    final capture = Capture(
      id: captureId,
      photoPath: photoPath,
      createdAt: now,
      scrapIds: List.unmodifiable(scraps.map((s) => s.id)),
    );
    await _writeList(_captureIndex, [
      ...await _readList(_captureIndex),
      capture.toJson(),
    ]);
    await _writeList(_scrapIndex, [
      ...await _readList(_scrapIndex),
      ...scraps.map((s) => s.toJson()),
    ]);
    return List.unmodifiable(scraps);
  }

  @override
  Future<Scrap> saveGenerated(GeneratedEphemera ephemera) =>
      _serially(() async {
        await _scrapDir.create(recursive: true);
        final id = _uuid.v4();
        final pngPath = p.join(_scrapDir.path, '$id.png');
        await File(pngPath).writeAsBytes(ephemera.png, flush: true);
        final scrap = Scrap(
          id: id,
          pngPath: pngPath,
          width: ephemera.width,
          height: ephemera.height,
          source: ScrapSource.generated,
          createdAt: _clock(),
          type: ephemera.kind,
          tags: List.unmodifiable(['generated', ephemera.kind]),
          palette: ephemera.palette,
          description: ephemera.prompt,
          // The prompt already describes it; no need to pay for enrichment.
          enriched: true,
        );
        await _writeList(_scrapIndex, [
          ...await _readList(_scrapIndex),
          scrap.toJson(),
        ]);
        return scrap;
      });

  @override
  Future<void> update(Scrap scrap) => _serially(() async {
    final all = await _readList(_scrapIndex);
    await _writeList(_scrapIndex, [
      for (final s in all) s['id'] == scrap.id ? scrap.toJson() : s,
    ]);
  });

  Future<List<Map<String, dynamic>>> _readList(File file) async {
    if (!await file.exists()) return const [];
    final decoded = jsonDecode(await file.readAsString()) as List<dynamic>;
    return decoded.cast<Map<String, dynamic>>();
  }

  /// Writes to a temp file then renames, so a crash mid-write can't corrupt the index.
  Future<void> _writeList(File file, List<Map<String, dynamic>> items) async {
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(items), flush: true);
    await temp.rename(file.path);
  }
}
