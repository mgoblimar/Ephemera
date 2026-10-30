import 'package:flutter/material.dart';

import 'package:ephemera_ai/features/doodles.dart';
import 'package:ephemera_ai/theme.dart';

/// An icon, a display-font title and a short hint, centred.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
  });

  final IconData icon;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tokens.catDoodles)
              CatFace(size: 72, color: tokens.accent)
            else
              Icon(icon, size: 56, color: tokens.accent),
            const SizedBox(height: 12),
            Text(title, style: tokens.display(22), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.inkSoft, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
