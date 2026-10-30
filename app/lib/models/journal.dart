/// Journals, pages and the elements placed on them. All immutable; edits
/// produce new values (which is what makes undo/redo a simple stack).
library;

/// Page aspect ratio, height / width (A5 portrait).
const pageAspect = 1.414;

enum PaperStyle { cream, kraft, dots }

enum ElementKind { scrap, text, stroke }

/// Handwriting fonts offered for text (Google Fonts family names).
const handwritingFonts = ['Caveat', 'Homemade Apple', 'Reenie Beanie'];

/// Something placed on a page. Positions are fractions of the page, so a
/// page renders identically at any size.
class PageElement {
  const PageElement({
    required this.id,
    required this.kind,
    required this.cx,
    required this.cy,
    required this.size,
    this.rotation = 0,
    this.scrapId,
    this.imagePath,
    this.imageAspect = 1,
    this.text = '',
    this.font = 'Caveat',
    this.color = 0xFF2F2A26,
    this.points = const [],
    this.penWidth = 0,
  });

  final String id;
  final ElementKind kind;

  /// Centre, as fractions of page width / height.
  final double cx;
  final double cy;

  /// Scrap and stroke: width as a fraction of page width. Text: font size as
  /// a fraction of page width.
  final double size;

  /// Radians, clockwise.
  final double rotation;

  final String? scrapId;
  final String? imagePath;

  /// Scrap image (or stroke box) height / width.
  final double imageAspect;

  final String text;
  final String font;
  final int color;

  /// Stroke: x, y pairs as fractions of the element's width (y runs to
  /// [imageAspect]), so the drawing scales with the element.
  final List<double> points;

  /// Stroke: pen thickness as a fraction of the element's width.
  final double penWidth;

  PageElement copyWith({
    double? cx,
    double? cy,
    double? size,
    double? rotation,
    String? text,
    String? font,
    int? color,
  }) {
    return PageElement(
      id: id,
      kind: kind,
      cx: cx ?? this.cx,
      cy: cy ?? this.cy,
      size: size ?? this.size,
      rotation: rotation ?? this.rotation,
      scrapId: scrapId,
      imagePath: imagePath,
      imageAspect: imageAspect,
      text: text ?? this.text,
      font: font ?? this.font,
      color: color ?? this.color,
      points: points,
      penWidth: penWidth,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'cx': cx,
    'cy': cy,
    'size': size,
    'rotation': rotation,
    'scrap_id': scrapId,
    'image_path': imagePath,
    'image_aspect': imageAspect,
    'text': text,
    'font': font,
    'color': color,
    if (kind == ElementKind.stroke) ...{
      'points': [for (final v in points) (v * 10000).round() / 10000],
      'pen_width': penWidth,
    },
  };

  factory PageElement.fromJson(Map<String, dynamic> json) => PageElement(
    id: json['id'] as String,
    kind: ElementKind.values.byName(json['kind'] as String),
    cx: (json['cx'] as num).toDouble(),
    cy: (json['cy'] as num).toDouble(),
    size: (json['size'] as num).toDouble(),
    rotation: (json['rotation'] as num? ?? 0).toDouble(),
    scrapId: json['scrap_id'] as String?,
    imagePath: json['image_path'] as String?,
    imageAspect: (json['image_aspect'] as num? ?? 1).toDouble(),
    text: json['text'] as String? ?? '',
    font: json['font'] as String? ?? 'Caveat',
    color: json['color'] as int? ?? 0xFF2F2A26,
    points: List.unmodifiable([
      for (final v in json['points'] as List<dynamic>? ?? const [])
        (v as num).toDouble(),
    ]),
    penWidth: (json['pen_width'] as num? ?? 0).toDouble(),
  );
}

/// One page. [elements] are in paint order: last is on top.
class JournalPage {
  const JournalPage({
    required this.id,
    this.paper = PaperStyle.cream,
    this.elements = const [],
  });

  final String id;
  final PaperStyle paper;
  final List<PageElement> elements;

  PageElement? element(String id) {
    for (final e in elements) {
      if (e.id == id) return e;
    }
    return null;
  }

  JournalPage withPaper(PaperStyle paper) =>
      JournalPage(id: id, paper: paper, elements: elements);

  JournalPage withElements(List<PageElement> elements) =>
      JournalPage(id: id, paper: paper, elements: List.unmodifiable(elements));

  JournalPage adding(PageElement element) =>
      withElements([...elements, element]);

  JournalPage replacing(PageElement element) => withElements([
    for (final e in elements) e.id == element.id ? element : e,
  ]);

  JournalPage removing(String id) => withElements([
    for (final e in elements)
      if (e.id != id) e,
  ]);

  /// Moves an element one step up (+1) or down (-1) in paint order.
  JournalPage reordering(String id, int delta) {
    final index = elements.indexWhere((e) => e.id == id);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= elements.length) return this;
    final reordered = [...elements]
      ..removeAt(index)
      ..insert(target, elements[index]);
    return withElements(reordered);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'paper': paper.name,
    'elements': [for (final e in elements) e.toJson()],
  };

  factory JournalPage.fromJson(Map<String, dynamic> json) => JournalPage(
    id: json['id'] as String,
    paper: PaperStyle.values.byName(json['paper'] as String? ?? 'cream'),
    elements: List.unmodifiable(
      (json['elements'] as List<dynamic>? ?? const []).map(
        (e) => PageElement.fromJson(e as Map<String, dynamic>),
      ),
    ),
  );
}

class Journal {
  const Journal({
    required this.id,
    required this.title,
    required this.createdAt,
    this.coverColor = 0xFFB5603F,
    this.pages = const [],
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final int coverColor;
  final List<JournalPage> pages;

  Journal withPages(List<JournalPage> pages) => Journal(
    id: id,
    title: title,
    createdAt: createdAt,
    coverColor: coverColor,
    pages: List.unmodifiable(pages),
  );

  Journal replacingPage(JournalPage page) =>
      withPages([for (final p in pages) p.id == page.id ? page : p]);

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'created_at': createdAt.toIso8601String(),
    'cover_color': coverColor,
    'pages': [for (final p in pages) p.toJson()],
  };

  factory Journal.fromJson(Map<String, dynamic> json) => Journal(
    id: json['id'] as String,
    title: json['title'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    coverColor: json['cover_color'] as int? ?? 0xFFB5603F,
    pages: List.unmodifiable(
      (json['pages'] as List<dynamic>? ?? const []).map(
        (p) => JournalPage.fromJson(p as Map<String, dynamic>),
      ),
    ),
  );
}
