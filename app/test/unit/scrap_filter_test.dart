import 'package:flutter_test/flutter_test.dart';

import 'package:ephemera_ai/features/archive/scrap_filter.dart';
import 'package:ephemera_ai/models/scrap.dart';

final _now = DateTime(2026, 10, 30, 15);

Scrap _scrap(
  String id, {
  String type = 'other',
  List<String> tags = const [],
  List<String> mood = const [],
  String ocr = '',
  String? splitFrom,
  List<String> palette = const [],
  int daysAgo = 0,
}) => Scrap(
  id: id,
  pngPath: '/$id.png',
  width: 1,
  height: 1,
  source: ScrapSource.capture,
  createdAt: _now.subtract(Duration(days: daysAgo, minutes: 1)),
  type: type,
  tags: tags,
  mood: mood,
  ocrText: ocr,
  palette: palette,
  splitFromLabel: splitFrom,
);

final _archive = [
  _scrap(
    'receipt',
    type: 'receipt',
    tags: ['coffee'],
    mood: ['cozy'],
    ocr: 'Cafe Lumiere 09:42',
    palette: ['#6B4F3A'],
    daysAgo: 0,
  ),
  _scrap(
    'sumo',
    type: 'logo',
    tags: ['cookies', 'blue'],
    mood: ['playful'],
    splitFrom: 'wrapper',
    palette: ['#1E6FB8'],
    daysAgo: 3,
  ),
  _scrap(
    'ticket',
    type: 'ticket',
    tags: ['bus', 'travel'],
    mood: ['nostalgic'],
    ocr: 'P20.00',
    palette: ['#F2CC8F'],
    daysAgo: 20,
  ),
  _scrap(
    'pup',
    type: 'sticker',
    tags: ['dog', 'coffee'],
    mood: ['cozy', 'playful'],
    palette: ['#E8DCC4'],
    daysAgo: 1,
  ),
];

List<String> _ids(ScrapFilter f) =>
    applyFilter(_archive, f, now: _now).map((s) => s.id).toList();

void main() {
  test('no filter returns everything', () {
    expect(_ids(ScrapFilter.none), hasLength(4));
  });

  test('search matches text, tags and type in any order', () {
    expect(_ids(const ScrapFilter(query: 'lumiere')), ['receipt']);
    expect(_ids(const ScrapFilter(query: 'COFFEE')), ['receipt', 'pup']);
    expect(_ids(const ScrapFilter(query: 'coffee dog')), ['pup']);
  });

  test('values within a category are ORed, categories are ANDed', () {
    expect(_ids(const ScrapFilter(types: {'ticket', 'logo'})), [
      'sumo',
      'ticket',
    ]);
    expect(_ids(const ScrapFilter(moods: {'cozy'}, tags: {'dog'})), ['pup']);
  });

  test('split-from finds elements of a parent type', () {
    expect(_ids(const ScrapFilter(splitFrom: {'wrapper'})), ['sumo']);
  });

  test('added-within uses the creation date', () {
    expect(_ids(const ScrapFilter(added: AddedWithin.today)), ['receipt']);
    expect(_ids(const ScrapFilter(added: AddedWithin.week)), [
      'receipt',
      'sumo',
      'pup',
    ]);
    expect(_ids(const ScrapFilter(added: AddedWithin.month)), hasLength(4));
  });

  test('colour matches similar palette colours', () {
    expect(_ids(const ScrapFilter(color: '#1F70B5')), ['sumo']);
  });

  test('facets list the most common values first', () {
    final facets = FilterFacets.of(_archive);

    expect(facets.moods.take(2), ['cozy', 'playful']);
    expect(facets.tags.first, 'coffee');
    expect(facets.splitFrom, ['wrapper']);
    expect(facets.colors, hasLength(4));
  });

  test('toggled adds and removes without mutating', () {
    const base = {'a'};
    final added = ScrapFilter.toggled(base, 'b');
    expect(added, {'a', 'b'});
    expect(ScrapFilter.toggled(added, 'a'), {'b'});
    expect(base, {'a'});
  });
}
