import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:ephemera_ai/config.dart';
import 'package:ephemera_ai/data/proxy_client.dart';
import 'package:ephemera_ai/data/journal_repository.dart';
import 'package:ephemera_ai/data/scrap_repository.dart';
import 'package:ephemera_ai/models/journal.dart';
import 'package:ephemera_ai/models/scrap.dart';

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
