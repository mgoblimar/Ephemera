import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ephemera_ai/features/home_shell.dart';
import 'package:ephemera_ai/theme.dart';

void main() {
  runApp(const ProviderScope(child: EphemeraApp()));
}

class EphemeraApp extends StatelessWidget {
  const EphemeraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EphemeraAI',
      theme: buildTheme(),
      home: const HomeShell(),
    );
  }
}
