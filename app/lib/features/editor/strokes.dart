import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ephemera_ai/models/journal.dart';
import 'package:ephemera_ai/theme.dart';

/// Pen thicknesses, as fractions of the page width.
const penWidths = [0.006, 0.012, 0.024];

/// Eraser reach (radius), as a fraction of the page width.
const eraserRadius = 0.02;

/// Pen colours: the theme's ink, accent and secondary, plus a blue and a gold.
List<Color> penColors(EphemeraTokens tokens) => [
  tokens.ink,
  tokens.accent,
  tokens.secondary,
  const Color(0xFF3D6FA8),
  const Color(0xFFD9A441),
];

/// Turns a finished pen stroke (page pixels) into a page element whose box
/// hugs the stroke, so it can be moved, scaled and rotated like a scrap.
/// Returns null for a stroke with no points.
PageElement? strokeElement({
  required String id,
  required List<Offset> points,
  required Size pageSize,
  required double thickness,
  required Color color,
}) {
  if (points.isEmpty || pageSize.isEmpty) return null;
  final xs = points.map((p) => p.dx);
  final ys = points.map((p) => p.dy);
  final pad = thickness; // room for round caps
  final left = xs.reduce(math.min) - pad;
  final top = ys.reduce(math.min) - pad;
  final width = math.max(xs.reduce(math.max) + pad - left, pad * 2);
  final height = math.max(ys.reduce(math.max) + pad - top, pad * 2);
  return PageElement(
    id: id,
    kind: ElementKind.stroke,
    cx: (left + width / 2) / pageSize.width,
    cy: (top + height / 2) / pageSize.height,
    size: width / pageSize.width,
    imageAspect: height / width,
    color: color.toARGB32(),
    points: List.unmodifiable([
      for (final p in points) ...[(p.dx - left) / width, (p.dy - top) / width],
    ]),
    penWidth: thickness / width,
  );
}

/// Ids of the pen strokes an eraser drag at [path] (page pixels) passes over.
/// Whole strokes are erased, like lifting off a line of washi.
Set<String> strokesErasedBy(
  List<PageElement> elements,
  List<Offset> path,
  Size pageSize,
) {
  if (path.isEmpty || pageSize.isEmpty) return const {};
  final reach = eraserRadius * pageSize.width;
  return {
    for (final e in elements)
      if (e.kind == ElementKind.stroke &&
          _lineGap(_strokePoints(e, pageSize).toList(), path) <=
              reach + e.penWidth * e.size * pageSize.width / 2)
        e.id,
  };
}

/// Closest distance between two polylines (fast drags leave gaps between
/// points, so segments are compared, not just points).
double _lineGap(List<Offset> a, List<Offset> b) {
  if (a.isEmpty || b.isEmpty) return double.infinity;
  for (var i = 0; i + 1 < a.length; i++) {
    for (var j = 0; j + 1 < b.length; j++) {
      if (_cross(a[i], a[i + 1], b[j], b[j + 1])) return 0;
    }
  }
  var gap = double.infinity;
  for (final p in a) {
    gap = math.min(gap, _toLine(p, b));
  }
  for (final p in b) {
    gap = math.min(gap, _toLine(p, a));
  }
  return gap;
}

/// Whether segments p1-p2 and q1-q2 cross.
bool _cross(Offset p1, Offset p2, Offset q1, Offset q2) {
  double side(Offset a, Offset b, Offset c) =>
      (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
  final d1 = side(q1, q2, p1), d2 = side(q1, q2, p2);
  final d3 = side(p1, p2, q1), d4 = side(p1, p2, q2);
  return d1 * d2 < 0 && d3 * d4 < 0;
}

double _toLine(Offset p, List<Offset> line) {
  if (line.length == 1) return (p - line.first).distance;
  var best = double.infinity;
  for (var i = 0; i + 1 < line.length; i++) {
    best = math.min(best, _toSegment(p, line[i], line[i + 1]));
  }
  return best;
}

double _toSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final lengthSquared = ab.distanceSquared;
  if (lengthSquared == 0) return (p - a).distance;
  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / lengthSquared).clamp(
    0.0,
    1.0,
  );
  return (p - (a + ab * t)).distance;
}

/// A stroke's points on the page, in page pixels (after move, scale and turn).
Iterable<Offset> _strokePoints(PageElement e, Size pageSize) sync* {
  final width = e.size * pageSize.width;
  final height = width * e.imageAspect;
  final centre = Offset(e.cx * pageSize.width, e.cy * pageSize.height);
  final cos = math.cos(e.rotation), sin = math.sin(e.rotation);
  for (var i = 0; i + 1 < e.points.length; i += 2) {
    final x = e.points[i] * width - width / 2;
    final y = e.points[i + 1] * width - height / 2;
    yield centre + Offset(x * cos - y * sin, x * sin + y * cos);
  }
}

/// Draws a stroke element at [width] logical pixels wide.
class StrokeView extends StatelessWidget {
  const StrokeView({super.key, required this.element, required this.width});

  final PageElement element;
  final double width;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(width, width * element.imageAspect),
    painter: _StrokePainter(
      points: [
        for (var i = 0; i + 1 < element.points.length; i += 2)
          Offset(element.points[i] * width, element.points[i + 1] * width),
      ],
      thickness: element.penWidth * width,
      color: Color(element.color),
    ),
  );
}

