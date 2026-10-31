import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import 'package:ephemera_ai/features/doodles.dart';
import 'package:ephemera_ai/features/editor/editor_sheets.dart';
import 'package:ephemera_ai/features/editor/page_canvas.dart';
import 'package:ephemera_ai/features/editor/page_history.dart';
import 'package:ephemera_ai/features/editor/strokes.dart';
import 'package:ephemera_ai/models/journal.dart';
import 'package:ephemera_ai/models/scrap.dart';
import 'package:ephemera_ai/providers.dart';
import 'package:ephemera_ai/theme.dart';

const _newScrapSize = 0.42; // fraction of page width
const _newTextSize = 0.07;
const _maxTilt = 0.12; // radians; a slight hand-placed tilt
const _duplicateOffset = 0.04;
const _exportPixelRatio = 3.0;
const _maxCaptionIdeas = 6;

/// Edits one page of a journal. Every finished change is one undo step and
/// is saved straight away.
class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key, required this.journal, required this.pageId});

  final Journal journal;
  final String pageId;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  late Journal _journal = widget.journal;
  late PageHistory _history = PageHistory.start(
    widget.journal.pages.firstWhere((p) => p.id == widget.pageId),
  );

  /// What's on screen; ahead of `_history.current` only mid-gesture.
  late JournalPage _live = _history.current;
  String? _selectedId;

  /// Draw mode: the pen is on, strokes are added as they're finished.
  bool _drawing = false;
  bool _erasing = false;
  double _penWidth = penWidths[1];
  Color? _penColor; // null: the theme's ink
  final _boundaryKey = GlobalKey();
  final _random = math.Random();
  static const _uuid = Uuid();

  PageElement? get _selected =>
      _selectedId == null ? null : _live.element(_selectedId!);

  void _commit(JournalPage page) {
    setState(() {
      _live = page;
      _history = _history.push(page);
    });
    _save();
  }

  void _restore(PageHistory history) {
    setState(() {
      _history = history;
      _live = history.current;
      if (_selectedId != null && _live.element(_selectedId!) == null) {
        _selectedId = null;
      }
    });
    _save();
  }

  void _save() {
    _journal = _journal.replacingPage(_history.current);
    final journal = _journal;
    unawaited(() async {
      try {
        final repository = await ref.read(journalRepositoryProvider.future);
        await repository.save(journal);
        ref.invalidate(journalsProvider);
      } on FileSystemException {
        _showMessage("Couldn't save the page. Check free storage.");
      }
    }());
  }

  void _onElementChanged(PageElement element, {required bool done}) {
    final page = _live.replacing(element);
    if (done) {
      _commit(page);
    } else {
      setState(() => _live = page);
    }
  }

  double _tilt() => (_random.nextDouble() * 2 - 1) * _maxTilt;

  Future<void> _addScrap() async {
    final Scrap? scrap = await pickScrap(context);
    if (scrap == null || !mounted) return;
    final element = PageElement(
      id: _uuid.v4(),
      kind: ElementKind.scrap,
      cx: 0.5,
      cy: 0.45,
      size: _newScrapSize,
      rotation: _tilt(),
      scrapId: scrap.id,
      imagePath: scrap.pngPath,
      imageAspect: scrap.height / scrap.width,
    );
    _commit(_live.adding(element));
    setState(() => _selectedId = element.id);
  }

  /// Caption ideas Muse Spark wrote for the scraps already on this page.
  Future<List<String>> _captionIdeas() async {
    final List<Scrap> archive;
    try {
      archive = await ref.read(scrapsProvider.future);
    } on Exception {
      return const []; // archive unreadable: just no ideas
    }
    final byId = {for (final s in archive) s.id: s};
    return {
      for (final e in _live.elements)
        if (e.kind == ElementKind.scrap) ...?byId[e.scrapId]?.captions,
    }.take(_maxCaptionIdeas).toList();
  }

  Future<void> _addText() async {
    final ideas = await _captionIdeas();
    if (!mounted) return;
    final choice = await editText(context, ideas: ideas);
    if (choice == null || !mounted) return;
    final element = PageElement(
      id: _uuid.v4(),
      kind: ElementKind.text,
      cx: 0.5,
      cy: 0.8,
      size: _newTextSize,
      rotation: _tilt() / 2,
      text: choice.text,
      font: choice.font,
    );
    _commit(_live.adding(element));
    setState(() => _selectedId = element.id);
  }

  Future<void> _editSelectedText() async {
    final element = _selected;
    if (element == null || element.kind != ElementKind.text) return;
    final choice = await editText(
      context,
      initialText: element.text,
      initialFont: element.font,
    );
    if (choice == null || !mounted) return;
    _commit(
      _live.replacing(element.copyWith(text: choice.text, font: choice.font)),
    );
  }

  void _duplicateSelected() {
    final element = _selected;
    if (element == null) return;
    final copy = PageElement.fromJson({
      ...element.toJson(),
      'id': _uuid.v4(),
      'cx': (element.cx + _duplicateOffset).clamp(0.0, 1.0),
      'cy': (element.cy + _duplicateOffset).clamp(0.0, 1.0),
    });
    _commit(_live.adding(copy));
    setState(() => _selectedId = copy.id);
  }

  void _deleteSelected() {
    final id = _selectedId;
    if (id == null) return;
    setState(() => _selectedId = null);
    _commit(_live.removing(id));
  }

  void _reorderSelected(int delta) {
    final id = _selectedId;
    if (id != null) _commit(_live.reordering(id, delta));
  }

  void _startDrawing() => setState(() {
    _selectedId = null;
    _drawing = true;
  });

  void _addStroke(List<Offset> points, Size pageSize) {
    if (_erasing) {
      final gone = strokesErasedBy(_live.elements, points, pageSize);
      if (gone.isNotEmpty) {
        _commit(
          _live.withElements([
            for (final e in _live.elements)
              if (!gone.contains(e.id)) e,
          ]),
        );
      }
      return;
    }
    final element = strokeElement(
      id: _uuid.v4(),
      points: points,
      pageSize: pageSize,
      thickness: _penWidth * pageSize.width,
      color: _penColor ?? context.tokens.ink,
    );
    if (element != null) _commit(_live.adding(element));
  }

  Future<void> _recolorSelected() async {
    final element = _selected;
    if (element == null) return;
    final color = await pickPenColor(context, current: Color(element.color));
    if (color == null || !mounted) return;
    _commit(_live.replacing(element.copyWith(color: color.toARGB32())));
  }

  void _cyclePaper() {
    const styles = PaperStyle.values;
    _commit(_live.withPaper(styles[(_live.paper.index + 1) % styles.length]));
  }

  Future<void> _export() async {
    setState(() => _selectedId = null);
    await WidgetsBinding.instance.endOfFrame; // render without selection chrome
    final boundary =
        _boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return;
    try {
      final image = await boundary.toImage(pixelRatio: _exportPixelRatio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File(
        p.join(
          dir.path,
          'ephemera_page_${DateTime.now().millisecondsSinceEpoch}.png',
        ),
      );
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: _journal.title),
      );
    } on FileSystemException {
      _showMessage("Couldn't export the page.");
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.tokens.paperDeep,
      appBar: AppBar(
        title: Text(_journal.title),
        backgroundColor: context.tokens.paperDeep,
        actions: [
          IconButton(
            tooltip: 'Undo',
            onPressed: _history.canUndo
                ? () => _restore(_history.undo())
                : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Redo',
            onPressed: _history.canRedo
                ? () => _restore(_history.redo())
                : null,
            icon: const Icon(Icons.redo),
          ),
          IconButton(
            tooltip: 'Export PNG',
            onPressed: _export,
            icon: const Icon(Icons.ios_share),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        RepaintBoundary(
                          key: _boundaryKey,
                          child: JournalPageCanvas(
                            page: _live,
                            selectedId: _selectedId,
                            onSelect: (id) => setState(() => _selectedId = id),
                            onChanged: _onElementChanged,
                          ),
                        ),
                        if (_drawing)
                          Positioned.fill(
                            child: DrawLayer(
                              thickness: _penWidth,
                              color: _penColor ?? context.tokens.ink,
                              onStroke: _addStroke,
                              erasing: _erasing,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_drawing)
              _WashiStrip(
                child: DrawBar(
                  thickness: _penWidth,
                  color: _penColor ?? context.tokens.ink,
                  erasing: _erasing,
                  onEraser: () => setState(() => _erasing = true),
                  onThickness: (w) => setState(() {
                    _penWidth = w;
                    _erasing = false;
                  }),
                  onColor: (c) => setState(() {
                    _penColor = c;
                    _erasing = false;
                  }),
                  onDone: () => setState(() {
                    _drawing = false;
                    _erasing = false;
                  }),
                ),
              )
            else if (_selected != null)
              _SelectionBar(
                isText: _selected!.kind == ElementKind.text,
                onForward: () => _reorderSelected(1),
                onBackward: () => _reorderSelected(-1),
                onDuplicate: _duplicateSelected,
                onDelete: _deleteSelected,
                onEditText: _editSelectedText,
                onColor: _selected!.kind == ElementKind.scrap
                    ? null
                    : _recolorSelected,
              )
            else
              _ToolBar(
                onScrap: _addScrap,
                onText: _addText,
                onDraw: _startDrawing,
                onPaper: _cyclePaper,
              ),
          ],
        ),
      ),
    );
  }
}

