import 'package:uuid/uuid.dart';

import 'package:ephemera_ai/models/journal.dart';
import 'package:ephemera_ai/models/scrap.dart';

const _uuid = Uuid();
const _heroSize = 0.5; // first scrap anchors the page
const _otherSize = 0.36;
const _tilt = 0.08;
const _rowStep = 0.24;

/// A simple, deterministic arrangement for an approved plan: scraps cascade
/// down the page in two loose columns with alternating tilts, the first caption
/// sits at the bottom. Stand-in until the agent's own layout step (Day 5).
JournalPage simpleLayout({
  required String pageId,
  required List<Scrap> scraps,
  required List<String> captions,
  required PaperStyle paper,
}) {
  final elements = <PageElement>[
    for (final (i, scrap) in scraps.indexed)
      PageElement(
        id: _uuid.v4(),
        kind: ElementKind.scrap,
        cx: i == 0 ? 0.36 : (i.isOdd ? 0.68 : 0.32),
        cy: (0.2 + (i + (i == 0 ? 0 : 0.4)) * _rowStep / 2).clamp(0.12, 0.82),
        size: i == 0 ? _heroSize : _otherSize,
        rotation: i.isEven ? -_tilt : _tilt,
        scrapId: scrap.id,
        imagePath: scrap.pngPath,
        imageAspect: scrap.height / scrap.width,
      ),
    if (captions.isNotEmpty)
      PageElement(
        id: _uuid.v4(),
        kind: ElementKind.text,
        cx: 0.5,
        cy: 0.92,
        size: 0.065,
        rotation: -0.03,
        text: captions.first,
      ),
  ];
  return JournalPage(
    id: pageId,
    paper: paper,
    elements: List.unmodifiable(elements),
  );
}

PaperStyle paperFromName(String name) =>
    PaperStyle.values.where((p) => p.name == name).firstOrNull ??
    PaperStyle.cream;
