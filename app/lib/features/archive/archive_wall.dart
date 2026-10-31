import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ephemera_ai/features/doodles.dart';
import 'package:ephemera_ai/models/scrap.dart';
import 'package:ephemera_ai/theme.dart';

const _gap = 14.0;
const _matPadding = 8.0;
const _maxTallness = 1.6;
const _matRoundness =
    0.3; // of the theme's card radius: crisp on Desk, soft on Cozy cat // height / column width; tall strips are shrunk

/// How big a scrap is shown in a column: never taller than [_maxTallness]
/// columns, and never enlarged past its own pixels (small scraps go blurry).
Size _shownSize(Scrap scrap, double inner) {
  final scale = [
    inner / scrap.width,
    inner * _maxTallness / scrap.height,
    1.0,
  ].reduce(math.min);
  return Size(scrap.width * scale, scrap.height * scale);
}

/// Scraps pinned to a wall: masonry columns, each scrap on a paper mat with a
/// slight tilt and the odd strip of washi tape.
class ScrapWall extends StatelessWidget {
  const ScrapWall({
    super.key,
    required this.scraps,
    required this.onTap,
    this.onLongPress,
    this.selected = const {},
  });

  final List<Scrap> scraps;
  final ValueChanged<Scrap> onTap;
  final ValueChanged<Scrap>? onLongPress;

  /// Ids of scraps picked in selection mode; shown ticked.
  final Set<String> selected;

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
                            onLongPress: onLongPress == null
                                ? null
                                : () => onLongPress!(scrap),
                            selected: selected.contains(scrap.id),
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
      heights[shortest] +=
          _shownSize(scrap, width - _matPadding * 2).height +
          _matPadding * 2 +
          _gap;
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
    this.onLongPress,
    this.selected = false,
  });

  final Scrap scrap;
  final double width;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // Stable per-scrap randomness, so the wall doesn't reshuffle on rebuild.
    final random = math.Random(scrap.id.hashCode);
    final tilt = (random.nextDouble() * 2 - 1) * tokens.scrapTilt;
    final taped = random.nextInt(3) == 0;
    final shown = _shownSize(scrap, width - _matPadding * 2);
    return Semantics(
      label: '${scrap.type} scrap',
      button: true,
      selected: selected,
      child: Transform.rotate(
        angle: tilt,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Material(
              color: tokens.surface,
              elevation: 0,
              borderRadius: BorderRadius.circular(
                tokens.cardRadius * _matRoundness,
              ),
              child: InkWell(
                onTap: onTap,
                onLongPress: onLongPress,
                borderRadius: BorderRadius.circular(
                  tokens.cardRadius * _matRoundness,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      tokens.cardRadius * _matRoundness,
                    ),
                    boxShadow: tokens.shadow,
                    color: tokens.surface,
                    border: selected
                        ? Border.all(color: tokens.accent, width: 3)
                        : null,
                  ),
                  padding: const EdgeInsets.all(_matPadding),
                  child: SizedBox.fromSize(
                    size: shown,
                    child: Image.file(
                      File(scrap.pngPath),
                      fit: BoxFit.contain,
                      cacheWidth: math.min(
                        scrap.width,
                        (shown.width * 2).round(),
                      ),
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
                    width: (shown.width + _matPadding * 2) * 0.38,
                    height: 16,
                    color: tokens.tape,
                    child: tokens.catDoodles
                        ? PawPrints(color: Colors.white.withValues(alpha: 0.8))
                        : null,
                  ),
                ),
              ),
            if (selected)
              Positioned(
                top: 4,
                right: 4,
                child: CircleAvatar(
                  radius: 13,
                  backgroundColor: tokens.accent,
                  child: const Icon(Icons.check, size: 18, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
