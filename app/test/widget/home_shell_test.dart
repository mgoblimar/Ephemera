import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ephemera_ai/features/editor/handwriting.dart';
import 'package:ephemera_ai/features/home_shell.dart';
import 'package:ephemera_ai/models/journal.dart';
import 'package:ephemera_ai/providers.dart';

void main() {
  setUpAll(() => useGoogleFonts = false);

  testWidgets('opening a journal from the shelf navigates without errors', (
    tester,
  ) async {
    final journal = Journal(
      id: 'j1',
      title: 'Kyoto',
      createdAt: DateTime.utc(2026, 10, 30),
      pages: const [JournalPage(id: 'p1')],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          journalsProvider.overrideWith((ref) async => [journal]),
          scrapsProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: HomeShell()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kyoto'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull); // e.g. duplicate hero tags
    expect(find.text('Page 1 of 1 · tap to edit'), findsOneWidget);
  });
}
