enum ScrapSource { capture, imported, generated }

/// One cut-out piece of ephemera in the archive. Immutable; use [copyWith].
class Scrap {
  const Scrap({
    required this.id,
    required this.pngPath,
    required this.width,
    required this.height,
    required this.source,
    required this.createdAt,
    this.captureId,
    this.type = 'other',
    this.tags = const [],
    this.ocrText = '',
    this.mood = const [],
    this.palette = const [],
    this.description = '',
    this.enriched = false,
    this.entities = const {},
    this.splitFromLabel,
    this.parentScrapId,
  });

  final String id;
  final String pngPath;
  final int width;
  final int height;
  final ScrapSource source;
  final DateTime createdAt;
  final String? captureId;
  final String type;
  final List<String> tags;
  final String ocrText;
  final List<String> mood;
  final List<String> palette;
  final String description;
  final bool enriched;

  /// Read from the scrap by Muse Spark: date, time, place, brand, price.
  final Map<String, String> entities;

  /// For Split elements: the label of the piece it was split from (e.g. "wrapper").
  final String? splitFromLabel;

  /// The parent's scrap id, when the parent was cut and saved too.
  final String? parentScrapId;

  bool get isSplitElement => splitFromLabel != null;

  Scrap copyWith({
    String? type,
    List<String>? tags,
    String? ocrText,
    List<String>? mood,
    List<String>? palette,
    String? description,
    bool? enriched,
    Map<String, String>? entities,
  }) {
    return Scrap(
      id: id,
      pngPath: pngPath,
      width: width,
      height: height,
      source: source,
      createdAt: createdAt,
      captureId: captureId,
      type: type ?? this.type,
      tags: tags ?? this.tags,
      ocrText: ocrText ?? this.ocrText,
      mood: mood ?? this.mood,
      palette: palette ?? this.palette,
      description: description ?? this.description,
      enriched: enriched ?? this.enriched,
      entities: entities ?? this.entities,
      splitFromLabel: splitFromLabel,
      parentScrapId: parentScrapId,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'png_path': pngPath,
    'width': width,
    'height': height,
    'source': source.name,
    'created_at': createdAt.toIso8601String(),
    'capture_id': captureId,
    'type': type,
    'tags': tags,
    'ocr_text': ocrText,
    'mood': mood,
    'palette': palette,
    'description': description,
    'enriched': enriched,
    'entities': entities,
    'split_from_label': splitFromLabel,
    'parent_scrap_id': parentScrapId,
  };

  factory Scrap.fromJson(Map<String, dynamic> json) {
    return Scrap(
      id: json['id'] as String,
      pngPath: json['png_path'] as String,
      width: json['width'] as int,
      height: json['height'] as int,
      source: ScrapSource.values.byName(json['source'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      captureId: json['capture_id'] as String?,
      type: json['type'] as String? ?? 'other',
      tags: _strings(json['tags']),
      ocrText: json['ocr_text'] as String? ?? '',
      mood: _strings(json['mood']),
      palette: _strings(json['palette']),
      description: json['description'] as String? ?? '',
      enriched: json['enriched'] as bool? ?? false,
      entities: Map.unmodifiable(
        (json['entities'] as Map<String, dynamic>? ?? const {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
      splitFromLabel: json['split_from_label'] as String?,
      parentScrapId: json['parent_scrap_id'] as String?,
    );
  }
}

/// A photo the user took, kept so scraps can link back to their source.
class Capture {
  const Capture({
    required this.id,
    required this.photoPath,
    required this.createdAt,
    required this.scrapIds,
  });

  final String id;
  final String photoPath;
  final DateTime createdAt;
  final List<String> scrapIds;

  Map<String, dynamic> toJson() => {
    'id': id,
    'photo_path': photoPath,
    'created_at': createdAt.toIso8601String(),
    'scrap_ids': scrapIds,
  };

  factory Capture.fromJson(Map<String, dynamic> json) {
    return Capture(
      id: json['id'] as String,
      photoPath: json['photo_path'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      scrapIds: _strings(json['scrap_ids']),
    );
  }
}

List<String> _strings(Object? value) =>
    List.unmodifiable((value as List<dynamic>? ?? const []).cast<String>());
