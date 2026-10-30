import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ephemera_ai/features/library/book_screen.dart';
import 'package:ephemera_ai/features/library/journal_cover.dart';
import 'package:ephemera_ai/models/journal.dart';
import 'package:ephemera_ai/features/zero_width_guard.dart';
import 'package:ephemera_ai/providers.dart';
import 'package:ephemera_ai/features/empty_state.dart';

const coverColors = [
  0xFFB5603F,
  0xFF6F7F5A,
  0xFF3D5A80,
  0xFF8E5572,
  0xFF2F2A26,
];

/// The shelf of journals.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final journals = ref.watch(journalsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Journals')),
      body: journals.when(
        data: (items) => items.isEmpty
            ? const _EmptyShelf()
            : ZeroWidthGuard(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    childAspectRatio: 1 / pageAspect,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) => JournalCover(
                    journal: items[i],
                    onTap: () => _open(context, items[i]),
                  ),
                ),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text("Couldn't load journals: $e")),
      ),
      floatingActionButton: FloatingActionButton.extended(
        // Both tabs stay alive in the IndexedStack, so their buttons need distinct hero tags.
        heroTag: 'new-journal-fab',
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New journal'),
      ),
    );
  }

  void _open(BuildContext context, Journal journal) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BookScreen(journalId: journal.id)),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => const _TitleDialog(),
    );
    if (title == null) return;
    final repository = await ref.read(journalRepositoryProvider.future);
    final count = (await repository.getAll()).length;
    final journal = await repository.create(
      title,
      coverColor: coverColors[count % coverColors.length],
    );
    ref.invalidate(journalsProvider);
    if (context.mounted) _open(context, journal);
  }
}

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf();

  @override
  Widget build(BuildContext context) => const EmptyState(
    icon: Icons.menu_book_outlined,
    title: 'No journals yet',
    hint: 'Start one, then fill its pages with your scraps.',
  );
}

class _TitleDialog extends StatefulWidget {
  const _TitleDialog();

  @override
  State<_TitleDialog> createState() => _TitleDialogState();
}

class _TitleDialogState extends State<_TitleDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _controller.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Give your journal a name');
      return;
    }
    Navigator.pop(context, title);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New journal'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        onChanged: (_) => setState(() => _error = null),
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: 'Kyoto, rainy days',
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}
