import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:ephemera_ai/data/proxy_client.dart';
import 'package:ephemera_ai/data/scrap_repository.dart';
import 'package:ephemera_ai/features/capture/photo_source.dart';
import 'package:ephemera_ai/features/scan/scan_session_screen.dart';
import 'package:ephemera_ai/models/scrap.dart';
import 'package:ephemera_ai/providers.dart';

import '../fakes.dart';

/// Answers detect with 2 pieces per photo and records cut requests.
http.Client _proxy(List<http.Request> log) {
  var photoCount = 0;
  return fakeProxy((request) {
    if (request.url.path == '/scan/detect') {
      return okEnvelope(scanDetectData('img${photoCount++}'));
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    return okEnvelope(
      scanCutData((body['pieces'] as List).cast<Map<String, dynamic>>()),
    );
  }, log: log);
}

Future<PickedPhoto?> _fakePick(BuildContext context) async =>
    (bytes: base64Decode(tinyPngBase64), filename: 'desk.jpg');

Widget _app(http.Client client, ScrapRepository repository) => ProviderScope(
  overrides: [
    proxyClientProvider.overrideWithValue(
      ProxyClient(baseUrl: 'http://proxy', httpClient: client),
    ),
    scrapRepositoryProvider.overrideWith((ref) async => repository),
  ],
  child: const MaterialApp(home: ScanSessionScreen(photoPicker: _fakePick)),
);

/// Taps the cut button, then waits (in real time) until [count] scraps are saved.
Future<List<Scrap>> _cutAndWait(
  WidgetTester tester,
  String button,
  ScrapRepository repository,
  int count,
) async {
  final saved = await tester.runAsync(() async {
    await tester.tap(find.text(button));
    for (var i = 0; i < 100; i++) {
      await tester.pump();
      final all = await repository.getAll();
      if (all.length == count) return all;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return repository.getAll();
  });
  return saved ?? [];
}

void main() {
  late Directory root;

  setUp(() async => root = await Directory.systemTemp.createTemp('scan_test'));
  tearDown(() async => root.delete(recursive: true));

  testWidgets('a scanned photo shows its pieces, all chosen, with cost', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_proxy([]), FileScrapRepository(root)));
    await tester.pumpAndSettle();

    expect(find.text('2 pieces found'), findsOneWidget);
    expect(find.text('Cut & save 2'), findsOneWidget);
    expect(find.textContaining('1 cut request · ≈₱0.16'), findsOneWidget);
  });

  testWidgets('unticking a piece leaves it out of the cut', (tester) async {
    final log = <http.Request>[];
    final repository = FileScrapRepository(root);
    await tester.pumpWidget(_app(_proxy(log), repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ticket'));
    await tester.pump();
    expect(find.text('Cut & save 1'), findsOneWidget);

    await _cutAndWait(tester, 'Cut & save 1', repository, 1);
    final cut = log.singleWhere((r) => r.url.path == '/scan/cut');
    final sent = (jsonDecode(cut.body) as Map)['pieces'] as List;
    expect(sent.map((p) => (p as Map)['piece_id']), ['p0']);
  });

  testWidgets(
    'pieces from two photos are cut in one request and saved per photo',
    (tester) async {
      final log = <http.Request>[];
      final repository = FileScrapRepository(root);
      await tester.pumpWidget(_app(_proxy(log), repository));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Photo'));
      await tester.pumpAndSettle();
      expect(find.text('Cut & save 4'), findsOneWidget);

      final saved = await _cutAndWait(tester, 'Cut & save 4', repository, 4);

      expect(log.where((r) => r.url.path == '/scan/cut'), hasLength(1));
      expect(saved, hasLength(4));
      expect(saved.map((s) => s.captureId).toSet(), hasLength(2));
      expect(saved.every((s) => s.type == 'sticker'), isTrue);
    },
  );

  testWidgets('a failed scan shows the error with retry', (tester) async {
    final client = fakeProxy(
      (_) => {
        'ok': false,
        'data': null,
        'error': {'code': 'model_error', 'message': 'The AI had a problem.'},
      },
    );
    await tester.pumpWidget(_app(client, FileScrapRepository(root)));
    await tester.pumpAndSettle();

    expect(find.text('The AI had a problem.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Cut & save 0'), findsOneWidget);
  });
}
