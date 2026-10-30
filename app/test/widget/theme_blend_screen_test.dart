import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:ephemera_ai/data/journal_repository.dart';
import 'package:ephemera_ai/data/proxy_client.dart';
import 'package:ephemera_ai/features/blend/simple_layout.dart';
import 'package:ephemera_ai/features/blend/theme_blend_screen.dart';
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
    List<http.Request> log,
  ) async {
    final repository = FileJournalRepository(root);
    final journal = (await tester.runAsync(() => repository.create('Kyoto')))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          proxyClientProvider.overrideWithValue(
            ProxyClient(
              baseUrl: 'http://proxy',
              httpClient: fakeProxy((_) => okEnvelope(_planJson()), log: log),
            ),
          ),
          scrapsProvider.overrideWith((ref) async => _archive),
          journalRepositoryProvider.overrideWith((ref) async => repository),
        ],
        child: MaterialApp(home: ThemeBlendScreen(journal: journal)),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
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
    expect(find.text('Build page with 2 scraps'), findsOneWidget);
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
    expect(find.text('Build page with 1 scrap'), findsOneWidget);
    await tester.ensureVisible(find.text('Build page with 1 scrap'));
    await tester.pumpAndSettle();

    final journal = await tester.runAsync(() async {
      await tester.tap(find.text('Build page with 1 scrap'));
      for (var i = 0; i < 100; i++) {
        await tester.pump();
        final j = (await repository.getAll()).single;
        if (j.pages.length == 2) return j;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return null;
    });

    final page = journal!.pages.last;
    expect(page.paper, PaperStyle.kraft);
    expect(
      page.elements.where((e) => e.kind == ElementKind.scrap).single.scrapId,
      'r1',
    );
  });
}
