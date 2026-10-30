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
import 'package:ephemera_ai/features/empty_state.dart';

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
        ActiveFilterChips(
          filter: _filter,
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
                    onTap: (s) => showScrapDetail(
                      context,
                      s,
                      onRemove: () => _remove(s),
                      onStatus: (status) => _setStatus(s, status),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _setStatus(Scrap scrap, PhysicalStatus status) async {
    final repository = await ref.read(scrapRepositoryProvider.future);
    await repository.modify(
      scrap.id,
      (s) => s.copyWith(physicalStatus: status),
    );
    ref.invalidate(scrapsProvider);
  }

  /// Removes a junk scrap, with a few seconds to change your mind.
  Future<void> _remove(Scrap scrap) async {
    final repository = await ref.read(scrapRepositoryProvider.future);
    await repository.remove(scrap.id);
    ref.invalidate(scrapsProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed the ${scrap.type} from your archive.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await repository.restore(scrap);
            ref.invalidate(scrapsProvider);
          },
        ),
      ),
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
  Widget build(BuildContext context) => const EmptyState(
    icon: Icons.local_activity_outlined,
    title: 'Your archive is empty',
    hint: 'Snap your tickets, receipts, tape and pressed flowers to begin.',
  );
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