class _ToolBar extends StatelessWidget {
  const _ToolBar({
    required this.onScrap,
    required this.onText,
    required this.onDraw,
    required this.onPaper,
  });

  final VoidCallback onScrap;
  final VoidCallback onText;
  final VoidCallback onDraw;
  final VoidCallback onPaper;

  @override
  Widget build(BuildContext context) {
    return _WashiStrip(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _Tool(
            icon: Icons.add_photo_alternate_outlined,
            label: 'Scrap',
            onTap: onScrap,
          ),
          _Tool(icon: Icons.edit_outlined, label: 'Text', onTap: onText),
          _Tool(icon: Icons.gesture, label: 'Draw', onTap: onDraw),
          _Tool(icon: Icons.texture, label: 'Paper', onTap: onPaper),
        ],
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.isText,
    required this.onForward,
    required this.onBackward,
    required this.onDuplicate,
    required this.onDelete,
    required this.onEditText,
    this.onColor,
  });

  final bool isText;
  final VoidCallback onForward;
  final VoidCallback onBackward;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onEditText;

  /// Recolour a drawing or caption; null hides the tool (scraps).
  final VoidCallback? onColor;

  @override
  Widget build(BuildContext context) {
    return _WashiStrip(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (isText)
            _Tool(icon: Icons.edit_outlined, label: 'Edit', onTap: onEditText),
          if (onColor != null)
            _Tool(
              icon: Icons.palette_outlined,
              label: 'Colour',
              onTap: onColor!,
            ),
          _Tool(icon: Icons.flip_to_front, label: 'Forward', onTap: onForward),
          _Tool(icon: Icons.flip_to_back, label: 'Back', onTap: onBackward),
          _Tool(icon: Icons.copy_outlined, label: 'Copy', onTap: onDuplicate),
          _Tool(icon: Icons.delete_outline, label: 'Delete', onTap: onDelete),
        ],
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: context.tokens.ink),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: context.tokens.ink),
            ),
          ],
        ),
      ),
    );
  }
}

