import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ephemera_ai/data/settings_store.dart';
import 'package:ephemera_ai/features/editor/handwriting.dart';
import 'package:ephemera_ai/features/library/theme_picker.dart';
import 'package:ephemera_ai/providers.dart';
import 'package:ephemera_ai/theme.dart';

/// The app's theme wiring (as in main.dart) around a page with the picker.
class _App extends ConsumerWidget {
  const _App();

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    theme: buildTheme(themes[ref.watch(themeIdProvider)] ?? deskTokens),
    home: Scaffold(
      appBar: AppBar(actions: const [ThemePickerButton()]),
      body: Builder(builder: (context) => Text(context.tokens.name)),
    ),
  );
}

void main() {
  late Directory root;

  setUpAll(() => useGoogleFonts = false);
  setUp(() async => root = await Directory.systemTemp.createTemp('theme'));
  tearDown(() async => root.delete(recursive: true));

  testWidgets('choosing Cozy cat restyles the app and is saved', (
    tester,
  ) async {
    final store = SettingsStore(root);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsStoreProvider.overrideWith((ref) async => store)],
        child: const _App(),
      ),
    );
    await tester.pump();
    expect(find.text('Desk'), findsOneWidget);

    await tester.tap(find.byTooltip('Theme'));
    await tester.pumpAndSettle();
    final saved = await tester.runAsync(() async {
      await tester.tap(find.text('Cozy cat'));
      for (var i = 0; i < 100; i++) {
        await tester.pump();
        final id = await store.themeId();
        if (id != null) return id;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return null;
    });
    await tester.pumpAndSettle();

    expect(saved, 'cozy');
    expect(
      find.descendant(
        of: find.byType(Scaffold),
        matching: find.text('Cozy cat'),
      ),
      findsWidgets,
    );
    expect(
      Theme.of(
        tester.element(find.byType(Scaffold)),
      ).extension<EphemeraTokens>(),
      cozyCatTokens,
    );
  });
}
