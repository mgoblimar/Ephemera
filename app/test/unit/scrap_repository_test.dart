import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ephemera_ai/data/scrap_repository.dart';
import 'package:ephemera_ai/models/scrap.dart';
import 'package:ephemera_ai/models/segmentation.dart';

import '../fakes.dart';

CutoutScrap _cutout(String maskId) => CutoutScrap(
  maskId: maskId,
  png: base64Decode(tinyPngBase64),
  width: 1,
  height: 1,
  palette: const ['#C8B496'],
);

void main() {
  late Directory root;

  setUp(
    () async => root = await Directory.systemTemp.createTemp('ephemera_test'),
  );
  tearDown(() async => root.delete(recursive: true));

  test('empty archive returns no scraps', () async {
    expect(await FileScrapRepository(root).getAll(), isEmpty);
  });

  test(
    'saveCapture writes files and persists scraps across instances',
    () async {
      final repository = FileScrapRepository(
        root,
        clock: () => DateTime.utc(2026, 10, 29),
      );

      final saved = await repository.saveCapture(
        photoJpeg: Uint8List.fromList([1, 2, 3]),
        cutouts: [_cutout('m0'), _cutout('m1')],
      );

      expect(saved, hasLength(2));
      expect(saved.every((s) => File(s.pngPath).existsSync()), isTrue);
      expect(saved.map((s) => s.captureId).toSet(), hasLength(1));

      final reloaded = await FileScrapRepository(root).getAll();
      expect(reloaded.map((s) => s.id).toSet(), saved.map((s) => s.id).toSet());
      expect(reloaded.first.source, ScrapSource.capture);
      expect(reloaded.first.palette, ['#C8B496']);
      expect(reloaded.map((s) => s.type).toSet(), {'other'});
    },
  );

  test('saveCapture stores the detected scrap type', () async {
    final repository = FileScrapRepository(root);

    final saved = await repository.saveCapture(
      photoJpeg: Uint8List(1),
      cutouts: [_cutout('m0').withLabel('sticker')],
    );

    expect(saved.single.type, 'sticker');
    expect((await FileScrapRepository(root).getAll()).single.type, 'sticker');
  });

  test('split elements remember their parent piece', () async {
    final repository = FileScrapRepository(root);

    final saved = await repository.saveCapture(
      photoJpeg: Uint8List(1),
      cutouts: [
        _cutout('whole').withLabel('wrapper'),
        _cutout('logo').withOrigin(
          label: 'logo',
          parentPieceId: 'whole',
          parentLabel: 'wrapper',
        ),
        _cutout('orphan').withOrigin(
          label: 'lettering',
          parentPieceId: 'not-cut',
          parentLabel: 'box',
        ),
      ],
    );

    final reloaded = {
      for (final s in await FileScrapRepository(root).getAll()) s.type: s,
    };
    expect(reloaded['wrapper']!.isSplitElement, isFalse);
    expect(reloaded['logo']!.splitFromLabel, 'wrapper');
    expect(reloaded['logo']!.parentScrapId, saved.first.id);
    expect(reloaded['lettering']!.splitFromLabel, 'box');
    expect(reloaded['lettering']!.parentScrapId, isNull); // parent wasn't cut
  });

  test('getAll lists newest scraps first', () async {
    var now = DateTime.utc(2026, 10, 29, 9);
    final repository = FileScrapRepository(root, clock: () => now);
    final older = await repository.saveCapture(
      photoJpeg: Uint8List(1),
      cutouts: [_cutout('a')],
    );
    now = DateTime.utc(2026, 10, 29, 10);
    final newer = await repository.saveCapture(
      photoJpeg: Uint8List(1),
      cutouts: [_cutout('b')],
    );

    final all = await repository.getAll();

    expect(all.map((s) => s.id), [newer.single.id, older.single.id]);
  });

  test('Scrap JSON round-trips and copyWith leaves the original unchanged', () {
    final scrap = Scrap(
      id: 's1',
      pngPath: '/x.png',
      width: 10,
      height: 20,
      source: ScrapSource.generated,
      createdAt: DateTime.utc(2026, 10, 29),
      tags: const ['tape'],
    );

    final enriched = scrap.copyWith(
      tags: const ['tape', 'washi'],
      enriched: true,
    );

    expect(Scrap.fromJson(enriched.toJson()).toJson(), enriched.toJson());
    expect(scrap.tags, ['tape']);
    expect(scrap.enriched, isFalse);
  });

  test(
    'remove takes a scrap out but keeps its image; restore undoes it',
    () async {
      final repository = FileScrapRepository(root);
      final saved = await repository.saveCapture(
        photoJpeg: Uint8List.fromList([1]),
        cutouts: [_cutout('m0'), _cutout('m1')],
      );
      final gone = saved.first;

      await repository.remove(gone.id);

      expect((await repository.getAll()).map((s) => s.id), [saved.last.id]);
      expect(File(gone.pngPath).existsSync(), isTrue); // pages still show it

      await repository.restore(gone);
      await repository.restore(gone); // twice is harmless

      expect(
        (await repository.getAll()).map((s) => s.id).toSet(),
        saved.map((s) => s.id).toSet(),
      );
    },
  );

  group('tooWeakForAgent', () {
    Scrap scrap(int w, int h, {bool split = false}) => Scrap(
      id: 's',
      pngPath: 'x.png',
      width: w,
      height: h,
      source: ScrapSource.capture,
      createdAt: DateTime.utc(2026),
      splitFromLabel: split ? 'wrapper' : null,
    );

    test('small whole stickers are fine; only specks are hidden', () {
      expect(scrap(205, 97).tooWeakForAgent, isFalse);
      expect(scrap(40, 300).tooWeakForAgent, isTrue);
    });

    test('split slivers and tiny badges are hidden, real elements kept', () {
      expect(scrap(118, 57, split: true).tooWeakForAgent, isTrue); // badge
      expect(scrap(60, 343, split: true).tooWeakForAgent, isTrue); // side text
      expect(scrap(433, 356, split: true).tooWeakForAgent, isFalse); // mascot
      expect(scrap(109, 333, split: true).tooWeakForAgent, isFalse);
    });
  });
}
