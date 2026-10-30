import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:ephemera_ai/data/journal_repository.dart';
import 'package:ephemera_ai/data/proxy_client.dart';
import 'package:ephemera_ai/data/scrap_repository.dart';
import 'package:ephemera_ai/features/blend/simple_layout.dart';
import 'package:ephemera_ai/features/blend/theme_blend_screen.dart';
import 'package:ephemera_ai/features/editor/editor_screen.dart';
import 'package:ephemera_ai/features/editor/handwriting.dart';
import 'package:ephemera_ai/models/journal.dart';
import 'package:ephemera_ai/models/scrap.dart';
import 'package:ephemera_ai/providers.dart';

import '../fakes.dart';

Scrap _scrap(String id, String type) => Scrap(
  id: id,
  pngPath: '/missing/$id.png',
  width: 100,
  height: 150,
  source: ScrapSource.capture,
  createdAt: DateTime.utc(2026, 10, 31),
  type: type,
  tags: [type],
);

final _archive = [
  _scrap('r1', 'receipt'),
  _scrap('t1', 'ticket'),
  _scrap('w1', 'wrapper'),
];

Map<String, dynamic> _planJson() => {
  'theme': 'slow sunday',
  'title': 'Slow Sunday',
  'palette': ['#6B4F3A', '#E8DCC4'],
  'paper': 'kraft',
  'scraps': [
    {'id': 'r1', 'reason': 'The café receipt sets the morning.'},
    {'id': 't1', 'reason': 'The bus ride there.'},
  ],
  'captions': ['9:42, still sleepy'],
  'layout_intent': 'Receipt anchors the top.',
  'ephemera': [
    {'kind': 'stamp', 'prompt': 'coffee stamp'},
  ],
  'tool_calls': 3,
};

/// A 1x1 PNG, standing in for a generated decoration.
const _pixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

Map<String, dynamic> _respond(http.Request request, bool layoutFails) {
  switch (request.url.path) {
    case '/agent/plan':
      return okEnvelope(_planJson());
    case '/agent/ephemera':
      return okEnvelope({
        'kind': 'stamp',
        'png_base64': _pixelPng,
        'width': 40,
        'height': 30,
        'palette': ['#6B4F3A'],
      });
  }
  if (layoutFails) {
    return {
      'ok': false,
      'data': null,
      'error': {'code': 'model_error', 'message': 'down'},
    };
  }
  final sent = jsonDecode(request.body) as Map<String, dynamic>;
  return okEnvelope({
    'placements': [
      for (final s in sent['scraps'] as List<dynamic>)
        if ((s as Map<String, dynamic>)['id'] == 'r1')
          {
            'id': 'r1',
            'cx': 0.3,
            'cy': 0.25,
            'width': 0.5,
            'rotation_deg': -6,
            'z': 1,
          }
        else
          {
            'id': s['id'],
            'cx': 0.7,
            'cy': 0.6,
            'width': 0.2,
            'rotation_deg': 4,
            'z': 2,
          },
      {
        'id': 'ghost',
        'cx': 0.5,
        'cy': 0.5,
        'width': 0.3,
        'rotation_deg': 0,
        'z': 0,
      },
    ],
    'captions': [
      {
        'text': '9:42, still sleepy',
        'cx': 0.5,
        'cy': 0.9,
        'size': 0.06,
        'rotation_deg': -3,
      },
    ],
  });
}

