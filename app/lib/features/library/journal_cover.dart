import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ephemera_ai/features/doodles.dart';
import 'package:ephemera_ai/models/journal.dart';
import 'package:ephemera_ai/theme.dart';

const _spineWidth = 14.0;
const _pageEdge = 5.0;

/// A cloth-bound notebook: linen weave, spine, page edges, elastic band and a
/// taped paper label with the title.
class JournalCover extends StatelessWidget {
  const JournalCover({super.key, required this.journal, required this.onTap});

  final Journal journal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final cloth = Color(journal.coverColor);
    final pages = journal.pages.length;
    // Stable per-journal randomness so the label tilt doesn't change on rebuild.
    final random = math.Random(journal.id.hashCode);
    final labelTilt = (random.nextDouble() * 2 - 1) * 0.04;
    const shape = BorderRadius.horizontal(
      left: Radius.circular(3),
      right: Radius.circular(8),
    );
    return Semantics(
      label: '${journal.title} journal, $pages pages',
      button: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: shape,
          boxShadow: tokens.shadow,
        ),
        child: ClipRRect(
          borderRadius: shape,
          child: Material(
            color: cloth,
            child: InkWell(
              onTap: onTap,
              child: CustomPaint(
                painter: _ClothPainter(cloth),
                child: Stack(
                  children: [
                    Positioned(
                      right: 22,
                      top: 0,
                      bottom: 0,
                      width: 7,
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.28),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        _spineWidth + 10,
                        22,
                        _pageEdge + 14,
                        14,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Transform.rotate(
                            angle: labelTilt,
                            child: _Label(title: journal.title),
                          ),
                          const Spacer(),
                          Text(
                            '$pages page${pages == 1 ? '' : 's'}',
                            style: tokens.hand(
                              20,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          decoration: BoxDecoration(
            color: tokens.paper,
            border: Border(
              bottom: BorderSide(color: tokens.paperDeep, width: 2),
            ),
          ),
          child: Text(
            title,
            style: tokens.display(17),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Positioned(
          top: -7,
          left: 18,
          child: Transform.rotate(
            angle: -0.08,
            child: Container(width: 40, height: 13, color: tokens.tape),
          ),
        ),
        if (tokens.catDoodles)
          Positioned(
            top: -17,
            right: 8,
            child: CatFace(size: 24, color: tokens.paper),
          ),
      ],
    );
  }
}

/// Linen weave, a darker spine and cream page edges peeking out on the right.
class _ClothPainter extends CustomPainter {
  _ClothPainter(this.cloth);

  final Color cloth;

  @override
  void paint(Canvas canvas, Size size) {
    final light = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    final dark = Paint()
      ..color = Colors.black.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), light);
    }
    for (var x = 0.0; x < size.width; x += 3) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), dark);
    }

    canvas.drawRect(
      Rect.fromLTWH(0, 0, _spineWidth, size.height),
      Paint()..color = Colors.black.withValues(alpha: 0.22),
    );
    canvas.drawLine(
      const Offset(_spineWidth, 0),
      Offset(_spineWidth, size.height),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..strokeWidth = 1.5,
    );

    final edge = Rect.fromLTWH(
      size.width - _pageEdge,
      6,
      _pageEdge,
      size.height - 12,
    );
    canvas.drawRect(edge, Paint()..color = const Color(0xFFF1E6D0));
    final lines = Paint()
      ..color = const Color(0xFFCDBFA4)
      ..strokeWidth = 0.6;
    for (var x = edge.left + 1.2; x < edge.right; x += 1.6) {
      canvas.drawLine(Offset(x, edge.top), Offset(x, edge.bottom), lines);
    }
  }

  @override
  bool shouldRepaint(_ClothPainter old) => old.cloth != cloth;
}
