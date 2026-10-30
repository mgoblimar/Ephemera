import 'package:flutter/material.dart';

import 'package:ephemera_ai/features/archive/scrap_filter.dart';
import 'package:ephemera_ai/theme.dart';

/// Search box plus one dropdown chip per filter category.
class ArchiveFilterBar extends StatelessWidget {
  const ArchiveFilterBar({
    super.key,
    required this.filter,
    required this.facets,
    required this.searchController,
    required this.onChanged,
  });

  final ScrapFilter filter;
  final FilterFacets facets;
  final TextEditingController searchController;
  final ValueChanged<ScrapFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: searchController,
            onChanged: (q) => onChanged(filter.copyWith(query: q)),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search words on your scraps…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: filter.query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        searchController.clear();
                        onChanged(filter.copyWith(query: ''));
                      },
                    ),
              filled: true,
              fillColor: tokens.surface,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(tokens.cardRadius),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _facetChip(
                context,
                'Type',
                filter.types,
                facets.types,
                (s) => filter.copyWith(types: s),
              ),
              _facetChip(
                context,
                'Vibe',
                filter.moods,
                facets.moods,
                (s) => filter.copyWith(moods: s),
              ),
              _facetChip(
                context,
                'Tags',
                filter.tags,
                facets.tags,
                (s) => filter.copyWith(tags: s),
              ),
              if (facets.splitFrom.isNotEmpty)
                _facetChip(
                  context,
                  'Split from',
                  filter.splitFrom,
                  facets.splitFrom,
                  (s) => filter.copyWith(splitFrom: s),
                ),
              _addedChip(context),
              if (facets.colors.isNotEmpty) _colorChip(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _facetChip(
    BuildContext context,
    String label,
    Set<String> selected,
    List<String> options,
    ScrapFilter Function(Set<String>) apply,
  ) {
    return _DropChip(
      label: selected.isEmpty ? label : '$label · ${selected.length}',
      active: selected.isNotEmpty,
      enabled: options.isNotEmpty,
      onTap: () async {
        final result = await showModalBottomSheet<Set<String>>(
          context: context,
          builder: (_) => _MultiPickSheet(
            title: label,
            options: options,
            selected: selected,
          ),
        );
        if (result != null) onChanged(apply(result));
      },
    );
  }

  Widget _addedChip(BuildContext context) {
    const labels = {
      AddedWithin.any: 'Any time',
      AddedWithin.today: 'Today',
      AddedWithin.week: 'This week',
      AddedWithin.month: 'This month',
    };
    return _DropChip(
      label: filter.added == AddedWithin.any ? 'Added' : labels[filter.added]!,
      active: filter.added != AddedWithin.any,
      onTap: () async {
        final result = await showModalBottomSheet<AddedWithin>(
          context: context,
          builder: (sheet) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in labels.entries)
                  ListTile(
                    title: Text(entry.value),
                    trailing: entry.key == filter.added
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => Navigator.pop(sheet, entry.key),
                  ),
              ],
            ),
          ),
        );
        if (result != null) onChanged(filter.copyWith(added: result));
      },
    );
  }

  Widget _colorChip(BuildContext context) {
    final color = filter.color;
    return _DropChip(
      label: 'Colour',
      active: color != null,
      leading: color == null
          ? null
          : CircleAvatar(radius: 7, backgroundColor: hexColor(color)),
      onTap: () async {
        final result = await showModalBottomSheet<String>(
          context: context,
          builder: (sheet) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final hex in facets.colors)
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.pop(sheet, hex),
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: hexColor(hex),
                        child: hex == color
                            ? const Icon(Icons.check, color: Colors.white)
                            : null,
                      ),
                    ),
                  ActionChip(
                    label: const Text('Any colour'),
                    onPressed: () => Navigator.pop(sheet, ''),
                  ),
                ],
              ),
            ),
          ),
        );
        if (result == null) return;
        onChanged(
          result.isEmpty
              ? filter.copyWith(clearColor: true)
              : filter.copyWith(color: result),
        );
      },
    );
  }
}

Color hexColor(String hex) {
  final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16) ?? 0;
  return Color(0xFF000000 | value);
}

class _DropChip extends StatelessWidget {
  const _DropChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.enabled = true,
    this.leading,
  });

  final String label;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        avatar: leading,
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Flexible: the chip can measure its label a fraction of a pixel
            // short, which overflowed the row.
            Flexible(
              child: Text(
                label,
                softWrap: false,
                overflow: TextOverflow.visible,
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
        selected: active,
        showCheckmark: false,
        selectedColor: tokens.accentSoft,
        backgroundColor: tokens.surface,
        side: BorderSide(color: active ? tokens.accent : tokens.paperDeep),
        onSelected: enabled ? (_) => onTap() : null,
      ),
    );
  }
}

class _MultiPickSheet extends StatefulWidget {
  const _MultiPickSheet({
    required this.title,
    required this.options,
    required this.selected,
  });

  final String title;
  final List<String> options;
  final Set<String> selected;

  @override
  State<_MultiPickSheet> createState() => _MultiPickSheetState();
}

class _MultiPickSheetState extends State<_MultiPickSheet> {
  late Set<String> _picked = widget.selected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: tokens.display(20)),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in widget.options)
                      FilterChip(
                        label: Text(option),
                        selected: _picked.contains(option),
                        selectedColor: tokens.accentSoft,
                        onSelected: (_) => setState(
                          () => _picked = ScrapFilter.toggled(_picked, option),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(() => _picked = const {}),
                  child: const Text('Clear'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _picked),
                  child: const Text('Show scraps'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
