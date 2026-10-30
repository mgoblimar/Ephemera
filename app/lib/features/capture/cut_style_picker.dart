import 'package:flutter/material.dart';

import 'package:ephemera_ai/models/segmentation.dart';

/// Tight / Sticker / Margin plus the S/M/L border size (size is disabled for Tight).
class CutStylePicker extends StatelessWidget {
  const CutStylePicker({
    super.key,
    required this.style,
    required this.size,
    required this.onStyle,
    required this.onSize,
  });

  final CutStyle style;
  final CutSize size;
  final ValueChanged<CutStyle> onStyle;
  final ValueChanged<CutSize> onSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: SegmentedButton<CutStyle>(
              segments: const [
                ButtonSegment(value: CutStyle.tight, label: Text('Tight')),
                ButtonSegment(value: CutStyle.sticker, label: Text('Sticker')),
                ButtonSegment(value: CutStyle.margin, label: Text('Margin')),
              ],
              selected: {style},
              showSelectedIcon: false,
              onSelectionChanged: (s) => onStyle(s.first),
            ),
          ),
          const SizedBox(width: 8),
          SegmentedButton<CutSize>(
            segments: const [
              ButtonSegment(value: CutSize.s, label: Text('S')),
              ButtonSegment(value: CutSize.m, label: Text('M')),
              ButtonSegment(value: CutSize.l, label: Text('L')),
            ],
            selected: {size},
            showSelectedIcon: false,
            // Border size only matters for sticker and margin cuts.
            onSelectionChanged: style == CutStyle.tight
                ? null
                : (s) => onSize(s.first),
          ),
        ],
      ),
    );
  }
}
