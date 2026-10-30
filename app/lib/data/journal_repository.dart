import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:ephemera_ai/models/journal.dart';

abstract interface class JournalRepository {
  Future<List<Journal>> getAll();

  Future<Journal> create(String title, {int coverColor});

  /// Saves the whole journal (pages included).
  Future<void> save(Journal journal);

  Future<void> delete(String journalId);
}

/// Local journals in one JSON file next to the scrap archive.
class FileJournalRepository implements JournalRepository {
  FileJournalRepository(
    this._root, {
    Uuid uuid = const Uuid(),
    DateTime Function()? clock,
  }) : _uuid = uuid,
       _clock = clock ?? DateTime.now;

  final Directory _root;
  final Uuid _uuid;
  final DateTime Function() _clock;

  File get _file => File(p.join(_root.path, 'journals.json'));

  @override
  Future<List<Journal>> getAll() async {
    if (!await _file.exists()) return const [];
    final raw = jsonDecode(await _file.readAsString()) as List<dynamic>;
    return List.unmodifiable(
      raw.map((j) => Journal.fromJson(j as Map<String, dynamic>)),
    );
  }

  @override
  Future<Journal> create(String title, {int coverColor = 0xFFB5603F}) async {
    final journal = Journal(
      id: _uuid.v4(),
      title: title,
      createdAt: _clock(),
      coverColor: coverColor,
      pages: [JournalPage(id: _uuid.v4())],
    );
    await _write([...await getAll(), journal]);
    return journal;
  }

  @override
  Future<void> save(Journal journal) async {
    final all = await getAll();
    final exists = all.any((j) => j.id == journal.id);
    await _write([
      for (final j in all) j.id == journal.id ? journal : j,
      if (!exists) journal,
    ]);
  }

  @override
  Future<void> delete(String journalId) async {
    await _write([
      for (final j in await getAll())
        if (j.id != journalId) j,
    ]);
  }

  /// Temp file + rename, so a crash mid-write can't corrupt the journals.
  Future<void> _write(List<Journal> journals) async {
    await _root.create(recursive: true);
    final temp = File('${_file.path}.tmp');
    await temp.writeAsString(
      jsonEncode([for (final j in journals) j.toJson()]),
      flush: true,
    );
    await temp.rename(_file.path);
  }
}
