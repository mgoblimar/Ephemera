import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ephemera_ai/data/journal_repository.dart';
import 'package:ephemera_ai/features/editor/editor_screen.dart';
import 'package:ephemera_ai/features/editor/handwriting.dart';
import 'package:ephemera_ai/features/editor/strokes.dart';
import 'package:ephemera_ai/models/journal.dart';
import 'package:ephemera_ai/models/scrap.dart';
import 'package:ephemera_ai/providers.dart';

void main() {
  late Directory root;
  late FileJournalRepository repository;

  setUpAll(() => useGoogleFonts = false);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('editor_test');
    repository = FileJournalRepository(root);
  });
  tearDown(() async => root.delete(recursive: true));

  Future<Journal> pumpEditor(
    WidgetTester tester, {
    List<Scrap> scraps = const [],
  }) async {
    final journal = (await tester.runAsync(() => repository.create('Kyoto')))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          journalRepositoryProvider.overrideWith((ref) async => repository),
          scrapsProvider.overrideWith((ref) async => scraps),
        ],
        child: MaterialApp(
          home: EditorScreen(journal: journal, pageId: journal.pages.single.id),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return journal;
  }

  Future<void> addCaption(WidgetTester tester, String text) async {
    await tester.tap(find.text('Text'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), text);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
  }

  testWidgets('adding a caption puts it on the page and selects it', (
    tester,
  ) async {
    await pumpEditor(tester);

    await addCaption(tester, 'slow sunday');

    expect(find.text('slow sunday'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget); // selection bar is showing
  });

  testWidgets('an empty caption shows an error instead of adding', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.tap(find.text('Text'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pump();

    expect(find.text('Write something first'), findsOneWidget);
  });

  testWidgets('dragging moves an element and undo puts it back', (
    tester,
  ) async {
    await pumpEditor(tester);
    await addCaption(tester, 'drag me');
    final before = tester.getCenter(find.text('drag me'));

    await tester.drag(find.text('drag me'), const Offset(0, -120));
    await tester.pumpAndSettle();
    final after = tester.getCenter(find.text('drag me'));
    expect(after.dy, lessThan(before.dy - 60));

    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.text('drag me')).dy, closeTo(before.dy, 2));
  });

  testWidgets('the corner handle scales the selected element', (tester) async {
    await pumpEditor(tester);
    await addCaption(tester, 'grow me');
    final before = tester.getSize(find.text('grow me'));
    final handle = find.byKey(const ValueKey('resize-handle'));
    final center = tester.getCenter(find.text('grow me'));
    final arm = tester.getCenter(handle) - center;

    // Drag straight outwards: no rotation, about twice the distance.
    final gesture = await tester.startGesture(tester.getCenter(handle));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(arm / 10);
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.text('grow me')).width,
      greaterThan(before.width * 1.5),
    );
  });

  testWidgets('the scrap picker can be searched like the archive', (
    tester,
  ) async {
    Scrap scrap(String id, String type, String ocr) => Scrap(
      id: id,
      pngPath: '/missing/$id.png',
      width: 100,
      height: 100,
      source: ScrapSource.capture,
      createdAt: DateTime.utc(2026, 10, 31),
      type: type,
      ocrText: ocr,
      enriched: true,
    );
    await pumpEditor(
      tester,
      scraps: [
        scrap('r', 'receipt', 'Cafe Lumiere'),
        scrap('t', 'ticket', 'Bus P20'),
      ],
    );
    await tester.tap(find.text('Scrap'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('receipt scrap'), findsOneWidget);
    expect(find.bySemanticsLabel('ticket scrap'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'bus');
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('receipt scrap'), findsNothing);
    await tester.tap(find.bySemanticsLabel('ticket scrap'));
    await tester.pumpAndSettle();
    expect(find.text('Add a scrap'), findsNothing); // picked and closed
  });

  testWidgets('drawing adds a stroke you can undo', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Draw'));
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsOneWidget);

    final page = tester.getCenter(find.byType(DrawLayer));
    final pen = await tester.startGesture(page);
    for (var i = 0; i < 10; i++) {
      await pen.moveBy(const Offset(8, 4));
      await tester.pump();
    }
    await pen.up();
    await tester.pumpAndSettle();
    expect(find.byType(StrokeView), findsOneWidget);

    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(find.byType(StrokeView), findsNothing);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Draw'), findsOneWidget);
  });

  testWidgets('the eraser lifts off a line it passes over; undo restores it', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Draw'));
    await tester.pumpAndSettle();
    final start = tester.getCenter(find.byType(DrawLayer));
    final pen = await tester.startGesture(start);
    for (var i = 0; i < 10; i++) {
      await pen.moveBy(const Offset(8, 0));
      await tester.pump();
    }
    await pen.up();
    await tester.pumpAndSettle();
    expect(find.byType(StrokeView), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Eraser'));
    await tester.pump();
    final eraser = await tester.startGesture(start + const Offset(40, -30));
    for (var i = 0; i < 6; i++) {
      await eraser.moveBy(const Offset(0, 10));
      await tester.pump();
    }
    await eraser.up();
    await tester.pumpAndSettle();
    expect(find.byType(StrokeView), findsNothing);

    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(find.byType(StrokeView), findsOneWidget);
  });

  testWidgets('a selected caption can be recoloured, and undo restores it', (
    tester,
  ) async {
    await pumpEditor(tester);
    await addCaption(tester, 'paint me');
    Color colorOf() => tester.widget<Text>(find.text('paint me')).style!.color!;
    final before = colorOf();

    await tester.tap(find.text('Colour'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Colour').last); // the gold
    await tester.pumpAndSettle();

    expect(colorOf(), isNot(before));
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(colorOf(), before);
  });

  testWidgets('Text offers caption ideas from the scraps on the page', (
    tester,
  ) async {
    final created = (await tester.runAsync(() => repository.create('Cafe')))!;
    final page = created.pages.single.adding(
      const PageElement(
        id: 'e1',
        kind: ElementKind.scrap,
        cx: 0.5,
        cy: 0.4,
        size: 0.4,
        scrapId: 'r1',
        imagePath: '/missing/r1.png',
      ),
    );
    final journal = created.replacingPage(page);
    final receipt = Scrap(
      id: 'r1',
      pngPath: '/missing/r1.png',
      width: 100,
      height: 100,
      source: ScrapSource.capture,
      createdAt: DateTime(2026, 10, 31),
      captions: const ['two flat whites, no rush'],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          journalRepositoryProvider.overrideWith((ref) async => repository),
          scrapsProvider.overrideWith((ref) async => [receipt]),
        ],
        child: MaterialApp(
          home: EditorScreen(journal: journal, pageId: page.id),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Text'));
    await tester.pumpAndSettle();
    expect(find.text('Ideas from your scraps'), findsOneWidget);
    await tester.tap(find.text('two flat whites, no rush'));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(
      find.text('two flat whites, no rush'),
      findsOneWidget,
    ); // on the page
  });

  testWidgets('delete removes the selected element; undo restores it', (
    tester,
  ) async {
    await pumpEditor(tester);
    await addCaption(tester, 'oops');

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('oops'), findsNothing);

    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('oops'), findsOneWidget);
  });

  testWidgets('edits are saved to the journal', (tester) async {
    final journal = await pumpEditor(tester);
    await tester.tap(find.text('Text'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'saved?');

    // The save runs real file I/O, so trigger and await it in real time.
    final saved = await tester.runAsync(() async {
      await tester.tap(find.text('Done'));
      for (var i = 0; i < 100; i++) {
        await tester.pump();
        final page = (await repository.getAll()).single.pages.single;
        if (page.elements.isNotEmpty) return page;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return null;
    });

    expect(saved?.elements.single.text, 'saved?');
    expect(saved?.id, journal.pages.single.id);
  });
}
