import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ephemera_ai/models/scrap.dart';
import 'package:ephemera_ai/theme.dart';

const _gap = 14.0;
const _matPadding = 8.0;

/// Scraps pinned to a wall: masonry columns, each scrap on a paper mat with a
/// slight tilt and the odd strip of washi tape.
class ScrapWall extends StatelessWidget {
  const ScrapWall({super.key, required this.scraps, required this.onTap});

  final List<Scrap> scraps;
  final ValueChanged<Scrap> onTap;

  static int columnsFor(double width) => width >= 900
      ? 5
      : width >= 640
      ? 4
      : width >= 420
      ? 3
      : 2;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = columnsFor(constraints.maxWidth);
        final columnWidth =
            (constraints.maxWidth - _gap * (columns + 1)) / columns;
        final lanes = _distribute(scraps, columns, columnWidth);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(_gap, _gap, _gap, 120),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, lane) in lanes.indexed) ...[
                if (i > 0) const SizedBox(width: _gap),
                SizedBox(
                  width: columnWidth,
                  child: Column(
                    children: [
                      for (final scrap in lane)
                        Padding(
                          padding: const EdgeInsets.only(bottom: _gap * 1.4),
                          child: ScrapCard(
                            scrap: scrap,
                            width: columnWidth,
                            onTap: () => onTap(scrap),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Each scrap goes to the currently shortest column (keeps lanes even).
  static List<List<Scrap>> _distribute(
    List<Scrap> scraps,
    int columns,
    double width,
  ) {
    final lanes = List.generate(columns, (_) => <Scrap>[]);
    final heights = List.filled(columns, 0.0);
    for (final scrap in scraps) {
      var shortest = 0;
      for (var i = 1; i < columns; i++) {
        if (heights[i] < heights[shortest]) shortest = i;
      }
      lanes[shortest].add(scrap);
      heights[shortest] += width * scrap.height / scrap.width + _gap;
    }
    return lanes;
  }
}

class ScrapCard extends StatelessWidget {
  const ScrapCard({
    super.key,
    required this.scrap,
    required this.width,
    required this.onTap,
  });

  final Scrap scrap;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // Stable per-scrap randomness, so the wall doesn't reshuffle on rebuild.
    final random = math.Random(scrap.id.hashCode);
    final tilt = (random.nextDouble() * 2 - 1) * tokens.scrapTilt;
    final taped = random.nextInt(3) == 0;
    final inner = width - _matPadding * 2;
    return Semantics(
      label: '${scrap.type} scrap',
      button: true,
      child: Transform.rotate(
        angle: tilt,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Material(
              color: tokens.surface,
              elevation: 0,
              borderRadius: BorderRadius.circular(3),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(3),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: tokens.shadow,
                    color: tokens.surface,
                  ),
                  padding: const EdgeInsets.all(_matPadding),
                  child: SizedBox(
                    width: inner,
                    height: inner * scrap.height / scrap.width,
                    child: Image.file(
                      File(scrap.pngPath),
                      fit: BoxFit.contain,
                      cacheWidth: (inner * 2).round(),
                      errorBuilder: (_, _, _) =>
                          ColoredBox(color: tokens.paperDeep),
                    ),
                  ),
                ),
              ),
            ),
            if (taped)
              Positioned(
                top: -8,
                child: Transform.rotate(
                  angle: -tilt * 3,
                  child: Container(
                    width: width * 0.38,
                    height: 16,
                    color: tokens.tape,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
