import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ephemera_ai/data/settings_store.dart';

void main() {
  late Directory root;

  setUp(() async => root = await Directory.systemTemp.createTemp('settings'));
  tearDown(() async => root.delete(recursive: true));

  test('has no theme on first run', () async {
    expect(await SettingsStore(root).themeId(), isNull);
  });

  test('remembers the chosen theme', () async {
    await SettingsStore(root).saveThemeId('cozy');

    expect(await SettingsStore(root).themeId(), 'cozy');
  });

  test('a broken settings file falls back to no choice', () async {
    await File('${root.path}/settings.json').writeAsString('{not json');

    expect(await SettingsStore(root).themeId(), isNull);
  });
}
