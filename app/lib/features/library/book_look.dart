import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ephemera_ai/models/journal.dart';
import 'package:ephemera_ai/theme.dart';

/// The surface the open book lies on, drawn in code (no image assets).
class BookBackdropView extends StatelessWidget {
  const BookBackdropView({
    super.key,
    required this.backdrop,
    required this.coverColor,
    required this.child,
  });

  final BookBackdrop backdrop;
  final Color coverColor;
  final Widget child;

  /// Base colour of each backdrop.
  static Color base(BookBackdrop backdrop, Color cover) => switch (backdrop) {
    BookBackdrop.cover => cover,
    BookBackdrop.wood => const Color(0xFF8A5A3B),
    BookBackdrop.linen => const Color(0xFFE6DCCB),
    BookBackdrop.cork => const Color(0xFFC49A6C),
    BookBackdrop.kraft => const Color(0xFFC8A57A),
  };

  /// Readable text colour on a backdrop.
  static Color onBackdrop(BookBackdrop backdrop, Color cover) =>
      base(backdrop, cover).computeLuminance() > 0.45
      ? const Color(0xFF2F2A26)
      : const Color(0xFFFBF6EC);

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _BackdropPainter(backdrop, base(backdrop, coverColor)),
    child: child,
  );
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.backdrop, this.colour);

  final BookBackdrop backdrop;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colour);
    final random = math.Random(7); // fixed seed: the texture never flickers
    switch (backdrop) {
      case BookBackdrop.cover:
        break;
      case BookBackdrop.wood:
        _woodGrain(canvas, size, random);
      case BookBackdrop.linen:
        _weave(canvas, size);
      case BookBackdrop.cork:
        _speckles(canvas, size, random, const Color(0x55603A1E), 1.6);
      case BookBackdrop.kraft:
        _speckles(canvas, size, random, const Color(0x22503018), 0.9);
    }
  }

  void _woodGrain(Canvas canvas, Size size, math.Random random) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var y = 0.0; y < size.height; y += 6 + random.nextDouble() * 10) {
      paint.color = Color.lerp(
        const Color(0x22000000),
        const Color(0x18FFFFFF),
        random.nextDouble(),
      )!;
      final wave = 2 + random.nextDouble() * 4;
      final path = Path()..moveTo(0, y);
      for (var x = 0.0; x <= size.width; x += 24) {
        path.lineTo(x, y + math.sin(x / 90 + y) * wave);
      }
      canvas.drawPath(path, paint);
    }
  }

  void _weave(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x14000000)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 3) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _speckles(
    Canvas canvas,
    Size size,
    math.Random random,
    Color colour,
    double radius,
  ) {
    final paint = Paint()..color = colour;
    final count = (size.width * size.height / 90).round();
    for (var i = 0; i < count; i++) {
      canvas.drawCircle(
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
        radius * (0.5 + random.nextDouble()),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter old) =>
      old.backdrop != backdrop || old.colour != colour;
}

/// The binding drawn along a page's left edge: a spine shadow (book), spiral
/// rings (notebook) or a stitched fold (booklet).
class BindingEdge extends StatelessWidget {
  const BindingEdge({super.key, required this.binding, required this.child});

  final BookBinding binding;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: _BindingPainter(binding, context.tokens.ink),
    child: child,
  );
}

class _BindingPainter extends CustomPainter {
  _BindingPainter(this.binding, this.ink);

  final BookBinding binding;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    switch (binding) {
      case BookBinding.book:
        _spineShadow(canvas, size);
      case BookBinding.notebook:
        _spiral(canvas, size);
      case BookBinding.booklet:
        _spineShadow(canvas, size);
        _stitches(canvas, size);
    }
  }

  void _spineShadow(Canvas canvas, Size size) {
    final band = Rect.fromLTWH(0, 0, size.width * 0.06, size.height);
    canvas.drawRect(
      band,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0x40000000), Color(0x00000000)],
        ).createShader(band),
    );
  }

  void _spiral(Canvas canvas, Size size) {
    final step = size.height / 18;
    final hole = Paint()..color = const Color(0xFF3A3530);
    final ring = Paint()
      ..color = const Color(0xFFB8B8BC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, size.width * 0.008);
    for (var y = step / 2; y < size.height; y += step) {
      final centre = Offset(size.width * 0.035, y);
      canvas.drawCircle(centre, size.width * 0.009, hole);
      canvas.drawArc(
        Rect.fromCenter(
          center: centre.translate(-size.width * 0.02, 0),
          width: size.width * 0.06,
          height: step * 0.55,
        ),
        -math.pi / 2,
        math.pi,
        false,
        ring,
      );
    }
  }

  void _stitches(Canvas canvas, Size size) {
    final x = size.width * 0.03;
    final thread = Paint()
      ..color = ink.withValues(alpha: 0.7)
      ..strokeWidth = math.max(1.5, size.width * 0.005)
      ..strokeCap = StrokeCap.round;
    final dash = size.height / 40;
    for (var y = size.height * 0.08; y < size.height * 0.92; y += dash * 2) {
      canvas.drawLine(Offset(x, y), Offset(x, y + dash), thread);
    }
  }

  @override
  bool shouldRepaint(_BindingPainter old) =>
      old.binding != binding || old.ink != ink;
}

/// Bottom sheet to pick the binding and backdrop; returns the updated
/// journal, or null if dismissed.
Future<Journal?> pickBookLook(BuildContext context, Journal journal) {
  return showModalBottomSheet<Journal>(
    context: context,
    builder: (_) => _BookLookSheet(journal: journal),
  );
}

class _BookLookSheet extends StatefulWidget {
  const _BookLookSheet({required this.journal});

  final Journal journal;

  @override
  State<_BookLookSheet> createState() => _BookLookSheetState();
}

class _BookLookSheetState extends State<_BookLookSheet> {
  late Journal _journal = widget.journal;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SafeArea(
      child: SingleChildScrollView(
        // Short screens (landscape) scroll instead of overflowing.
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Book style', style: tokens.display(20)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                for (final b in BookBinding.values)
                  ChoiceChip(
                    label: Text(b.label),
                    selected: _journal.binding == b,
                    onSelected: (_) => setState(
                      () => _journal = _journal.withLook(binding: b),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Paper (all pages)', style: tokens.display(20)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in PaperStyle.values)
                  ChoiceChip(
                    label: Text(p.label),
                    selected: _journal.sharedPaper == p,
                    onSelected: _journal.pages.isEmpty
                        ? null
                        : (_) => setState(
                            () => _journal = _journal.withPaperEverywhere(p),
                          ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Background', style: tokens.display(20)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final b in BookBackdrop.values)
                  ChoiceChip(
                    avatar: CircleAvatar(
                      backgroundColor: BookBackdropView.base(
                        b,
                        Color(_journal.coverColor),
                      ),
                    ),
                    label: Text(b.label),
                    selected: _journal.backdrop == b,
                    onSelected: (_) => setState(
                      () => _journal = _journal.withLook(backdrop: b),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _journal),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
