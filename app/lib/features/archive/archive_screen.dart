import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ephemera_ai/features/scan/scan_session_screen.dart';
import 'package:ephemera_ai/models/scrap.dart';
import 'package:ephemera_ai/features/zero_width_guard.dart';
import 'package:ephemera_ai/providers.dart';
import 'package:ephemera_ai/theme.dart';

class ArchiveScreen extends ConsumerWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scraps = ref.watch(scrapsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Scrap archive')),
      body: scraps.when(
        data: (items) =>
            items.isEmpty ? const _EmptyArchive() : _ScrapGrid(scraps: items),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(
            "Couldn't load your archive.\n$error",
            textAlign: TextAlign.center,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        // Both tabs stay alive in the IndexedStack, so their buttons need distinct hero tags.
        heroTag: 'scan-fab',
        onPressed: () => _startScan(context),
        icon: const Icon(Icons.photo_camera_outlined),
        label: const Text('Scan'),
      ),
    );
  }

  Future<void> _startScan(BuildContext context) async {
    final saved = await Navigator.push<int>(
      context,
      MaterialPageRoute(builder: (_) => const ScanSessionScreen()),
    );
    if (saved != null && saved > 0 && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved $saved scrap${saved == 1 ? '' : 's'} to your archive.',
          ),
        ),
      );
    }
  }
}

class _EmptyArchive extends StatelessWidget {
  const _EmptyArchive();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'Your archive is empty.\nSnap your tickets, receipts, tape and pressed flowers to begin.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Palette.inkSoft, height: 1.5),
        ),
      ),
    );
  }
}

class _ScrapGrid extends StatelessWidget {
  const _ScrapGrid({required this.scraps});

  final List<Scrap> scraps;

  @override
  Widget build(BuildContext context) {
    return ZeroWidthGuard(
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
        itemCount: scraps.length,
        itemBuilder: (context, index) => DecoratedBox(
          decoration: BoxDecoration(
            color: Palette.paperDeep,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Image.file(File(scraps[index].pngPath), fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}
