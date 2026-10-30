/// The Theme Blend agent's plan for one page (SPEC 4.6), shown for approval.
class BlendPlan {
  const BlendPlan({
    required this.theme,
    required this.title,
    required this.palette,
    required this.paper,
    required this.scraps,
    required this.captions,
    required this.layoutIntent,
    required this.ephemera,
    required this.toolCalls,
  });

  final String theme;
  final String title;
  final List<String> palette;
  final String paper;
  final List<({String id, String reason})> scraps;
  final List<String> captions;
  final String layoutIntent;
  final List<({String kind, String prompt})> ephemera;
  final int toolCalls;

  factory BlendPlan.fromJson(Map<String, dynamic> json) {
    List<String> strings(Object? v) => List.unmodifiable(
      (v as List<dynamic>? ?? const []).whereType<String>(),
    );
    return BlendPlan(
      theme: json['theme'] as String? ?? '',
      title: json['title'] as String? ?? '',
      palette: strings(json['palette']),
      paper: json['paper'] as String? ?? 'cream',
      scraps: List.unmodifiable(
        (json['scraps'] as List<dynamic>? ?? const []).map((raw) {
          final s = raw as Map<String, dynamic>;
          return (id: s['id'] as String, reason: s['reason'] as String? ?? '');
        }),
      ),
      captions: strings(json['captions']),
      layoutIntent: json['layout_intent'] as String? ?? '',
      ephemera: List.unmodifiable(
        (json['ephemera'] as List<dynamic>? ?? const []).map((raw) {
          final e = raw as Map<String, dynamic>;
          return (
            kind: e['kind'] as String? ?? '',
            prompt: e['prompt'] as String? ?? '',
          );
        }),
      ),
      toolCalls: json['tool_calls'] as int? ?? 0,
    );
  }
}
