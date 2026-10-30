import 'dart:math' as math;

import 'package:ephemera_ai/models/scrap.dart';

/// When a scrap was added, for the "Added" filter.
enum AddedWithin { any, today, week, month }

/// The archive's combined filters (SPEC 4.2). Categories are ANDed together;
/// several values inside one category are ORed ("sticker or wrapper").
class ScrapFilter {
  const ScrapFilter({
    this.query = '',
    this.types = const {},
    this.moods = const {},
    this.tags = const {},
    this.splitFrom = const {},
    this.added = AddedWithin.any,
    this.color,
  });

  static const none = ScrapFilter();

  /// Free text over OCR text, description, tags and type.
  final String query;
  final Set<String> types;
  final Set<String> moods;
  final Set<String> tags;

  /// Parent labels, e.g. {"wrapper"} = elements split from wrappers.
  final Set<String> splitFrom;
  final AddedWithin added;

  /// Hex colour, e.g. "#C8B496"; matches scraps with a similar palette colour.
  final String? color;

  bool get isEmpty =>
      query.trim().isEmpty &&
      types.isEmpty &&
      moods.isEmpty &&
      tags.isEmpty &&
      splitFrom.isEmpty &&
      added == AddedWithin.any &&
      color == null;

  ScrapFilter copyWith({
    String? query,
    Set<String>? types,
    Set<String>? moods,
    Set<String>? tags,
    Set<String>? splitFrom,
    AddedWithin? added,
    String? color,
    bool clearColor = false,
  }) {
    return ScrapFilter(
      query: query ?? this.query,
      types: types ?? this.types,
      moods: moods ?? this.moods,
      tags: tags ?? this.tags,
      splitFrom: splitFrom ?? this.splitFrom,
      added: added ?? this.added,
      color: clearColor ? null : (color ?? this.color),
    );
  }

  /// Toggles [value] in or out of a set (returns a new, unmodifiable set).
  static Set<String> toggled(Set<String> set, String value) => Set.unmodifiable(
    set.contains(value) ? (Set.of(set)..remove(value)) : {...set, value},
  );
}

/// RGB distance under which two colours count as the same swatch.
const colorMatchDistance = 80.0;

List<Scrap> applyFilter(
  List<Scrap> scraps,
  ScrapFilter filter, {
  DateTime? now,
}) {
  if (filter.isEmpty) return scraps;
  final words = _words(filter.query);
  final since = _since(filter.added, now ?? DateTime.now());
  final target = filter.color == null ? null : _rgb(filter.color!);
  return List.unmodifiable(
    scraps.where((s) {
      if (filter.types.isNotEmpty && !filter.types.contains(s.type)) {
        return false;
      }
      if (filter.moods.isNotEmpty && !s.mood.any(filter.moods.contains)) {
        return false;
      }
      if (filter.tags.isNotEmpty && !s.tags.any(filter.tags.contains)) {
        return false;
      }
      if (filter.splitFrom.isNotEmpty &&
          !filter.splitFrom.contains(s.splitFromLabel)) {
        return false;
      }
      if (since != null && s.createdAt.isBefore(since)) return false;
      if (target != null && !_hasColor(s, target)) return false;
      if (words.isNotEmpty) {
        final haystack = _words(
          '${s.ocrText} ${s.description} ${s.tags.join(' ')} ${s.type} ${s.mood.join(' ')}',
        );
        if (!words.every(haystack.contains)) return false;
      }
      return true;
    }),
  );
}

/// What the filter sheets offer, most common first, from the whole archive.
class FilterFacets {
  const FilterFacets({
    required this.types,
    required this.moods,
    required this.tags,
    required this.splitFrom,
    required this.colors,
  });

  final List<String> types;
  final List<String> moods;
  final List<String> tags;
  final List<String> splitFrom;
  final List<String> colors;

  static const maxTags = 24;
  static const maxColors = 12;

  factory FilterFacets.of(List<Scrap> scraps) {
    List<String> ranked(Iterable<String> values, [int? limit]) {
      final counts = <String, int>{};
      for (final v in values.where((v) => v.isNotEmpty)) {
        counts[v] = (counts[v] ?? 0) + 1;
      }
      final sorted = counts.keys.toList()
        ..sort((a, b) {
          final byCount = counts[b]!.compareTo(counts[a]!);
          return byCount != 0 ? byCount : a.compareTo(b);
        });
      return List.unmodifiable(limit == null ? sorted : sorted.take(limit));
    }

    return FilterFacets(
      types: ranked(scraps.map((s) => s.type)),
      moods: ranked(scraps.expand((s) => s.mood)),
      tags: ranked(scraps.expand((s) => s.tags), maxTags),
      splitFrom: ranked(scraps.map((s) => s.splitFromLabel ?? '')),
      colors: ranked(scraps.map((s) => s.palette.firstOrNull ?? ''), maxColors),
    );
  }
}

Set<String> _words(String text) => RegExp(
  r'[a-z0-9]+',
).allMatches(text.toLowerCase()).map((m) => m.group(0)!).toSet();

DateTime? _since(AddedWithin added, DateTime now) => switch (added) {
  AddedWithin.any => null,
  AddedWithin.today => DateTime(now.year, now.month, now.day),
  AddedWithin.week => now.subtract(const Duration(days: 7)),
  AddedWithin.month => now.subtract(const Duration(days: 30)),
};

bool _hasColor(Scrap scrap, (int, int, int) target) {
  for (final hex in scrap.palette) {
    final rgb = _rgb(hex);
    if (rgb != null && _distance(rgb, target) < colorMatchDistance) return true;
  }
  return false;
}

(int, int, int)? _rgb(String hex) {
  final clean = hex.replaceFirst('#', '');
  if (clean.length != 6) return null;
  final value = int.tryParse(clean, radix: 16);
  if (value == null) return null;
  return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF);
}

double _distance((int, int, int) a, (int, int, int) b) => math.sqrt(
  math.pow(a.$1 - b.$1, 2) +
      math.pow(a.$2 - b.$2, 2) +
      math.pow(a.$3 - b.$3, 2),
);
