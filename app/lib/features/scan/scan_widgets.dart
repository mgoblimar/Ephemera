import 'package:flutter/material.dart';

import 'package:ephemera_ai/config.dart';
import 'package:ephemera_ai/features/capture/cut_style_picker.dart';
import 'package:ephemera_ai/models/scan.dart';
import 'package:ephemera_ai/models/segmentation.dart';
import 'package:ephemera_ai/theme.dart';

const _thumbSize = 96.0;

class EmptySession extends StatelessWidget {
  const EmptySession({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'Add photos of your scraps. We find the pieces first - '
          'cutting happens once, after you choose what to keep.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Palette.inkSoft, height: 1.5),
        ),
      ),
    );
  }
}

/// One scanned photo: a header and a tile per detected piece.
class PhotoSection extends StatelessWidget {
  const PhotoSection({
    super.key,
    required this.photo,
    required this.chosen,
    required this.onToggle,
    required this.onChooseAll,
    required this.onRetry,
    required this.onRemove,
  });

  final SessionPhoto photo;
  final Set<String> chosen;
  final ValueChanged<ScanPiece> onToggle;
  final ValueChanged<bool> onChooseAll;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final pieces = photo.scan?.pieces ?? const <ScanPiece>[];
    final allChosen =
        pieces.isNotEmpty && pieces.every((p) => chosen.contains(p.key));
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.memory(
                  photo.bytes,
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  cacheWidth: 120,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: _status(pieces.length)),
              if (pieces.isNotEmpty)
                TextButton(
                  onPressed: () => onChooseAll(!allChosen),
                  child: Text(allChosen ? 'None' : 'All'),
                ),
              IconButton(
                tooltip: 'Remove photo',
                onPressed: onRemove,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final piece in pieces)
                PieceTile(
                  piece: piece,
                  chosen: chosen.contains(piece.key),
                  onTap: () => onToggle(piece),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _status(int count) {
    if (photo.isLoading) {
      return const Row(
        children: [
          SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text('Finding pieces…'),
        ],
      );
    }
    final error = photo.error;
    if (error != null) {
      return Row(
        children: [
          Flexible(
            child: Text(
              error,
              style: const TextStyle(color: Palette.terracotta),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      );
    }
    return Text(
      count == 0
          ? 'No pieces found'
          : '$count piece${count == 1 ? '' : 's'} found',
    );
  }
}

class PieceTile extends StatelessWidget {
  const PieceTile({
    super.key,
    required this.piece,
    required this.chosen,
    required this.onTap,
  });

  final ScanPiece piece;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${piece.label}, ${chosen ? 'chosen' : 'not chosen'}',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: chosen ? 1 : 0.45,
          child: Container(
            width: _thumbSize,
            decoration: BoxDecoration(
              color: Palette.paperDeep,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: chosen ? Palette.terracotta : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              children: [
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                      child: Image.memory(
                        piece.thumbJpeg,
                        width: _thumbSize,
                        height: _thumbSize - 20,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Icon(
                        chosen ? Icons.check_circle : Icons.circle_outlined,
                        size: 20,
                        color: chosen ? Palette.terracotta : Colors.white,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    piece.label,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Cut style, cost preview and the two actions, pinned to the bottom.
class CutBar extends StatelessWidget {
  const CutBar({
    super.key,
    required this.chosenCount,
    required this.style,
    required this.size,
    required this.cutting,
    required this.onStyle,
    required this.onSize,
    required this.onAddPhoto,
    required this.onCut,
  });

  final int chosenCount;
  final CutStyle style;
  final CutSize size;
  final bool cutting;
  final ValueChanged<CutStyle> onStyle;
  final ValueChanged<CutSize> onSize;
  final VoidCallback? onAddPhoto;
  final VoidCallback onCut;

  @override
  Widget build(BuildContext context) {
    final requests = (chosenCount / piecesPerSamRequest).ceil();
    return Material(
      color: Palette.paperDeep,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CutStylePicker(
              style: style,
              size: size,
              onStyle: onStyle,
              onSize: onSize,
            ),
            Text(
              chosenCount == 0
                  ? 'Tap pieces to choose what to keep'
                  : '$chosenCount chosen · $requests cut request${requests == 1 ? '' : 's'} · '
                        '≈₱${(requests * samRequestCostPesos).toStringAsFixed(2)}',
              style: const TextStyle(color: Palette.inkSoft),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: onAddPhoto,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('Photo'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: chosenCount == 0 || cutting ? null : onCut,
                      child: Text(
                        cutting ? 'Cutting…' : 'Cut & save $chosenCount',
                      ),
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
