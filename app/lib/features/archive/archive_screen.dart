import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ephemera_ai/features/archive/archive_filter_bar.dart';
import 'package:ephemera_ai/features/archive/archive_wall.dart';
import 'package:ephemera_ai/features/archive/scrap_detail_sheet.dart';
import 'package:ephemera_ai/features/archive/scrap_filter.dart';
import 'package:ephemera_ai/features/scan/scan_session_screen.dart';
import 'package:ephemera_ai/features/zero_width_guard.dart';
import 'package:ephemera_ai/models/scrap.dart';
import 'package:ephemera_ai/providers.dart';
import 'package:ephemera_ai/theme.dart';

class ArchiveScreen extends ConsumerStatefulWidget {
  const ArchiveScreen({super.key});

  @override
  ConsumerState<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends ConsumerState<ArchiveScreen> {
  final _search = TextEditingController();
  ScrapFilter _filter = ScrapFilter.none;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scraps = ref.watch(scrapsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Scrap archive')),
      body: scraps.when(
        data: (items) =>
            items.isEmpty ? const _EmptyArchive() : _filtered(items),
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

  Widget _filtered(List<Scrap> all) {
    final tokens = context.tokens;
    final shown = applyFilter(all, _filter);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ArchiveFilterBar(
          filter: _filter,
          facets: FilterFacets.of(all),
          searchController: _search,
          onChanged: (f) => setState(() => _filter = f),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
          child: Row(
            children: [
              Text(
                _filter.isEmpty
                    ? '${all.length} scraps'
                    : '${shown.length} of ${all.length} scraps',
                style: TextStyle(color: tokens.inkSoft),
              ),
              const Spacer(),
              if (!_filter.isEmpty)
                TextButton(onPressed: _clear, child: const Text('Clear all')),
            ],
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? _NoMatches(onClear: _clear)
              : ZeroWidthGuard(
                  child: ScrapWall(
                    scraps: shown,
                    onTap: (s) => showScrapDetail(context, s),
                  ),
                ),
        ),
      ],
    );
  }

  void _clear() {
    _search.clear();
    setState(() => _filter = ScrapFilter.none);
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
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_activity_outlined, size: 56, color: tokens.accent),
            const SizedBox(height: 12),
            Text('Your archive is empty', style: tokens.display(22)),
            const SizedBox(height: 8),
            Text(
              'Snap your tickets, receipts, tape and pressed flowers to begin.',
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.inkSoft, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('No scraps match', style: tokens.hand(26)),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: onClear,
            child: const Text('Clear filters'),
          ),
        ],
      ),
    );
  }
}
