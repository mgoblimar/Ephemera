import 'package:ephemera_ai/models/journal.dart';

/// Where a scrap was last placed in the app, as a "Used in" note
/// ("Kyoto, page 4"): the newest journal holding it, and its last page there.
/// Null when it isn't on any page.
String? whereUsed(String scrapId, List<Journal> journals) {
  final newestFirst = [...journals]
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  for (final journal in newestFirst) {
    for (var i = journal.pages.length - 1; i >= 0; i--) {
      if (journal.pages[i].elements.any((e) => e.scrapId == scrapId)) {
        return '${journal.title}, page ${i + 1}';
      }
    }
  }
  return null;
}
