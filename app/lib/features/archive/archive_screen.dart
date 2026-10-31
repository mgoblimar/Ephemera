import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ephemera_ai/features/archive/archive_filter_bar.dart';
import 'package:ephemera_ai/features/archive/archive_wall.dart';
import 'package:ephemera_ai/features/archive/scrap_detail_sheet.dart';
import 'package:ephemera_ai/features/archive/scrap_filter.dart';
import 'package:ephemera_ai/features/archive/where_used.dart';
import 'package:ephemera_ai/features/scan/scan_session_screen.dart';
import 'package:ephemera_ai/features/zero_width_guard.dart';
import 'package:ephemera_ai/models/journal.dart';
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

  /// Scraps picked by long-press; non-empty means selection mode.
  Set<String> _selected = {};
  bool get _selecting => _selected.isNotEmpty;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scraps = ref.watch(scrapsProvider);
    ref.watch(journalsProvider); // loaded early for "Used in" suggestions
    final all = scraps.value ?? const <Scrap>[];
    return PopScope(
      // Back leaves selection mode first.
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _selected = {});
      },
      child: _scaffold(scraps, all),
    );
  }

  Widget _scaffold(AsyncValue<List<Scrap>> scraps, List<Scrap> all) {
    return Scaffold(
      appBar: _selecting
          ? _selectionBar(all)
          : AppBar(title: const Text('Scrap archive')),
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
      floatingActionButton: _selecting
          ? null
          : FloatingActionButton.extended(
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
                    selected: _selected,
                    onLongPress: _toggle,
                    onTap: (s) => _selecting
                        ? _toggle(s)
                        : showScrapDetail(
                            context,
                            s,
                            onRemove: () => _remove([s]),
                            onStatus: (status) => _setStatus([s], status),
                            onUsedIn: (note) => _setUsedIn(s, note),
                            suggestedNote: whereUsed(s.id, _journals),
                          ),
                  ),
                ),
        ),
      ],
    );
  }

  void _toggle(Scrap scrap) => setState(() {
    _selected = _selected.contains(scrap.id)
        ? ({..._selected}..remove(scrap.id))
        : {..._selected, scrap.id};
  });

  AppBar _selectionBar(List<Scrap> all) {
    final picked = all.where((s) => _selected.contains(s.id)).toList();
    final shown = applyFilter(all, _filter);
    return AppBar(
      leading: IconButton(
        tooltip: 'Cancel selection',
        icon: const Icon(Icons.close),
        onPressed: () => setState(() => _selected = {}),
      ),
      title: Text('${picked.length} selected'),
      actions: [
        IconButton(
          tooltip: 'Select all shown',
          icon: const Icon(Icons.select_all),
          onPressed: () =>
              setState(() => _selected = {for (final s in shown) s.id}),
        ),
        PopupMenuButton<PhysicalStatus>(
          tooltip: 'Set status',
          icon: const Icon(Icons.bookmark_added_outlined),
          onSelected: (status) {
            _setStatus(picked, status);
            setState(() => _selected = {});
          },
          itemBuilder: (_) => [
            for (final status in PhysicalStatus.values)
              PopupMenuItem(value: status, child: Text(status.label)),
          ],
        ),
        IconButton(
          tooltip: 'Remove from archive',
          icon: const Icon(Icons.delete_outline),
          onPressed: () {
            _remove(picked);
            setState(() => _selected = {});
          },
        ),
      ],
    );
  }

  /// Journals as loaded so far (for "Used in" suggestions); empty until then.
  List<Journal> get _journals =>
      ref.read(journalsProvider).valueOrNull ?? const [];

  /// Sets the status; scraps marked used without a note get where they were
  /// last placed in the app ("Kyoto, page 4").
  Future<void> _setStatus(List<Scrap> scraps, PhysicalStatus status) async {
    final repository = await ref.read(scrapRepositoryProvider.future);
    // Journals are watched in build, so they're usually loaded by now; if
    // not, the status still saves, just without a suggested note.
    final journals = status == PhysicalStatus.used
        ? _journals
        : const <Journal>[];
    for (final scrap in scraps) {
      await repository.modify(scrap.id, (s) {
        final note = s.usedIn.isEmpty ? whereUsed(s.id, journals) : null;
        return s.copyWith(physicalStatus: status, usedIn: note);
      });
    }
    ref.invalidate(scrapsProvider);
  }

  Future<void> _setUsedIn(Scrap scrap, String note) async {
    final repository = await ref.read(scrapRepositoryProvider.future);
    await repository.modify(scrap.id, (s) => s.copyWith(usedIn: note));
    ref.invalidate(scrapsProvider);
  }

  /// Removes junk scraps, with a few seconds to change your mind.
  Future<void> _remove(List<Scrap> scraps) async {
    if (scraps.isEmpty) return;
    final repository = await ref.read(scrapRepositoryProvider.future);
    for (final scrap in scraps) {
      await repository.remove(scrap.id);
    }
    ref.invalidate(scrapsProvider);
    if (!mounted) return;
    final what = scraps.length == 1
        ? 'the ${scraps.single.type}'
        : '${scraps.length} scraps';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Removed $what from your archive.'),
          // Flutter keeps snack bars with an action open unless told not to.
          persist: false,
          duration: _undoWindow,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              for (final scrap in scraps) {
                await repository.restore(scrap);
              }
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

const _undoWindow = Duration(seconds: 4);

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
