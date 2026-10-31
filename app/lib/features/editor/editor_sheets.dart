import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ephemera_ai/features/archive/archive_filter_bar.dart';
import 'package:ephemera_ai/features/archive/scrap_filter.dart';
import 'package:ephemera_ai/features/editor/handwriting.dart';
import 'package:ephemera_ai/models/journal.dart';
import 'package:ephemera_ai/models/scrap.dart';
import 'package:ephemera_ai/providers.dart';
import 'package:ephemera_ai/theme.dart';

/// Bottom sheet listing archive scraps, with the archive's filters; returns
/// the tapped one.
Future<Scrap?> pickScrap(BuildContext context) {
  return showModalBottomSheet<Scrap>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const FractionallySizedBox(
      heightFactor: 0.85,
      child: _ScrapPickerSheet(),
    ),
  );
}

class _ScrapPickerSheet extends ConsumerStatefulWidget {
  const _ScrapPickerSheet();

  @override
  ConsumerState<_ScrapPickerSheet> createState() => _ScrapPickerSheetState();
}

class _ScrapPickerSheetState extends ConsumerState<_ScrapPickerSheet> {
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
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Add a scrap', style: TextStyle(fontSize: 18)),
        ),
        Expanded(
          child: scraps.when(
            data: (items) => items.isEmpty
                ? const Center(
                    child: Text(
                      'Your archive is empty. Scan some scraps first.',
                    ),
                  )
                : _filtered(items),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text("Couldn't load scraps: $e")),
          ),
        ),
      ],
    );
  }

  Widget _filtered(List<Scrap> all) {
    final shown = applyFilter(all, _filter);
    return Column(
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
        const SizedBox(height: 8),
        Expanded(
          child: shown.isEmpty
              ? const Center(child: Text('No scraps match'))
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 120,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  itemCount: shown.length,
                  itemBuilder: (context, i) => Semantics(
                    label: '${shown[i].type} scrap',
                    button: true,
                    child: InkWell(
                      onTap: () => Navigator.pop(context, shown[i]),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: context.tokens.paperDeep,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Image.file(
                            File(shown[i].pngPath),
                            fit: BoxFit.contain,
                            cacheWidth: 240,
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

typedef TextChoice = ({String text, String font});

/// Dialog for writing (or editing) a handwritten caption. [ideas] are offered
/// as one-tap suggestions (caption ideas from the scraps on the page).
Future<TextChoice?> editText(
  BuildContext context, {
  String initialText = '',
  String initialFont = 'Caveat',
  List<String> ideas = const [],
}) {
  return showDialog<TextChoice>(
    context: context,
    builder: (_) => _TextDialog(
      initialText: initialText,
      initialFont: initialFont,
      ideas: ideas,
    ),
  );
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.initialText,
    required this.initialFont,
    this.ideas = const [],
  });

  final String initialText;
  final String initialFont;
  final List<String> ideas;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );
  late String _font = widget.initialFont;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Write something first');
      return;
    }
    Navigator.pop(context, (text: text, font: _font));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // Scrolls when the keyboard leaves little room (landscape tablet).
      scrollable: true,
      title: const Text('Caption'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 3,
            minLines: 1,
            onChanged: (_) => setState(() => _error = null),
            decoration: InputDecoration(
              hintText: 'A slow Sunday morning…',
              errorText: _error,
            ),
          ),
          if (widget.ideas.isNotEmpty) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Ideas from your scraps',
                style: TextStyle(color: context.tokens.inkSoft, fontSize: 12),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final idea in widget.ideas)
                  ActionChip(
                    label: Text(idea, style: handwriting(_font, fontSize: 16)),
                    onPressed: () => setState(() {
                      _controller.text = idea;
                      _error = null;
                    }),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final font in handwritingFonts)
                ChoiceChip(
                  label: Text(font, style: handwriting(font, fontSize: 16)),
                  selected: font == _font,
                  onSelected: (_) => setState(() => _font = font),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Done')),
      ],
    );
  }
}
