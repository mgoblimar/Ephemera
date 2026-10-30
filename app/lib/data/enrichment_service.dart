import 'dart:async';
import 'dart:io';

import 'package:ephemera_ai/data/proxy_client.dart';
import 'package:ephemera_ai/data/scrap_repository.dart';
import 'package:ephemera_ai/models/scrap.dart';

/// Enriches archive scraps in the background (Muse Spark, ~₱0.01 each):
/// OCR text, entities, tags, mood and a description, used by archive search
/// and the Theme Blend agent. Failed scraps stay unenriched and are retried
/// on the next run.
class EnrichmentService {
  EnrichmentService({
    required ProxyClient proxy,
    required Future<ScrapRepository> Function() repository,
    required void Function() onUpdated,
    this.concurrency = 2,
  }) : _proxy = proxy,
       _repository = repository,
       _onUpdated = onUpdated;

  final ProxyClient _proxy;
  final Future<ScrapRepository> Function() _repository;
  final void Function() _onUpdated;
  final int concurrency;

  bool _running = false;

  /// Enriches every scrap not yet enriched. Safe to call often: a run already
  /// in progress is not duplicated. Returns how many scraps were enriched.
  Future<int> enrichPending() async {
    if (_running) return 0;
    _running = true;
    try {
      final ScrapRepository repository;
      final List<Scrap> pending;
      try {
        repository = await _repository();
        pending = (await repository.getAll())
            .where((s) => !s.enriched)
            .toList();
      } on Exception {
        return 0; // storage unavailable; nothing to do this run
      }
      var done = 0;
      for (var i = 0; i < pending.length; i += concurrency) {
        final batch = pending.skip(i).take(concurrency);
        final results = await Future.wait(
          batch.map((s) => _enrichOne(repository, s)),
        );
        done += results.where((ok) => ok).length;
        if (results.any((ok) => ok)) _onUpdated();
      }
      return done;
    } finally {
      _running = false;
    }
  }

  Future<bool> _enrichOne(ScrapRepository repository, Scrap scrap) async {
    try {
      final data = await _proxy.enrich(await File(scrap.pngPath).readAsBytes());
      // Merged into the stored copy: the user may have changed it meanwhile.
      return repository.modify(scrap.id, (s) => applyEnrichment(s, data));
    } on ProxyException {
      return false; // network or model trouble: retry on the next run
    } on FileSystemException {
      return false;
    }
  }
}

/// Merges the proxy's enrichment into a scrap. The detector's type wins
/// unless it was unknown; the cut-time palette is kept if the reply has none.
Scrap applyEnrichment(Scrap scrap, Map<String, dynamic> data) {
  List<String> strings(Object? value) => List.unmodifiable(
    (value as List<dynamic>? ?? const []).whereType<String>(),
  );
  final type = data['type'] as String?;
  final palette = strings(data['palette']);
  return scrap.copyWith(
    type: scrap.type == 'other' && type != null ? type : scrap.type,
    ocrText: data['ocr_text'] as String? ?? '',
    tags: strings(data['tags']),
    mood: strings(data['mood']),
    description: data['description'] as String? ?? '',
    journalPrompt: data['journal_prompt'] as String? ?? '',
    captions: strings(data['captions']),
    palette: palette.isEmpty ? scrap.palette : palette,
    entities: Map.unmodifiable(
      (data['entities'] as Map<String, dynamic>? ?? const {}).map(
        (k, v) => MapEntry(k, v.toString()),
      ),
    ),
    enriched: true,
  );
}
