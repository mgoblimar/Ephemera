import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ephemera_ai/features/editor/handwriting.dart';
import 'package:ephemera_ai/models/journal.dart';
import 'package:ephemera_ai/models/scrap.dart';
import 'package:ephemera_ai/providers.dart';
import 'package:ephemera_ai/theme.dart';

/// Bottom sheet listing archive scraps; returns the tapped one.
Future<Scrap?> pickScrap(BuildContext context) {
  return showModalBottomSheet<Scrap>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const FractionallySizedBox(
      heightFactor: 0.7,
      child: _ScrapPickerSheet(),
    ),
  );
}

class _ScrapPickerSheet extends ConsumerWidget {
  const _ScrapPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 120,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                        ),
                    itemCount: items.length,
                    itemBuilder: (context, i) => InkWell(
                      onTap: () => Navigator.pop(context, items[i]),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Palette.paperDeep,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Image.file(
                            File(items[i].pngPath),
                            fit: BoxFit.contain,
                            cacheWidth: 240,
                          ),
                        ),
                      ),
                    ),
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text("Couldn't load scraps: $e")),
          ),
        ),
      ],
    );
  }
}

typedef TextChoice = ({String text, String font});

/// Dialog for writing (or editing) a handwritten caption.
Future<TextChoice?> editText(
  BuildContext context, {
  String initialText = '',
  String initialFont = 'Caveat',
}) {
  return showDialog<TextChoice>(
    context: context,
    builder: (_) =>
        _TextDialog(initialText: initialText, initialFont: initialFont),
  );
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.initialText, required this.initialFont});

  final String initialText;
  final String initialFont;

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
