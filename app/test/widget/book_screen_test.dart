import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ephemera_ai/data/journal_repository.dart';
import 'package:ephemera_ai/features/editor/handwriting.dart';
import 'package:ephemera_ai/features/library/book_look.dart';
import 'package:ephemera_ai/features/library/book_screen.dart';
import 'package:ephemera_ai/models/journal.dart';
import 'package:ephemera_ai/models/scrap.dart';
import 'package:ephemera_ai/providers.dart';
import 'package:ephemera_ai/theme.dart';

/// In-memory journals, so the book screen runs without file I/O.
class _MemoryJournals implements JournalRepository {
  _MemoryJournals(this.journal);

  Journal journal;

  @override
  Future<List<Journal>> getAll() async => [journal];

  @override
  Future<void> save(Journal updated) async => journal = updated;

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() => useGoogleFonts = false);

  testWidgets('the book style sheet changes binding and background', (
    tester,
  ) async {
    final journals = _MemoryJournals(
      Journal(
        id: 'j',
        title: 'Kyoto',
        createdAt: DateTime.utc(2026, 11, 1),
        pages: const [
          JournalPage(id: 'p1'),
          JournalPage(id: 'p2', paper: PaperStyle.kraft),
        ],
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          journalRepositoryProvider.overrideWith((ref) async => journals),
          scrapsProvider.overrideWith((ref) async => const <Scrap>[]),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: const BookScreen(journalId: 'j'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<BindingEdge>(find.byType(BindingEdge)).binding,
      BookBinding.book,
    );

    await tester.tap(find.byTooltip('Book style and background'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notebook'));
    await tester.pump();
    await tester.tap(find.text('Lined'));
    await tester.pump();
    await tester.ensureVisible(find.text('Cork'));
    await tester.tap(find.text('Cork'));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(journals.journal.binding, BookBinding.notebook);
    expect(journals.journal.backdrop, BookBackdrop.cork);
    expect(
      journals.journal.pages.map((p) => p.paper),
      everyElement(PaperStyle.lined),
    );
    expect(
      tester.widget<BindingEdge>(find.byType(BindingEdge)).binding,
      BookBinding.notebook,
    );
  });
}