void main() {
  setUpAll(() => useGoogleFonts = false);

  test('simple layout places every scrap plus the first caption', () {
    final page = simpleLayout(
      pageId: 'p',
      scraps: _archive,
      captions: ['hello', 'second'],
      paper: PaperStyle.kraft,
    );

    expect(page.paper, PaperStyle.kraft);
    expect(
      page.elements.where((e) => e.kind == ElementKind.scrap),
      hasLength(3),
    );
    expect(
      page.elements.where((e) => e.kind == ElementKind.text).single.text,
      'hello',
    );
    for (final e in page.elements) {
      expect(e.cx, inInclusiveRange(0, 1));
      expect(e.cy, inInclusiveRange(0, 1));
    }
    expect(paperFromName('dots'), PaperStyle.dots);
    expect(paperFromName('glitter'), PaperStyle.cream);
  });

  late Directory root;
  setUp(() async => root = await Directory.systemTemp.createTemp('blend_test'));
  tearDown(() async => root.delete(recursive: true));

  Future<FileJournalRepository> pumpBlend(
    WidgetTester tester,
    List<http.Request> log, {
    bool layoutFails = false,
    List<Scrap>? archive,
  }) async {
    final repository = FileJournalRepository(root);
    final journal = (await tester.runAsync(() => repository.create('Kyoto')))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          proxyClientProvider.overrideWithValue(
            ProxyClient(
              baseUrl: 'http://proxy',
              httpClient: fakeProxy((r) => _respond(r, layoutFails), log: log),
            ),
          ),
          scrapsProvider.overrideWith((ref) async => archive ?? _archive),
          scrapRepositoryProvider.overrideWith(
            (ref) async =>
                FileScrapRepository(Directory('${root.path}/archive')),
          ),
          journalRepositoryProvider.overrideWith((ref) async => repository),
        ],
        child: MaterialApp(home: ThemeBlendScreen(journal: journal)),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  /// Taps Build and waits for the editor to open (the page is saved by then).
  /// Reading the journal file while the app writes it locks it on Windows.
  Future<Journal?> buildAndWait(
    WidgetTester tester,
    String label,
    FileJournalRepository repository,
  ) {
    return tester.runAsync<Journal?>(() async {
      await tester.tap(find.text(label));
      for (var i = 0; i < 300; i++) {
        await tester.pump();
        if (find.byType(EditorScreen).evaluate().isNotEmpty) {
          return (await repository.getAll()).single;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return null;
    });
  }

  testWidgets('an empty theme shows a hint instead of calling the agent', (
    tester,
  ) async {
    final log = <http.Request>[];
    await pumpBlend(tester, log);

    await tester.tap(find.text('Plan a page'));
    await tester.pump();

    expect(find.textContaining('Describe a theme first'), findsOneWidget);
    expect(log, isEmpty);
  });

  testWidgets('a theme returns plan cards built from the archive', (
    tester,
  ) async {
    final log = <http.Request>[];
    await pumpBlend(tester, log);

    await tester.enterText(find.byType(TextField), 'slow sunday');
    await tester.tap(find.text('Plan a page'));
    await tester.pumpAndSettle();

    final sent = jsonDecode(log.single.body) as Map<String, dynamic>;
    expect(sent['theme'], 'slow sunday');
    expect((sent['archive'] as List), hasLength(3));
    expect(find.text('Slow Sunday'), findsOneWidget);
    expect(find.text('The café receipt sets the morning.'), findsOneWidget);
    expect(
      find.textContaining('coffee stamp', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('1 decoration · ≈₱0.64'), findsOneWidget);
    expect(
      find.text('Build page with 2 scraps + 1 decoration'),
      findsOneWidget,
    );
  });

  testWidgets('dropping a scrap and building adds a page with the rest', (
    tester,
  ) async {
    final log = <http.Request>[];
    final repository = await pumpBlend(tester, log);
    await tester.enterText(find.byType(TextField), 'slow sunday');
    await tester.tap(find.text('Plan a page'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('The bus ride there.'));
    await tester.pump();
    await tester.ensureVisible(
      find.textContaining('coffee stamp', findRichText: true),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.textContaining('coffee stamp', findRichText: true),
    ); // and skip the decoration
    await tester.pump();
    expect(find.text('Build page with 1 scrap'), findsOneWidget);
    await tester.ensureVisible(find.text('Build page with 1 scrap'));
    await tester.pumpAndSettle();

    final journal = await buildAndWait(
      tester,
      'Build page with 1 scrap',
      repository,
    );

    final page = journal!.pages.last;
    expect(page.paper, PaperStyle.kraft);
    expect(
      page.elements.where((e) => e.kind == ElementKind.scrap).single.scrapId,
      'r1',
    );
    final scrap = page.elements.firstWhere((e) => e.kind == ElementKind.scrap);
    expect(scrap.cx, closeTo(0.3, 1e-9)); // the agent's placement
    expect(scrap.size, closeTo(0.5, 1e-9));
    expect(page.elements.last.text, '9:42, still sleepy');
    expect(log.where((r) => r.url.path == '/agent/layout'), hasLength(1));
    expect(log.where((r) => r.url.path == '/agent/ephemera'), isEmpty);
  });

  testWidgets('building makes the decoration, saves it and places it', (
    tester,
  ) async {
    final log = <http.Request>[];
    final repository = await pumpBlend(tester, log);
    await tester.enterText(find.byType(TextField), 'slow sunday');
    await tester.tap(find.text('Plan a page'));
    await tester.pumpAndSettle();
    const build = 'Build page with 2 scraps + 1 decoration';
    await tester.ensureVisible(find.text(build));
    await tester.pumpAndSettle();

    final journal = await buildAndWait(tester, build, repository);

    final sent =
        jsonDecode(log.singleWhere((r) => r.url.path == '/agent/ephemera').body)
            as Map<String, dynamic>;
    expect(sent, {
      'kind': 'stamp',
      'prompt': 'coffee stamp',
      'palette': ['#6B4F3A', '#E8DCC4'],
    });
    final saved = await tester.runAsync(
      () => FileScrapRepository(Directory('${root.path}/archive')).getAll(),
    );
    final stamp = saved!.single;
    expect(stamp.source, ScrapSource.generated);
    expect(stamp.type, 'stamp');
    expect(stamp.description, 'coffee stamp');
    final placed = journal!.pages.last.elements.where(
      (e) => e.kind == ElementKind.scrap,
    );
    expect(placed.map((e) => e.scrapId), containsAll(['r1', 't1', stamp.id]));
  });

  testWidgets('if the designer fails, Build still makes a simple page', (
    tester,
  ) async {
    final log = <http.Request>[];
    final repository = await pumpBlend(tester, log, layoutFails: true);
    await tester.enterText(find.byType(TextField), 'slow sunday');
    await tester.tap(find.text('Plan a page'));
    await tester.pumpAndSettle();
    const build = 'Build page with 2 scraps + 1 decoration';
    await tester.ensureVisible(find.text(build));
    await tester.pumpAndSettle();

    final journal = await buildAndWait(tester, build, repository);

    final scraps = journal!.pages.last.elements.where(
      (e) => e.kind == ElementKind.scrap,
    );
    expect(scraps, hasLength(3)); // simple cascade, decoration included
  });

  testWidgets(
    'scraps used in real spreads and tiny slivers never reach the agent',
    (tester) async {
      final log = <http.Request>[];
      final glued = Scrap(
        id: 'glued',
        pngPath: '/missing/glued.png',
        width: 100,
        height: 150,
        source: ScrapSource.capture,
        createdAt: DateTime.utc(2026, 10, 31),
        physicalStatus: PhysicalStatus.used,
      );
      final sliver = Scrap(
        id: 'sliver',
        pngPath: '/missing/sliver.png',
        width: 40,
        height: 340,
        source: ScrapSource.capture,
        createdAt: DateTime.utc(2026, 10, 31),
        splitFromLabel: 'wrapper',
      );
      await pumpBlend(tester, log, archive: [..._archive, glued, sliver]);

      await tester.enterText(find.byType(TextField), 'slow sunday');
      await tester.tap(find.text('Plan a page'));
      await tester.pumpAndSettle();

      final sent = jsonDecode(log.single.body) as Map<String, dynamic>;
      final ids = [for (final s in sent['archive'] as List) s['id']];
      expect(ids, ['r1', 't1', 'w1']);
    },
  );
}
