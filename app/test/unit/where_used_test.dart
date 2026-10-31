import 'package:flutter_test/flutter_test.dart';

import 'package:ephemera_ai/features/archive/where_used.dart';
import 'package:ephemera_ai/models/journal.dart';

JournalPage _page(String id, List<String> scrapIds) => JournalPage(
  id: id,
  elements: [
    for (final s in scrapIds)
      PageElement(
        id: '$id-$s',
        kind: ElementKind.scrap,
        cx: 0.5,
        cy: 0.5,
        size: 0.3,
        scrapId: s,
      ),
  ],
);

Journal _journal(String title, DateTime created, List<JournalPage> pages) =>
    Journal(id: title, title: title, createdAt: created, pages: pages);

void main() {
  test('names the newest journal and the last page holding the scrap', () {
    final journals = [
      _journal('Kyoto', DateTime.utc(2026, 10, 1), [
        _page('k1', ['ticket']),
      ]),
      _journal('Cat cafe', DateTime.utc(2026, 10, 30), [
        _page('c1', ['ticket']),
        _page('c2', []),
        _page('c3', ['ticket', 'receipt']),
      ]),
    ];

    expect(whereUsed('ticket', journals), 'Cat cafe, page 3');
    expect(whereUsed('receipt', journals), 'Cat cafe, page 3');
  });

  test('is null for a scrap on no page', () {
    final journals = [
      _journal('Kyoto', DateTime.utc(2026, 10, 1), [
        _page('k1', ['ticket']),
      ]),
    ];

    expect(whereUsed('sticker', journals), isNull);
    expect(whereUsed('ticket', const []), isNull);
  });
}
