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
      ),
    ),
  );
}

class _ScrapDetail extends StatelessWidget {
  const _ScrapDetail({
    required this.scrap,
    required this.controller,
    this.onRemove,
  });

  final Scrap scrap;
  final ScrollController controller;
  final VoidCallback? onRemove;

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
