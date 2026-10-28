import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ephemera_ai/features/archive/archive_screen.dart';
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
      home: const ArchiveScreen(),
    );
  }
}
