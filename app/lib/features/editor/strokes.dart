import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ephemera_ai/models/journal.dart';
import 'package:ephemera_ai/theme.dart';

/// Pen thicknesses, as fractions of the page width.
const penWidths = [0.006, 0.012, 0.024];

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
  });

  /// Pen thickness as a fraction of the layer's width.
  final double thickness;
  final Color color;
  final void Function(List<Offset> points, Size size) onStroke;

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
              thickness: widget.thickness * size.width,
              color: widget.color,
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
  });

  final double thickness;
  final Color color;
  final ValueChanged<double> onThickness;
  final ValueChanged<Color> onColor;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final (i, w) in penWidths.indexed)
          _Choice(
            label: '${const ['Fine', 'Medium', 'Bold'][i]} pen',
            selected: w == thickness,
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
            selected: c == color,
            onTap: () => onColor(c),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
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
