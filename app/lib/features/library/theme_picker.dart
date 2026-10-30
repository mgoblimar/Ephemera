import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ephemera_ai/features/doodles.dart';
import 'package:ephemera_ai/providers.dart';
import 'package:ephemera_ai/theme.dart';

/// Palette button for an app bar; opens [showThemePicker].
class ThemePickerButton extends StatelessWidget {
  const ThemePickerButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Theme',
    icon: const Icon(Icons.palette_outlined),
    onPressed: () => showThemePicker(context),
  );
}

/// A small sheet of theme swatches; the choice applies at once and is saved.
Future<void> showThemePicker(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => const _ThemeSheet(),
    );

class _ThemeSheet extends ConsumerWidget {
  const _ThemeSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themeIdProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Theme', style: context.tokens.display(22)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final tokens in themes.values)
                  _Swatch(
                    tokens: tokens,
                    selected: tokens.id == current,
                    onTap: () =>
                        ref.read(themeIdProvider.notifier).choose(tokens.id),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A mini preview of a theme: its paper, a card, an accent chip and its type.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.tokens,
    required this.selected,
    required this.onTap,
  });

  static const _width = 168.0;

  final EphemeraTokens tokens;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(tokens.cardRadius * 0.7);
    return Semantics(
      label: '${tokens.name} theme${selected ? ', chosen' : ''}',
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: _width,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tokens.paper,
            borderRadius: radius,
            border: Border.all(
              color: selected ? tokens.accent : tokens.paperDeep,
              width: selected ? 3 : 1.5,
            ),
            boxShadow: selected ? tokens.shadow : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(tokens.name, style: tokens.display(18))),
                  if (tokens.catDoodles)
                    CatFace(size: 26, color: tokens.accent)
                  else
                    Icon(Icons.auto_stories, size: 20, color: tokens.accent),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final c in [
                    tokens.accent,
                    tokens.secondary,
                    tokens.tape,
                  ])
                    Container(
                      width: 22,
                      height: 22,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text('a little note', style: tokens.hand(20)),
            ],
          ),
        ),
      ),
    );
  }
}
