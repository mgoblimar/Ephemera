import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:ephemera_ai/config.dart';
import 'package:ephemera_ai/data/proxy_client.dart';
import 'package:ephemera_ai/data/enrichment_service.dart';
import 'package:ephemera_ai/data/journal_repository.dart';
import 'package:ephemera_ai/data/scrap_repository.dart';
import 'package:ephemera_ai/data/settings_store.dart';
import 'package:ephemera_ai/models/journal.dart';
import 'package:ephemera_ai/models/scrap.dart';
import 'package:ephemera_ai/theme.dart';

final proxyClientProvider = Provider<ProxyClient>(
  (ref) => ProxyClient(baseUrl: proxyUrl),
);

final scrapRepositoryProvider = FutureProvider<ScrapRepository>((ref) async {
  final docs = await getApplicationDocumentsDirectory();
  return FileScrapRepository(Directory(p.join(docs.path, 'archive')));
});

/// All scraps, newest first. Invalidate after saving to refresh the archive.
final scrapsProvider = FutureProvider<List<Scrap>>((ref) async {
  final repository = await ref.watch(scrapRepositoryProvider.future);
  return repository.getAll();
});

final journalRepositoryProvider = FutureProvider<JournalRepository>((
  ref,
) async {
  final docs = await getApplicationDocumentsDirectory();
  return FileJournalRepository(Directory(p.join(docs.path, 'journals')));
});

/// All journals. Invalidate after creating or saving one.
final journalsProvider = FutureProvider<List<Journal>>((ref) async {
  final repository = await ref.watch(journalRepositoryProvider.future);
  return repository.getAll();
});

final settingsStoreProvider = FutureProvider<SettingsStore>((ref) async {
  final docs = await getApplicationDocumentsDirectory();
  return SettingsStore(Directory(docs.path));
});

/// The chosen theme's id; starts on Desk and switches once the saved choice loads.
final themeIdProvider = NotifierProvider<ThemeIdNotifier, String>(
  ThemeIdNotifier.new,
);

class ThemeIdNotifier extends Notifier<String> {
  @override
  String build() {
    unawaited(_loadSaved());
    return deskTokens.id;
  }

  Future<void> _loadSaved() async {
    final store = await ref.read(settingsStoreProvider.future);
    final saved = await store.themeId();
    if (saved != null && themes.containsKey(saved)) state = saved;
  }

  Future<void> choose(String id) async {
    if (!themes.containsKey(id)) return;
    state = id;
    final store = await ref.read(settingsStoreProvider.future);
    await store.saveThemeId(id);
  }
}

/// Background scrap enrichment; trigger with `enrichPending()` after saving.
final enrichmentServiceProvider = Provider<EnrichmentService>((ref) {
  return EnrichmentService(
    proxy: ref.watch(proxyClientProvider),
    repository: () => ref.read(scrapRepositoryProvider.future),
    onUpdated: () => ref.invalidate(scrapsProvider),
  );
});
