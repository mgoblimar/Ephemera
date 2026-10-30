import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ephemera_ai/features/editor/handwriting.dart';
import 'package:ephemera_ai/features/editor/strokes.dart';
import 'package:ephemera_ai/models/journal.dart';
import 'package:ephemera_ai/theme.dart';

/// Smallest/largest element size, as a fraction of page width.
const _minSize = 0.03;
const _maxSize = 1.6;

/// Room around a selected element for its corner handle (logical px).
const _handleInset = 13.0;

/// Called while an element is being dragged/pinched ([done] false) and once
/// when the gesture ends ([done] true) - only the latter becomes an undo step.
typedef ElementChanged =
    void Function(PageElement element, {required bool done});

/// Renders a journal page. Interactive when [onSelect] and [onChanged] are
/// given (the editor); read-only otherwise (book pages, thumbnails).
class JournalPageCanvas extends StatelessWidget {
  const JournalPageCanvas({
    super.key,
    required this.page,
    this.selectedId,
    this.onSelect,
    this.onChanged,
  });

  final JournalPage page;
  final String? selectedId;
  final ValueChanged<String?>? onSelect;
  final ElementChanged? onChanged;

  bool get _interactive => onSelect != null && onChanged != null;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1 / pageAspect,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pageSize = Size(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _interactive ? () => onSelect!(null) : null,
            child: ClipRect(
              child: CustomPaint(
                painter: PaperPainter(page.paper),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final element in page.elements)
                      _PlacedElement(
                        key: ValueKey(element.id),
                        element: element,
                        pageSize: pageSize,
                        selected: element.id == selectedId,
                        onSelect: onSelect,
                        onChanged: onChanged,
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PlacedElement extends StatefulWidget {
  const _PlacedElement({
    super.key,
    required this.element,
    required this.pageSize,
    required this.selected,
    required this.onSelect,
    required this.onChanged,
  });

  final PageElement element;
  final Size pageSize;
  final bool selected;
  final ValueChanged<String?>? onSelect;
  final ElementChanged? onChanged;

  @override
  State<_PlacedElement> createState() => _PlacedElementState();
}

class _PlacedElementState extends State<_PlacedElement> {
  final _boxKey = GlobalKey();
  PageElement? _base;

  /// Latest gesture result; the widget may not have rebuilt with it yet when
  /// the gesture ends (move and release can land in the same frame).
  PageElement? _latest;
  Offset _startFocal = Offset.zero;

  /// Element centre on screen and the pointer's offset from it when a corner
  /// handle drag started.
  Offset _center = Offset.zero;
  Offset _startArm = Offset.zero;

  void _begin() {
    if (!widget.selected) HapticFeedback.selectionClick();
    widget.onSelect?.call(widget.element.id);
    _base = widget.element;
    _latest = widget.element;
  }

  void _emit(PageElement updated) {
    _latest = updated;
    widget.onChanged?.call(updated, done: false);
  }

  void _start(ScaleStartDetails details) {
    _begin();
    _startFocal = details.focalPoint;
  }

  void _update(ScaleUpdateDetails details) {
    final base = _base;
    if (base == null) return;
    final delta = details.focalPoint - _startFocal;
    _emit(
      base.copyWith(
        cx: (base.cx + delta.dx / widget.pageSize.width).clamp(0.0, 1.0),
        cy: (base.cy + delta.dy / widget.pageSize.height).clamp(0.0, 1.0),
        size: (base.size * details.scale).clamp(_minSize, _maxSize),
        rotation: base.rotation + details.rotation,
      ),
    );
  }

  void _handleStart(DragStartDetails details) {
    final box = _boxKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    _begin();
    _center = box.localToGlobal(box.size.center(Offset.zero));
    _startArm = details.globalPosition - _center;
  }

  /// Corner handle: distance from the centre scales, angle around it rotates.
  void _handleUpdate(DragUpdateDetails details) {
    final base = _base;
    if (base == null || _startArm.distance == 0) return;
    final arm = details.globalPosition - _center;
    _emit(
      base.copyWith(
        size: (base.size * arm.distance / _startArm.distance).clamp(
          _minSize,
          _maxSize,
        ),
        rotation: base.rotation + arm.direction - _startArm.direction,
      ),
    );
  }

  void _end([Object? _]) {
    final latest = _latest;
    _base = null;
    _latest = null;
    if (latest == null) return;
    HapticFeedback.lightImpact();
    widget.onChanged?.call(latest, done: true);
  }

  @override
  Widget build(BuildContext context) {
    final element = widget.element;
    final width = widget.pageSize.width;
    Widget child = ElementView(element: element, pageWidth: width);
    if (widget.selected) child = _selectionChrome(context, child);
    if (widget.onChanged != null) {
      child = GestureDetector(
        onTap: () {
          if (!widget.selected) HapticFeedback.selectionClick();
          widget.onSelect?.call(element.id);
        },
        onScaleStart: _start,
        onScaleUpdate: _update,
        onScaleEnd: _end,
        child: child,
      );
    }
    return Positioned(
      left: element.cx * width,
      top: element.cy * widget.pageSize.height,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Transform.rotate(
          angle: element.rotation,
          child: KeyedSubtree(key: _boxKey, child: child),
        ),
      ),
    );
  }

  /// Accent outline, corner marks and a scale/rotate handle. The padding keeps
  /// the handle inside the hit-test area and is symmetric, so the centre stays.
  Widget _selectionChrome(BuildContext context, Widget child) {
    final tokens = context.tokens;
    Widget mark(Alignment at) => Align(
      alignment: at,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: tokens.surface,
          border: Border.all(color: tokens.accent, width: 2),
          shape: BoxShape.circle,
        ),
      ),
    );
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(_handleInset),
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: Border.all(color: tokens.accent, width: 1.5),
            ),
            child: child,
          ),
        ),
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.all(_handleInset - 5),
            child: IgnorePointer(
              child: Stack(
                children: [
                  mark(Alignment.topLeft),
                  mark(Alignment.topRight),
                  mark(Alignment.bottomLeft),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: GestureDetector(
            key: const ValueKey('resize-handle'),
            dragStartBehavior: DragStartBehavior.down,
            onPanStart: _handleStart,
            onPanUpdate: _handleUpdate,
            onPanEnd: _end,
            child: Semantics(
              label: 'Resize and rotate',
              child: Container(
                width: _handleInset * 2,
                height: _handleInset * 2,
                decoration: BoxDecoration(
                  color: tokens.accent,
                  shape: BoxShape.circle,
                  boxShadow: tokens.shadow,
                ),
                child: Icon(
                  Icons.open_in_full,
                  size: 13,
                  color: tokens.surface,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The element's own pixels, without position or selection chrome.
class ElementView extends StatelessWidget {
  const ElementView({
    super.key,
    required this.element,
    required this.pageWidth,
  });

  final PageElement element;
  final double pageWidth;

  @override
  Widget build(BuildContext context) {
    switch (element.kind) {
      case ElementKind.scrap:
        final w = element.size * pageWidth;
        final path = element.imagePath;
        return SizedBox(
          width: w,
          height: w * element.imageAspect,
          child: path == null
              ? ColoredBox(color: context.tokens.paperDeep)
              : Image.file(
                  File(path),
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) =>
                      ColoredBox(color: context.tokens.paperDeep),
                ),
        );
      case ElementKind.stroke:
        return StrokeView(element: element, width: element.size * pageWidth);
      case ElementKind.text:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            element.text,
            textAlign: TextAlign.center,
            style: handwriting(
              element.font,
              fontSize: element.size * pageWidth,
              color: Color(element.color),
            ),
          ),
        );
    }
  }
}

/// Paper backgrounds, drawn rather than bitmap so they stay crisp at any size.
class PaperPainter extends CustomPainter {
  const PaperPainter(this.style);

  final PaperStyle style;

  static const _cream = Color(0xFFFBF5E9);
  static const _kraft = Color(0xFFC9A57A);
  static const _dotColor = Color(0x332F2A26);
  static const _grainColor = Color(0x1A3D2B1F);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    switch (style) {
      case PaperStyle.cream:
        canvas.drawRect(rect, Paint()..color = _cream);
      case PaperStyle.kraft:
        canvas.drawRect(rect, Paint()..color = _kraft);
        _grain(canvas, size);
      case PaperStyle.dots:
        canvas.drawRect(rect, Paint()..color = _cream);
        _dots(canvas, size);
    }
  }

  void _dots(Canvas canvas, Size size) {
    final gap = size.width / 18;
    final paint = Paint()..color = _dotColor;
    for (var y = gap; y < size.height; y += gap) {
      for (var x = gap; x < size.width; x += gap) {
        canvas.drawCircle(Offset(x, y), size.width / 400 + 0.6, paint);
      }
    }
  }

  void _grain(Canvas canvas, Size size) {
    // Fixed seed: the same paper texture every time the page repaints.
    final random = math.Random(7);
    final paint = Paint()..color = _grainColor;
    for (var i = 0; i < 900; i++) {
      final at = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      canvas.drawCircle(at, random.nextDouble() * 1.2 + 0.3, paint);
    }
  }

  @override
  bool shouldRepaint(PaperPainter oldDelegate) => oldDelegate.style != style;
}
