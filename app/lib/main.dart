import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ephemera_ai/features/home_shell.dart';
import 'package:ephemera_ai/providers.dart';
import 'package:ephemera_ai/theme.dart';

void main() {
  runApp(const ProviderScope(child: EphemeraApp()));
}

class EphemeraApp extends ConsumerWidget {
  const EphemeraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = themes[ref.watch(themeIdProvider)] ?? deskTokens;
    return MaterialApp(
      title: 'EphemeraAI',
      theme: buildTheme(tokens),
      home: const HomeShell(),
    );
  }
}
