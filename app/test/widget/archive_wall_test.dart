import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ephemera_ai/features/archive/archive_wall.dart';
import 'package:ephemera_ai/models/scrap.dart';
import 'package:ephemera_ai/theme.dart';

Scrap _scrap(String id, int width, int height) => Scrap(
  id: id,
  pngPath: '/missing/$id.png',
  width: width,
  height: height,
  source: ScrapSource.capture,
  createdAt: DateTime(2026, 10, 30),
);

Size _shown(WidgetTester tester, String id) => tester.getSize(
  find
      .descendant(
        of: find.byWidgetPredicate((w) => w is ScrapCard && w.scrap.id == id),
        matching: find.byType(Image),
      )
      .first,
);

void main() {
  testWidgets('small scraps keep their own size and tall strips are capped', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: ScrapWall(
            scraps: [
              _scrap('big', 2000, 1500),
              _scrap('badge', 120, 60),
              _scrap('strip', 40, 2000),
            ],
            onTap: (_) {},
          ),
        ),
      ),
    );

    final column = _shown(tester, 'big').width;
    expect(_shown(tester, 'badge'), const Size(120, 60));
    expect(_shown(tester, 'strip').height, closeTo(column * 1.6, 0.5));
  });
}
