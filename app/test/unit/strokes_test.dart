import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ephemera_ai/features/editor/strokes.dart';
import 'package:ephemera_ai/models/journal.dart';

void main() {
  const page = Size(400, 400 * pageAspect);

  PageElement stroke(List<Offset> points, {double thickness = 4}) =>
      strokeElement(
        id: 's1',
        points: points,
        pageSize: page,
        thickness: thickness,
        color: const Color(0xFF112233),
      )!;

  test('the element box hugs the stroke plus room for the pen', () {
    final e = stroke(const [Offset(100, 200), Offset(300, 200)]);

    // 200 px long + 4 px pad each side = 208 px wide, 8 px tall.
    expect(e.kind, ElementKind.stroke);
    expect(e.size * page.width, closeTo(208, 0.01));
    expect(e.imageAspect * 208, closeTo(8, 0.01));
    expect(e.cx * page.width, closeTo(200, 0.01));
    expect(e.cy * page.height, closeTo(200, 0.01));
    expect(e.penWidth * 208, closeTo(4, 0.01));
    expect(e.color, 0xFF112233);
  });

  test('points are stored relative to the box, so they scale with it', () {
    final e = stroke(const [Offset(100, 100), Offset(150, 150)]);

    expect(e.points.take(2), [closeTo(4 / 58, 1e-9), closeTo(4 / 58, 1e-9)]);
    expect(e.points.skip(2), [closeTo(54 / 58, 1e-9), closeTo(54 / 58, 1e-9)]);
  });

  test('a single tap becomes a dot', () {
    final e = stroke(const [Offset(50, 50)]);

    expect(e.size * page.width, closeTo(8, 0.01));
    expect(e.imageAspect, 1);
  });

  test('an empty stroke makes nothing', () {
    expect(
      strokeElement(
        id: 'x',
        points: const [],
        pageSize: page,
        thickness: 4,
        color: Colors.black,
      ),
      isNull,
    );
  });

  test('strokes survive a save and load', () {
    final e = stroke(const [Offset(10, 10), Offset(60, 30), Offset(90, 80)]);

    final loaded = PageElement.fromJson(e.toJson());

    expect(loaded.kind, ElementKind.stroke);
    expect(loaded.points.length, 6);
    for (var i = 0; i < 6; i++) {
      expect(loaded.points[i], closeTo(e.points[i], 1e-4));
    }
    expect(loaded.penWidth, e.penWidth);
  });

  test('text and scrap elements do not store stroke data', () {
    const text = PageElement(
      id: 't',
      kind: ElementKind.text,
      cx: 0.5,
      cy: 0.5,
      size: 0.07,
    );

    expect(text.toJson().containsKey('points'), isFalse);
  });
}
