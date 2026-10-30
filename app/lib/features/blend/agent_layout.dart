import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import 'package:ephemera_ai/models/journal.dart';
import 'package:ephemera_ai/models/scrap.dart';

const _uuid = Uuid();

/// Turns the agent's layout reply into a page. Scraps are painted in the
/// agent's layer order (z); captions go on top. Placements for unknown scraps
/// are ignored.
JournalPage pageFromAgentLayout({
  required String pageId,
  required Map<String, dynamic> layout,
  required List<Scrap> scraps,
  required PaperStyle paper,
}) {
  final byId = {for (final s in scraps) s.id: s};
  final placements = [
    for (final raw in layout['placements'] as List<dynamic>? ?? const [])
      if (raw is Map<String, dynamic> && byId[raw['id']] != null) raw,
  ]..sort((a, b) => _num(a['z']).compareTo(_num(b['z'])));
  final elements = <PageElement>[
    for (final p in placements)
      PageElement(
        id: _uuid.v4(),
        kind: ElementKind.scrap,
        cx: _num(p['cx'], 0.5),
        cy: _num(p['cy'], 0.5),
        size: _num(p['width'], 0.35),
        rotation: _num(p['rotation_deg']) * math.pi / 180,
        scrapId: p['id'] as String,
        imagePath: byId[p['id']]!.pngPath,
        imageAspect: byId[p['id']]!.height / byId[p['id']]!.width,
      ),
    for (final c in layout['captions'] as List<dynamic>? ?? const [])
      if (c is Map<String, dynamic> && (c['text'] as String? ?? '').isNotEmpty)
        PageElement(
          id: _uuid.v4(),
          kind: ElementKind.text,
          cx: _num(c['cx'], 0.5),
          cy: _num(c['cy'], 0.9),
          size: _num(c['size'], 0.06),
          rotation: _num(c['rotation_deg']) * math.pi / 180,
          text: c['text'] as String,
        ),
  ];
  return JournalPage(
    id: pageId,
    paper: paper,
    elements: List.unmodifiable(elements),
  );
}

double _num(Object? value, [double fallback = 0]) =>
    value is num && value.isFinite ? value.toDouble() : fallback;
