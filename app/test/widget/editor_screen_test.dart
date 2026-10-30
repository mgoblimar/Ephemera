import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ephemera_ai/data/journal_repository.dart';
import 'package:ephemera_ai/features/editor/editor_screen.dart';
import 'package:ephemera_ai/features/editor/handwriting.dart';
import 'package:ephemera_ai/models/journal.dart';
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

  Future<Journal> pumpEditor(WidgetTester tester) async {
    final journal = (await tester.runAsync(() => repository.create('Kyoto')))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          journalRepositoryProvider.overrideWith((ref) async => repository),
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
