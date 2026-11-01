import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ephemera_ai/features/home_shell.dart';
import 'package:ephemera_ai/providers.dart';
import 'package:ephemera_ai/theme.dart';

void main() {
  // The Open Font License asks for its text to travel with the font.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Open Sauce Sans',
    ], await rootBundle.loadString('assets/fonts/OpenSauceSans-OFL.txt'));
  });
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
