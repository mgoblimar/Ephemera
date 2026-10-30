import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Small on-device preferences, kept as one JSON file (like the archive index).
class SettingsStore {
  SettingsStore(this.root);

  final Directory root;

  File get _file => File(p.join(root.path, 'settings.json'));

  Future<String?> themeId() async {
    try {
      final data = jsonDecode(await _file.readAsString());
      return data is Map<String, dynamic> ? data['theme'] as String? : null;
    } on FileSystemException {
      return null; // first run
    } on FormatException {
      return null; // unreadable file: fall back to the default theme
    }
  }

  Future<void> saveThemeId(String id) async {
    await root.create(recursive: true);
    await _file.writeAsString(jsonEncode({'theme': id}));
  }
}
