import 'package:flutter/material.dart';

import 'package:ephemera_ai/config.dart';
import 'package:ephemera_ai/features/capture/cut_style_picker.dart';
import 'package:ephemera_ai/features/empty_state.dart';
import 'package:ephemera_ai/features/scan/piece_preview_sheet.dart';
import 'package:ephemera_ai/features/scan/scan_motion.dart';
import 'package:ephemera_ai/models/scan.dart';
import 'package:ephemera_ai/models/segmentation.dart';
import 'package:ephemera_ai/theme.dart';

const _thumbSize = 96.0;

class EmptySession extends StatelessWidget {
  const EmptySession({super.key});

  @override
  Widget build(BuildContext context) => const EmptyState(
    icon: Icons.add_a_photo_outlined,
    title: 'Scan a few scraps',
    hint:
        'Add photos of your scraps. We find the pieces first - '
        'cutting happens once, after you choose what to keep.',
  );
}

/// One scanned photo: a header and a tile per detected piece.
const _loadingPhotoHeight = 160.0;
const _ghostTiles = 2;

class PhotoSection extends StatelessWidget {
  const PhotoSection({
    super.key,
    required this.photo,
    required this.chosen,
    required this.onToggle,
    required this.onChooseAll,
    required this.onRetry,
    required this.onRemove,
    required this.splitting,
    required this.alreadySplit,
    required this.onSplit,
  });

  final SessionPhoto photo;
  final Set<String> chosen;
  final ValueChanged<ScanPiece> onToggle;

  /// Keys of whole pieces whose split is in progress / done.
  final Set<String> splitting;
  final Set<String> alreadySplit;
  final ValueChanged<ScanPiece> onSplit;
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
              Expanded(
                child: _status(
                  context,
                  pieces.where((p) => !p.isElement).length,
                ),
              ),
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
          if (photo.isLoading)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Shimmer(
                child: Image.memory(
                  photo.bytes,
                  height: _loadingPhotoHeight,
                  fit: BoxFit.cover,
                  cacheHeight: (_loadingPhotoHeight * 2).round(),
                ),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (i, piece) in pieces.indexed) ...[
                PopIn(
                  key: ValueKey(piece.key),
                  index: i,
                  child: PieceTile(
                    piece: piece,
                    chosen: chosen.contains(piece.key),
                    onTap: () => onToggle(piece),
                    onPreview: () => showPiecePreview(
                      context,
                      photo: photo,
                      piece: piece,
                      chosen: chosen,
                      onToggle: onToggle,
                      onSplit: _splitAction(piece),
                    ),
                    splitting: splitting.contains(piece.key),
                    onSplit: _splitAction(piece),
                  ),
                ),
                // Placeholders where the split elements will land.
                if (splitting.contains(piece.key))
                  for (var g = 0; g < _ghostTiles; g++) const _GhostTile(),
              ],
            ],
          ),
        ],
      ),
    );
  }

  VoidCallback? _splitAction(ScanPiece piece) =>
      piece.isElement || alreadySplit.contains(piece.key)
      ? null
      : () => onSplit(piece);

  Widget _status(BuildContext context, int count) {
    final tokens = context.tokens;
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
            child: Text(error, style: TextStyle(color: tokens.accent)),
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
    this.onPreview,
    this.splitting = false,
    this.onSplit,
  });

  final ScanPiece piece;
  final bool chosen;
  final VoidCallback onTap;

  /// Opens the closer look (magnifier, or long-press on the tile).
  final VoidCallback? onPreview;
  final bool splitting;

  /// Null hides the Split action (elements, or pieces already split).
  final VoidCallback? onSplit;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: _thumbSize,
      decoration: BoxDecoration(
        color: piece.isElement ? tokens.paper : tokens.paperDeep,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: chosen ? tokens.accent : tokens.paperDeep,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Semantics(
            label: '${piece.label}, ${chosen ? 'chosen' : 'not chosen'}',
            button: true,
            child: GestureDetector(
              onTap: onTap,
              onLongPress: onPreview,
              behavior: HitTestBehavior.opaque,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: chosen ? 1 : 0.45,
                child: Column(
                  children: [
                    _thumbWithCheck(tokens),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        piece.isElement ? '↳ ${piece.label}' : piece.label,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (splitting)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Splitting…',
                style: TextStyle(fontSize: 12, color: tokens.inkSoft),
              ),
            )
          else if (onSplit != null)
            InkWell(
              onTap: onSplit,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.content_cut, size: 14, color: tokens.inkSoft),
                    const SizedBox(width: 4),
                    Text(
                      'Split',
                      style: TextStyle(fontSize: 12, color: tokens.inkSoft),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _thumbWithCheck(EphemeraTokens tokens) {
    final thumb = ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      child: Image.memory(
        piece.thumbJpeg,
        width: _thumbSize,
        height: _thumbSize - 20,
        fit: BoxFit.cover,
      ),
    );
    return Stack(
      children: [
        if (splitting) Shimmer(child: thumb) else thumb,
        if (onPreview != null)
          Positioned(
            top: 0,
            left: 0,
            child: IconButton(
              tooltip: 'Look closer',
              onPressed: onPreview,
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                backgroundColor: Colors.black.withValues(alpha: 0.35),
              ),
              icon: const Icon(Icons.zoom_in, size: 18, color: Colors.white),
            ),
          ),
        Positioned(
          top: 4,
          right: 4,
          child: Icon(
            chosen ? Icons.check_circle : Icons.circle_outlined,
            size: 20,
            color: chosen ? tokens.accent : Colors.white,
          ),
        ),
      ],
    );
  }
}

/// A shimmering empty tile, standing in for a split element still being found.
class _GhostTile extends StatelessWidget {
  const _GhostTile();

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Container(
        width: _thumbSize,
        height: _thumbSize + 18,
        decoration: BoxDecoration(
          color: context.tokens.paperDeep,
          borderRadius: BorderRadius.circular(6),
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
      color: context.tokens.paperDeep,
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
              style: TextStyle(color: context.tokens.inkSoft),
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
