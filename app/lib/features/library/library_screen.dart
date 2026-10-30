import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ephemera_ai/features/library/book_screen.dart';
import 'package:ephemera_ai/models/journal.dart';
import 'package:ephemera_ai/features/zero_width_guard.dart';
import 'package:ephemera_ai/providers.dart';
import 'package:ephemera_ai/theme.dart';

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

class JournalCover extends StatelessWidget {
  const JournalCover({super.key, required this.journal, required this.onTap});

  final Journal journal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pages = journal.pages.length;
    return Material(
      color: Color(journal.coverColor),
      borderRadius: const BorderRadius.horizontal(
        left: Radius.circular(4),
        right: Radius.circular(10),
      ),
      elevation: 3,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            // Spine
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 12,
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.18)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    journal.title,
                    style: const TextStyle(
                      color: Palette.paper,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                  Text(
                    '$pages page${pages == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: Palette.paper.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'No journals yet.\nStart one, then fill its pages with your scraps.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Palette.inkSoft, height: 1.5),
        ),
      ),
    );
  }
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
