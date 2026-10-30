import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Our own simple cat doodles for the Cozy cat theme: a round face with
/// pointy ears, and paw prints. Drawn with a few strokes, no imported art.
class CatFace extends StatelessWidget {
  const CatFace({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _CatFacePainter(color));
}

class _CatFacePainter extends CustomPainter {
  _CatFacePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.05
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;

    // Head with two ears, as one outline.
    final head = Path()
      ..moveTo(s * 0.16, s * 0.48)
      ..lineTo(s * 0.18, s * 0.14)
      ..lineTo(s * 0.38, s * 0.3)
      ..quadraticBezierTo(s * 0.5, s * 0.26, s * 0.62, s * 0.3)
      ..lineTo(s * 0.82, s * 0.14)
      ..lineTo(s * 0.84, s * 0.48)
      ..cubicTo(s * 0.9, s * 0.86, s * 0.1, s * 0.86, s * 0.16, s * 0.48);
    canvas.drawPath(head, line);

    // Sleepy closed eyes, a tiny nose and whiskers.
    for (final x in [0.36, 0.64]) {
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(s * x, s * 0.5),
          width: s * 0.12,
          height: s * 0.08,
        ),
        0,
        math.pi,
        false,
        line,
      );
    }
    canvas.drawCircle(Offset(s * 0.5, s * 0.6), s * 0.03, fill);
    for (final side in [-1, 1]) {
      for (final dy in [0.0, 0.06]) {
        canvas.drawLine(
          Offset(s * (0.5 + side * 0.14), s * (0.6 + dy)),
          Offset(s * (0.5 + side * 0.36), s * (0.56 + dy * 1.6)),
          line..strokeWidth = s * 0.025,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CatFacePainter old) => old.color != color;
}

/// A row of small paw prints, for tape strips and labels.
class PawPrints extends StatelessWidget {
  const PawPrints({super.key, required this.color, this.pawSize = 9});

  final Color color;
  final double pawSize;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _PawPrintsPainter(color, pawSize));
}

class _PawPrintsPainter extends CustomPainter {
  _PawPrintsPainter(this.color, this.pawSize);

  final Color color;
  final double pawSize;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final step = pawSize * 1.9;
    for (var x = step / 2, i = 0; x < size.width; x += step, i++) {
      // Alternate up and down a little, like a cat walking across.
      final y = size.height / 2 + (i.isEven ? -1 : 1) * pawSize * 0.18;
      _paw(canvas, Offset(x, y), pawSize, paint);
    }
  }

  static void _paw(Canvas canvas, Offset c, double s, Paint paint) {
    canvas.drawOval(
      Rect.fromCenter(
        center: c.translate(0, s * 0.18),
        width: s * 0.55,
        height: s * 0.45,
      ),
      paint,
    );
    for (final (dx, dy) in [
      (-0.32, -0.12),
      (-0.11, -0.3),
      (0.11, -0.3),
      (0.32, -0.12),
    ]) {
      canvas.drawCircle(c.translate(s * dx, s * dy), s * 0.11, paint);
    }
  }

  @override
  bool shouldRepaint(_PawPrintsPainter old) =>
      old.color != color || old.pawSize != pawSize;
}