/// A strip of washi tape across the bottom: translucent, faintly striped, with
/// torn zig-zag ends.
class _WashiStrip extends StatelessWidget {
  const _WashiStrip({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
      child: Transform.rotate(
        angle: -0.008,
        child: ClipPath(
          clipper: _TornEnds(),
          child: CustomPaint(
            painter: _TapeStripes(tokens.tape),
            child: Stack(
              children: [
                if (tokens.catDoodles)
                  Positioned.fill(
                    child: PawPrints(
                      color: Colors.white.withValues(alpha: 0.35),
                      pawSize: 14,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 4,
                  ),
                  child: child,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TornEnds extends CustomClipper<Path> {
  static const _tooth = 6.0;

  @override
  Path getClip(Size size) {
    final path = Path()..moveTo(_tooth, 0);
    path.lineTo(size.width - _tooth, 0);
    var y = 0.0;
    var out = true;
    while (y < size.height) {
      y = (y + _tooth).clamp(0, size.height);
      path.lineTo(out ? size.width : size.width - _tooth, y);
      out = !out;
    }
    path.lineTo(_tooth, size.height);
    out = true;
    while (y > 0) {
      y = (y - _tooth).clamp(0, size.height);
      path.lineTo(out ? 0 : _tooth, y);
      out = !out;
    }
    return path..close();
  }

  @override
  bool shouldReclip(_TornEnds old) => false;
}

class _TapeStripes extends CustomPainter {
  _TapeStripes(this.tape);

  final Color tape;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = tape);
    final stripe = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 5;
    for (var x = -size.height; x < size.width; x += 16) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        stripe,
      );
    }
  }

  @override
  bool shouldRepaint(_TapeStripes old) => old.tape != tape;
}
