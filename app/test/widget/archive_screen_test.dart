import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ephemera_ai/data/scrap_repository.dart';
import 'package:ephemera_ai/features/archive/archive_screen.dart';
import 'package:ephemera_ai/features/archive/archive_wall.dart';
import 'package:ephemera_ai/features/editor/handwriting.dart';
import 'package:ephemera_ai/models/scrap.dart';
import 'package:ephemera_ai/providers.dart';
import 'package:ephemera_ai/theme.dart';

Scrap _scrap(
  String id,
  String type, {
  List<String> mood = const [],
  String ocr = '',
}) => Scrap(
  id: id,
  pngPath: '/missing/$id.png',
  width: 100,
  height: 120,
  source: ScrapSource.capture,
  createdAt: DateTime.now(),
  type: type,
  mood: mood,
  ocrText: ocr,
  description: 'A $type',
  enriched: true,
);

final _archive = [
  _scrap('r', 'receipt', mood: ['cozy'], ocr: 'Cafe Lumiere'),
  _scrap('t', 'ticket', mood: ['nostalgic'], ocr: 'Bus P20'),
  _scrap('s', 'sticker', mood: ['cozy', 'playful']),
];

/// In-memory archive, so removal runs without file I/O.
class _MemoryArchive implements ScrapRepository {
  _MemoryArchive(List<Scrap> scraps) : _scraps = [...scraps];

  final List<Scrap> _scraps;

  @override
  Future<List<Scrap>> getAll() async => List.unmodifiable(_scraps);

  @override
  Future<void> remove(String id) async =>
      _scraps.removeWhere((s) => s.id == id);

  @override
  Future<void> restore(Scrap scrap) async => _scraps.add(scrap);

  @override
  Future<bool> modify(String id, Scrap Function(Scrap) change) async {
    final i = _scraps.indexWhere((s) => s.id == id);
    if (i < 0) return false;
    _scraps[i] = change(_scraps[i]);
    return true;
  }

  @override
  Future<void> update(Scrap scrap) async {
    final i = _scraps.indexWhere((s) => s.id == scrap.id);
    if (i >= 0) _scraps[i] = scrap;
  }

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() => useGoogleFonts = false);

  Future<void> pumpArchive(WidgetTester tester, List<Scrap> scraps) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [scrapsProvider.overrideWith((ref) async => scraps)],
        child: MaterialApp(theme: buildTheme(), home: const ArchiveScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an empty archive invites a first scan', (tester) async {
    await pumpArchive(tester, const []);

    expect(find.text('Your archive is empty'), findsOneWidget);
  });

  testWidgets('search narrows the wall and shows the count', (tester) async {
    await pumpArchive(tester, _archive);
    expect(find.byType(ScrapCard), findsNWidgets(3));
    expect(find.text('3 scraps'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'lumiere');
    await tester.pumpAndSettle();

    expect(find.byType(ScrapCard), findsOneWidget);
    expect(find.text('1 of 3 scraps'), findsOneWidget);
  });

  testWidgets('picking a vibe filters, and clear all resets', (tester) async {
    await pumpArchive(tester, _archive);

    await tester.tap(find.text('Vibe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('cozy'));
    await tester.pump();
    await tester.tap(find.text('Show scraps'));
    await tester.pumpAndSettle();

    expect(find.byType(ScrapCard), findsNWidgets(2));
    expect(find.text('Vibe · 1'), findsOneWidget);

    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    expect(find.byType(ScrapCard), findsNWidgets(3));
  });

  testWidgets('no matches offers to clear filters', (tester) async {
    await pumpArchive(tester, _archive);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();

    expect(find.text('No scraps match'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.byType(ScrapCard), findsNWidgets(3));
  });

  testWidgets('tapping a scrap opens its details', (tester) async {
    await pumpArchive(tester, _archive);

    await tester.tap(find.bySemanticsLabel('ticket scrap'));
    await tester.pumpAndSettle();

    expect(find.text('A ticket'), findsOneWidget);
    expect(find.text('“Bus P20”'), findsOneWidget);
  });

  testWidgets('removing a scrap takes it off the wall; undo brings it back', (
    tester,
  ) async {
    final archive = _MemoryArchive(_archive);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scrapRepositoryProvider.overrideWith((ref) async => archive),
          scrapsProvider.overrideWith(
            (ref) async =>
                (await ref.watch(scrapRepositoryProvider.future)).getAll(),
          ),
        ],
        child: MaterialApp(theme: buildTheme(), home: const ArchiveScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('ticket scrap'));
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Remove from archive'),
      find.byType(ListView).last,
      const Offset(0, -200),
    );
    await tester.tap(find.text('Remove from archive'));
    await tester.pumpAndSettle();

    expect(find.byType(ScrapCard), findsNWidgets(2));
    expect(find.text('Removed the ticket from your archive.'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.byType(ScrapCard), findsNWidgets(3));
  });

  testWidgets('an active filter chip removes just that filter', (tester) async {
    await pumpArchive(tester, _archive);
    await tester.tap(find.text('Vibe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('cozy'));
    await tester.pump();
    await tester.tap(find.text('Show scraps'));
    await tester.pumpAndSettle();
    expect(find.byType(ScrapCard), findsNWidgets(2));

    await tester.tap(find.byTooltip('Remove cozy'));
    await tester.pumpAndSettle();

    expect(find.byType(ScrapCard), findsNWidgets(3));
    expect(find.byType(InputChip), findsNothing);
  });

  testWidgets(
    'marking a scrap as used saves it and the Status filter finds it',
    (tester) async {
      final archive = _MemoryArchive(_archive);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            scrapRepositoryProvider.overrideWith((ref) async => archive),
            scrapsProvider.overrideWith(
              (ref) async =>
                  (await ref.watch(scrapRepositoryProvider.future)).getAll(),
            ),
          ],
          child: MaterialApp(theme: buildTheme(), home: const ArchiveScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('ticket scrap'));
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.text('Used in a spread'),
        find.byType(ListView).last,
        const Offset(0, -200),
      );
      await tester.tap(find.text('Used in a spread'));
      await tester.pumpAndSettle();
      expect(find.text('Theme Blend will leave it out.'), findsOneWidget);
      expect(
        (await archive.getAll()).firstWhere((s) => s.id == 't').physicalStatus,
        PhysicalStatus.used,
      );

      await tester.tapAt(const Offset(10, 10)); // close the sheet
      await tester.pumpAndSettle();
      await tester.tap(find.text('Status'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Used in a spread'));
      await tester.pump();
      await tester.tap(find.text('Show scraps'));
      await tester.pumpAndSettle();

      expect(find.byType(ScrapCard), findsOneWidget);
      expect(find.bySemanticsLabel('ticket scrap'), findsOneWidget);
    },
  );
}
