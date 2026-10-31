import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:ephemera_ai/features/archive/archive_filter_bar.dart';
import 'package:ephemera_ai/models/scrap.dart';
import 'package:ephemera_ai/theme.dart';

/// Everything known about one scrap: what Muse Spark read, where it came from.
/// [onRemove] adds a "Remove from archive" button (the sheet closes first).
Future<void> showScrapDetail(
  BuildContext context,
  Scrap scrap, {
  VoidCallback? onRemove,
  ValueChanged<PhysicalStatus>? onStatus,
  ValueChanged<String>? onUsedIn,
  String? suggestedNote,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, controller) => _ScrapDetail(
        scrap: scrap,
        controller: controller,
        onRemove: onRemove,
        onStatus: onStatus,
        onUsedIn: onUsedIn,
        suggestedNote: suggestedNote,
      ),
    ),
  );
}

class _ScrapDetail extends StatelessWidget {
  const _ScrapDetail({
    required this.scrap,
    required this.controller,
    this.onRemove,
    this.onStatus,
    this.onUsedIn,
    this.suggestedNote,
  });

  final Scrap scrap;
  final ScrollController controller;
  final VoidCallback? onRemove;
  final ValueChanged<PhysicalStatus>? onStatus;
  final ValueChanged<String>? onUsedIn;
  final String? suggestedNote;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final added = scrap.createdAt;
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: Image.file(File(scrap.pngPath), fit: BoxFit.contain),
          ),
        ),
        const SizedBox(height: 16),
        Text(scrap.type, style: tokens.display(24)),
        Text(
          [
            'Added ${added.year}-${_two(added.month)}-${_two(added.day)}',
            if (scrap.splitFromLabel != null)
              'split from a ${scrap.splitFromLabel}',
            if (scrap.source == ScrapSource.generated) 'made by AI',
            if (!scrap.enriched) 'not read yet',
          ].join(' · '),
          style: TextStyle(color: tokens.inkSoft),
        ),
        if (onStatus != null) ...[
          const SizedBox(height: 16),
          _StatusPicker(
            initial: scrap.physicalStatus,
            initialNote: scrap.usedIn,
            suggestedNote: suggestedNote,
            onChanged: onStatus!,
            onNote: onUsedIn,
          ),
        ],
        if (scrap.tooWeakForAgent) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.visibility_off_outlined,
                size: 16,
                color: tokens.inkSoft,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Too small to use in Theme Blend pages',
                  style: TextStyle(color: tokens.inkSoft, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
        if (scrap.description.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            scrap.description,
            style: TextStyle(color: tokens.ink, height: 1.4),
          ),
        ],
        if (scrap.journalPrompt.isNotEmpty) ...[
          const SizedBox(height: 16),
          _JournalPrompt(prompt: scrap.journalPrompt),
        ],
        if (scrap.ocrText.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Words on it',
            style: TextStyle(color: tokens.inkSoft, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text('“${scrap.ocrText}”', style: tokens.hand(22)),
        ],
        if (scrap.entities.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final e in scrap.entities.entries)
            Text('${e.key}: ${e.value}', style: TextStyle(color: tokens.ink)),
        ],
        if (scrap.mood.isNotEmpty || scrap.tags.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in scrap.mood)
                Chip(
                  label: Text(m),
                  backgroundColor: tokens.accentSoft,
                  side: BorderSide.none,
                ),
              for (final t in scrap.tags)
                Chip(
                  label: Text('#$t'),
                  side: BorderSide(color: tokens.paperDeep),
                ),
            ],
          ),
        ],
        if (scrap.palette.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              for (final hex in scrap.palette)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: hexColor(hex),
                  ),
                ),
            ],
          ),
        ],
        if (onRemove != null) ...[
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                onRemove!();
              },
              style: TextButton.styleFrom(foregroundColor: tokens.accent),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Remove from archive'),
            ),
          ),
        ],
      ],
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}

/// Where the real scrap is now. Theme Blend skips used and set-aside scraps.
class _StatusPicker extends StatefulWidget {
  const _StatusPicker({
    required this.initial,
    required this.onChanged,
    this.initialNote = '',
    this.suggestedNote,
    this.onNote,
  });

  final PhysicalStatus initial;
  final ValueChanged<PhysicalStatus> onChanged;
  final String initialNote;

  /// Filled in (and saved) when the scrap is marked used with no note yet.
  final String? suggestedNote;

  /// Saves the used-in note; null hides the field.
  final ValueChanged<String>? onNote;

  @override
  State<_StatusPicker> createState() => _StatusPickerState();
}

class _StatusPickerState extends State<_StatusPicker> {
  static const _saveDelay = Duration(milliseconds: 600);

  late PhysicalStatus _status = widget.initial;
  late final _note = TextEditingController(text: widget.initialNote);
  Timer? _pendingSave;

  /// Saves shortly after typing stops, and on close if still pending.
  void _noteChanged(String _) {
    _pendingSave?.cancel();
    _pendingSave = Timer(_saveDelay, _saveNote);
  }

  void _saveNote() {
    _pendingSave?.cancel();
    _pendingSave = null;
    widget.onNote?.call(_note.text.trim());
  }

  @override
  void dispose() {
    if (_pendingSave != null) _saveNote();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<PhysicalStatus>(
          segments: [
            for (final s in PhysicalStatus.values)
              ButtonSegment(value: s, label: Text(s.label)),
          ],
          selected: {_status},
          showSelectedIcon: false,
          onSelectionChanged: (picked) {
            setState(() => _status = picked.single);
            widget.onChanged(picked.single);
            final suggestion = widget.suggestedNote;
            if (picked.single == PhysicalStatus.used &&
                suggestion != null &&
                _note.text.trim().isEmpty) {
              _note.text = suggestion;
              _saveNote();
            }
          },
        ),
        const SizedBox(height: 6),
        Text(
          _status == PhysicalStatus.available
              ? 'Theme Blend can use it.'
              : 'Theme Blend will leave it out.',
          style: TextStyle(color: tokens.inkSoft, fontSize: 13),
        ),
        if (widget.onNote != null && _status != PhysicalStatus.available) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _note,
            onChanged: _noteChanged,
            onSubmitted: (_) => _saveNote(),
            textInputAction: TextInputAction.done,
            maxLength: 80,
            decoration: InputDecoration(
              labelText: _status == PhysicalStatus.used
                  ? 'Used in'
                  : 'Set aside for',
              hintText: 'Kyoto journal, page 4',
              prefixIcon: const Icon(Icons.bookmark_border),
              isDense: true,
            ),
          ),
        ],
      ],
    );
  }
}

/// A writing prompt on a little lined card, like a journaling sticker.
class _JournalPrompt extends StatelessWidget {
  const _JournalPrompt({required this.prompt});

  final String prompt;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(tokens.cardRadius * 0.6),
        border: Border(left: BorderSide(color: tokens.accent, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note, size: 18, color: tokens.accent),
              const SizedBox(width: 6),
              Text(
                'Journal prompt',
                style: TextStyle(color: tokens.inkSoft, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(prompt, style: tokens.hand(24)),
        ],
      ),
    );
  }
}