class _StrokePainter extends CustomPainter {
  _StrokePainter({
    required this.points,
    required this.thickness,
    required this.color,
  });

  final List<Offset> points;
  final double thickness;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    if (points.length == 1) {
      canvas.drawCircle(
        points.first,
        thickness / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }
    canvas.drawPath(smoothPath(points), paint);
  }

  @override
  bool shouldRepaint(_StrokePainter old) =>
      old.points != points || old.thickness != thickness || old.color != color;
}

/// A path through [points], rounded through the midpoints so it reads as ink.
Path smoothPath(List<Offset> points) {
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (var i = 1; i < points.length - 1; i++) {
    final mid = Offset.lerp(points[i], points[i + 1], 0.5)!;
    path.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
  }
  path.lineTo(points.last.dx, points.last.dy);
  return path;
}

/// Sits over the page while drawing: shows the stroke under the finger and
/// hands each finished one to [onStroke], in this layer's pixels.
class DrawLayer extends StatefulWidget {
  const DrawLayer({
    super.key,
    required this.thickness,
    required this.color,
    required this.onStroke,
    this.erasing = false,
  });

  /// Pen thickness as a fraction of the layer's width.
  final double thickness;
  final Color color;
  final void Function(List<Offset> points, Size size) onStroke;

  /// Shows a soft eraser trail instead of ink; [onStroke] then gets the
  /// eraser's path.
  final bool erasing;

  @override
  State<DrawLayer> createState() => _DrawLayerState();
}

class _DrawLayerState extends State<DrawLayer> {
  static const _minStep = 1.5; // px between kept points

  List<Offset> _points = const [];

  void _add(Offset point) {
    if (_points.isNotEmpty && (point - _points.last).distance < _minStep) {
      return;
    }
    setState(() => _points = [..._points, point]);
  }

  void _finish(Size size) {
    final points = _points;
    setState(() => _points = const []);
    if (points.isNotEmpty) widget.onStroke(points, size);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => _add(d.localPosition),
          onPanUpdate: (d) => _add(d.localPosition),
          onPanEnd: (_) => _finish(size),
          onTapUp: (d) {
            _add(d.localPosition); // a dot
            _finish(size);
          },
          child: CustomPaint(
            size: size,
            painter: _StrokePainter(
              points: _points,
              thickness: widget.erasing
                  ? eraserRadius * 2 * size.width
                  : widget.thickness * size.width,
              color: widget.erasing ? const Color(0x33888888) : widget.color,
            ),
          ),
        );
      },
    );
  }
}

/// Pen settings shown instead of the tool bar while drawing.
class DrawBar extends StatelessWidget {
  const DrawBar({
    super.key,
    required this.thickness,
    required this.color,
    required this.onThickness,
    required this.onColor,
    required this.onDone,
    this.erasing = false,
    this.onEraser,
  });

  final double thickness;
  final Color color;
  final ValueChanged<double> onThickness;
  final ValueChanged<Color> onColor;
  final VoidCallback onDone;
  final bool erasing;

  /// Picks the eraser; choosing a pen size or colour goes back to the pen.
  final VoidCallback? onEraser;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final (i, w) in penWidths.indexed)
          _Choice(
            label: '${const ['Fine', 'Medium', 'Bold'][i]} pen',
            selected: !erasing && w == thickness,
            onTap: () => onThickness(w),
            child: Container(
              width: 6.0 + i * 6,
              height: 6.0 + i * 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
        Container(
          width: 1,
          height: 28,
          color: tokens.ink.withValues(alpha: 0.2),
        ),
        for (final c in penColors(tokens))
          _Choice(
            label: 'Colour',
            selected: !erasing && c == color,
            onTap: () => onColor(c),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
          ),
        if (onEraser != null)
          _Choice(
            label: 'Eraser',
            selected: erasing,
            onTap: onEraser!,
            child: const _EraserIcon(),
          ),
        FilledButton.icon(
          onPressed: onDone,
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Done'),
        ),
      ],
    );
  }
}

/// A little two-tone eraser block (Material has no eraser icon).
class _EraserIcon extends StatelessWidget {
  const _EraserIcon();

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: -0.6,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: const SizedBox(
        width: 24,
        height: 12,
        child: Row(
          // Childless boxes have no height of their own; stretch fills it.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: ColoredBox(color: Color(0xFFE8A0A8))),
            Expanded(child: ColoredBox(color: Color(0xFF8C9BB0))),
          ],
        ),
      ),
    ),
  );
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      label: label,
      button: true,
      selected: selected,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? tokens.surface : Colors.transparent,
            border: selected
                ? Border.all(color: tokens.accent, width: 2)
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A small sheet of pen colours; returns the one tapped, or null.
Future<Color?> pickPenColor(BuildContext context, {required Color current}) {
  return showModalBottomSheet<Color>(
    context: context,
    builder: (sheet) {
      final tokens = sheet.tokens;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Colour', style: tokens.display(20)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 14,
                children: [
                  for (final c in penColors(tokens))
                    _Choice(
                      label: 'Colour',
                      selected: c.toARGB32() == current.toARGB32(),
                      onTap: () => Navigator.pop(sheet, c),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
