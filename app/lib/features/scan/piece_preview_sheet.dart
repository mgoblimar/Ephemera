import 'package:flutter/material.dart';

import 'package:ephemera_ai/models/scan.dart';
import 'package:ephemera_ai/theme.dart';

const _maxPhotoHeight = 300.0;
const _bigThumb = 140.0;
const _smallThumb = 76.0;

/// A closer look at one piece before cutting: where it sits on the photo, its
/// split elements outlined, and a way to choose or drop each of them.
Future<void> showPiecePreview(
  BuildContext context, {
  required SessionPhoto photo,
  required ScanPiece piece,
  required Set<String> chosen,
  required ValueChanged<ScanPiece> onToggle,
  VoidCallback? onSplit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, controller) => _PiecePreview(
        photo: photo,
        piece: piece,
        chosen: chosen,
        onToggle: onToggle,
        onSplit: onSplit,
        controller: controller,
      ),
    ),
  );
}

class _PiecePreview extends StatefulWidget {
  const _PiecePreview({
    required this.photo,
    required this.piece,
    required this.chosen,
    required this.onToggle,
    required this.onSplit,
    required this.controller,
  });

  final SessionPhoto photo;
  final ScanPiece piece;
  final Set<String> chosen;
  final ValueChanged<ScanPiece> onToggle;
  final VoidCallback? onSplit;
  final ScrollController controller;

  @override
  State<_PiecePreview> createState() => _PiecePreviewState();
}

class _PiecePreviewState extends State<_PiecePreview> {
  // The sheet keeps its own copy so ticks update while it is open.
  late Set<String> _chosen = widget.chosen;

  void _toggle(ScanPiece piece) {
    widget.onToggle(piece);
    setState(
      () => _chosen = _chosen.contains(piece.key)
          ? _chosen.difference({piece.key})
          : {..._chosen, piece.key},
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final piece = widget.piece;
    final pieces = widget.photo.scan?.pieces ?? const <ScanPiece>[];
    final parent = piece.isElement
        ? pieces.where((p) => p.id == piece.parentId).firstOrNull
        : null;
    final elements = piece.isElement
        ? const <ScanPiece>[]
        : pieces.where((p) => p.parentId == piece.id).toList();
    final subtitle = parent != null
        ? 'Split from the ${parent.label}'
        : elements.isEmpty
        ? 'Whole piece'
        : '${elements.length} element${elements.length == 1 ? '' : 's'} split out';

    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Text(piece.label, style: tokens.display(24)),
        Text(subtitle, style: TextStyle(color: tokens.inkSoft)),
        const SizedBox(height: 12),
        _PhotoWithAreas(
          photo: widget.photo,
          focus: piece,
          outlined: [?parent, ...elements],
          chosen: _chosen,
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.memory(
                piece.thumbJpeg,
                width: _bigThumb,
                height: _bigThumb,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ChooseButton(
                    chosen: _chosen.contains(piece.key),
                    onPressed: () => _toggle(piece),
                  ),
                  if (widget.onSplit != null) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onSplit!();
                      },
                      icon: const Icon(Icons.content_cut, size: 18),
                      label: const Text('Split into elements'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (elements.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('Split elements', style: tokens.display(18)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final e in elements)
                _ElementChoice(
                  piece: e,
                  chosen: _chosen.contains(e.key),
                  onTap: () => _toggle(e),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ChooseButton extends StatelessWidget {
  const _ChooseButton({required this.chosen, required this.onPressed});

  final bool chosen;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return chosen
        ? FilledButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.check_circle, size: 18),
            label: const Text('Chosen'),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.circle_outlined, size: 18),
            label: const Text('Choose'),
          );
  }
}

class _ElementChoice extends StatelessWidget {
  const _ElementChoice({
    required this.piece,
    required this.chosen,
    required this.onTap,
  });

  final ScanPiece piece;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      label: '${piece.label} element, ${chosen ? 'chosen' : 'not chosen'}',
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: _smallThumb + 8,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: chosen ? tokens.accent : tokens.paperDeep,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Stack(
                children: [
                  Opacity(
                    opacity: chosen ? 1 : 0.45,
                    child: Image.memory(
                      piece.thumbJpeg,
                      width: _smallThumb,
                      height: _smallThumb,
                      fit: BoxFit.contain,
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Icon(
                      chosen ? Icons.check_circle : Icons.circle_outlined,
                      size: 18,
                      color: chosen ? tokens.accent : tokens.inkSoft,
                    ),
                  ),
                ],
              ),
              Text(
                piece.label,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The photo with everything but [focus] dimmed, and [outlined] pieces boxed
/// (solid when chosen, faint when not).
class _PhotoWithAreas extends StatelessWidget {
  const _PhotoWithAreas({
    required this.photo,
    required this.focus,
    required this.outlined,
    required this.chosen,
  });

  final SessionPhoto photo;
  final ScanPiece focus;
  final List<ScanPiece> outlined;
  final Set<String> chosen;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final size = focus.photoSize;
    final aspect = size == null || size.isEmpty ? 4 / 3 : size.aspectRatio;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: _maxPhotoHeight),
        child: AspectRatio(
          aspectRatio: aspect,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: CustomPaint(
              foregroundPainter: _AreasPainter(
                focus: focus.area,
                outlined: [
                  for (final p in outlined)
                    if (p.area case final area?)
                      (area: area, chosen: chosen.contains(p.key)),
                ],
                accent: tokens.accent,
              ),
              child: Image.memory(
                photo.bytes,
                fit: BoxFit.fill,
                cacheHeight: (_maxPhotoHeight * 2).round(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AreasPainter extends CustomPainter {
  _AreasPainter({
    required this.focus,
    required this.outlined,
    required this.accent,
  });

  final Rect? focus;
  final List<({Rect area, bool chosen})> outlined;
  final Color accent;

  Rect _scaled(Rect r, Size size) => Rect.fromLTRB(
    r.left * size.width,
    r.top * size.height,
    r.right * size.width,
    r.bottom * size.height,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final focus = this.focus;
    if (focus != null) {
      final hole = _scaled(focus, size);
      canvas.drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(Offset.zero & size)
          ..addRect(hole),
        Paint()..color = Colors.black.withValues(alpha: 0.5),
      );
      canvas.drawRect(
        hole,
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
    for (final o in outlined) {
      canvas.drawRect(
        _scaled(o.area, size),
        Paint()
          ..color = o.chosen
              ? Colors.white
              : Colors.white.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = o.chosen ? 2 : 1,
      );
    }
  }

  @override
  bool shouldRepaint(_AreasPainter old) =>
      old.focus != focus || old.outlined != outlined || old.accent != accent;
}
