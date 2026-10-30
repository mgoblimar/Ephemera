import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:ephemera_ai/data/enrichment_service.dart';
import 'package:ephemera_ai/data/proxy_client.dart';
import 'package:ephemera_ai/data/scrap_repository.dart';
import 'package:ephemera_ai/models/segmentation.dart';

import '../fakes.dart';

CutoutScrap _cutout(String id, {String? label}) => CutoutScrap(
  maskId: id,
  png: base64Decode(tinyPngBase64),
  width: 1,
  height: 1,
  palette: const ['#C8B496'],
  label: label,
);

void main() {
  late Directory root;
  late FileScrapRepository repository;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('enrich_test');
    repository = FileScrapRepository(root);
  });
  tearDown(() async => root.delete(recursive: true));

  EnrichmentService service(http.Client client, {void Function()? onUpdated}) =>
      EnrichmentService(
        proxy: ProxyClient(baseUrl: 'http://proxy', httpClient: client),
        repository: () async => repository,
        onUpdated: onUpdated ?? () {},
      );

  test('enriches pending scraps with text, tags and entities', () async {
    await repository.saveCapture(
      photoJpeg: Uint8List(1),
      cutouts: [
        _cutout('a'),
        _cutout('b', label: 'ticket'),
      ],
    );
    var updates = 0;
    final client = fakeProxy(
      (_) => okEnvelope({
        'type': 'receipt',
        'ocr_text': 'Cafe 09:42',
        'entities': {'time': '09:42'},
        'tags': ['coffee'],
        'mood': ['cozy'],
        'description': 'A receipt.',
        'palette': ['#FFFFFF'],
      }),
    );

    final done = await service(
      client,
      onUpdated: () => updates++,
    ).enrichPending();

    final all = await repository.getAll();
    expect(done, 2);
    expect(updates, greaterThan(0));
    expect(all.every((s) => s.enriched && s.tags.contains('coffee')), isTrue);
    expect(
      all.firstWhere((s) => s.type != 'receipt').type,
      'ticket',
    ); // detector's type kept
    expect(all.first.entities, {'time': '09:42'});
  });

  test('failed scraps stay pending for the next run', () async {
    await repository.saveCapture(
      photoJpeg: Uint8List(1),
      cutouts: [_cutout('a')],
    );
    final failing = fakeProxy(
      (_) => {
        'ok': false,
        'data': null,
        'error': {'code': 'model_error', 'message': 'nope'},
      },
    );

    expect(await service(failing).enrichPending(), 0);
    expect((await repository.getAll()).single.enriched, isFalse);
  });

  test('concurrent saves and updates do not overwrite each other', () async {
    final first = await repository.saveCapture(
      photoJpeg: Uint8List(1),
      cutouts: [_cutout('a')],
    );

    await Future.wait([
      repository.update(first.single.copyWith(tags: const ['updated'])),
      repository.saveCapture(photoJpeg: Uint8List(1), cutouts: [_cutout('b')]),
      repository.saveCapture(photoJpeg: Uint8List(1), cutouts: [_cutout('c')]),
    ]);

    final all = await repository.getAll();
    expect(all, hasLength(3));
    expect(all.firstWhere((s) => s.id == first.single.id).tags, ['updated']);
  });
}
