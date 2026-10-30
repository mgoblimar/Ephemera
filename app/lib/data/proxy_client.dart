import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:http/http.dart' as http;

import 'package:ephemera_ai/models/blend_plan.dart';
import 'package:ephemera_ai/models/scan.dart';
import 'package:ephemera_ai/models/scrap.dart';
import 'package:ephemera_ai/models/segmentation.dart';

const _requestTimeout = Duration(seconds: 30);

/// Detection and batched cutting upload/download full-size images.
const _slowRequestTimeout = Duration(seconds: 90);

/// The agent searches the archive over several model turns.
const _agentTimeout = Duration(seconds: 150);

/// Error from the proxy, carrying its envelope code and a user-facing message.
class ProxyException implements Exception {
  const ProxyException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'ProxyException($code): $message';
}

/// Typed client for the EphemeraAI FastAPI proxy.
class ProxyClient {
  ProxyClient({required this.baseUrl, http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _http;

  Future<SegmentResult> segmentAuto(
    Uint8List photo, {
    String filename = 'photo.jpg',
  }) async {
    final request = http.MultipartRequest('POST', _uri('/segment/auto'))
      ..files.add(
        http.MultipartFile.fromBytes('image', photo, filename: filename),
      );
    final data = await _send(
      () async => http.Response.fromStream(await _http.send(request)),
    );
    return SegmentResult(
      imageId: data['image_id'] as String,
      width: data['width'] as int,
      height: data['height'] as int,
      photoJpeg: base64Decode(data['photo_jpeg'] as String),
      masks: List.unmodifiable(
        (data['masks'] as List<dynamic>).map(
          (m) => _mask(m as Map<String, dynamic>),
        ),
      ),
    );
  }

  Future<MaskCandidate> segmentPoint(
    String imageId,
    List<TapPoint> points,
  ) async {
    final data = await _postJson('/segment/point', {
      'image_id': imageId,
      'points': points.map((p) => p.toJson()).toList(),
    });
    return _mask(data['mask'] as Map<String, dynamic>);
  }

  Future<List<CutoutScrap>> cutout({
    required String imageId,
    required List<String> maskIds,
    required CutStyle style,
    required CutSize size,
  }) async {
    final data = await _postJson('/cutout', {
      'image_id': imageId,
      'mask_ids': maskIds,
      'cut_style': style.name,
      'cut_size': size.name,
    });
    return List.unmodifiable(
      (data['scraps'] as List<dynamic>).map((raw) {
        final s = raw as Map<String, dynamic>;
        return CutoutScrap(
          maskId: s['mask_id'] as String,
          png: base64Decode(s['png_base64'] as String),
          width: s['width'] as int,
          height: s['height'] as int,
          palette: List.unmodifiable(
            (s['palette'] as List<dynamic>).cast<String>(),
          ),
        );
      }),
    );
  }

  /// Theme Blend agent: plans a page from the archive. Slow (agent loop).
  Future<BlendPlan> agentPlan({
    required String theme,
    required List<Scrap> archive,
    List<String> pinnedIds = const [],
  }) async {
    final data = await _postJson('/agent/plan', {
      'theme': theme,
      'pinned_ids': pinnedIds,
      'archive': [
        for (final s in archive)
          {
            'id': s.id,
            'type': s.type,
            'tags': s.tags.take(20).toList(),
            'ocr_text': s.ocrText.length > 1000
                ? s.ocrText.substring(0, 1000)
                : s.ocrText,
            'mood': s.mood.take(10).toList(),
            'description': s.description.length > 600
                ? s.description.substring(0, 600)
                : s.description,
            'palette': s.palette.take(8).toList(),
          },
      ],
    }, timeout: _agentTimeout);
    return BlendPlan.fromJson(data);
  }

  /// Theme Blend build step: the agent arranges the plan's scraps on a page.
  Future<Map<String, dynamic>> agentLayout({
    required BlendPlan plan,
    required List<Scrap> scraps,
  }) {
    return _postJson('/agent/layout', {
      'title': plan.title,
      'layout_intent': plan.layoutIntent,
      'paper': plan.paper,
      'scraps': [
        for (final s in scraps.take(12))
          {
            'id': s.id,
            'aspect': s.height / s.width,
            'type': s.type,
            'description': s.description.length > 600
                ? s.description.substring(0, 600)
                : s.description,
          },
      ],
      'captions': plan.captions.take(3).toList(),
    }, timeout: _agentTimeout);
  }

  /// Muse Spark reads a scrap: OCR text, entities, tags, mood, description.
  Future<Map<String, dynamic>> enrich(Uint8List scrapPng) async {
    final request = http.MultipartRequest('POST', _uri('/enrich'))
      ..files.add(
        http.MultipartFile.fromBytes('scrap', scrapPng, filename: 'scrap.png'),
      );
    return _send(
      () async => http.Response.fromStream(await _http.send(request)),
      timeout: _slowRequestTimeout,
    );
  }

  /// Detect pieces in a photo without cutting them (cheap: no SAM call).
  Future<ScanPhoto> scanDetect(
    Uint8List photo, {
    String filename = 'photo.jpg',
  }) async {
    final request = http.MultipartRequest('POST', _uri('/scan/detect'))
      ..files.add(
        http.MultipartFile.fromBytes('image', photo, filename: filename),
      );
    final data = await _send(
      () async => http.Response.fromStream(await _http.send(request)),
      timeout: _slowRequestTimeout,
    );
    final imageId = data['image_id'] as String;
    final width = data['width'] as num?;
    final height = data['height'] as num?;
    final photoSize = width == null || height == null
        ? null
        : Size(width.toDouble(), height.toDouble());
    return ScanPhoto(
      imageId: imageId,
      pieces: List.unmodifiable(
        (data['pieces'] as List<dynamic>).map((raw) {
          final p = raw as Map<String, dynamic>;
          return ScanPiece(
            id: p['id'] as String,
            imageId: imageId,
            label: p['label'] as String,
            thumbJpeg: base64Decode(p['thumb_jpeg'] as String),
            box: _pieceBox(p['box']),
            photoSize: photoSize,
          );
        }),
      ),
    );
  }

  /// `[x, y, w, h]` in working pixels, or null when absent or malformed.
  static Rect? _pieceBox(Object? raw) {
    if (raw is! List || raw.length != 4 || raw.any((v) => v is! num)) {
      return null;
    }
    final v = raw.cast<num>().map((n) => n.toDouble()).toList();
    return Rect.fromLTWH(v[0], v[1], v[2], v[3]);
  }

  /// Find design elements (logos, lettering...) inside one whole piece.
  Future<List<ScanPiece>> scanSplit(ScanPiece parent) async {
    final data = await _postJson('/scan/split', {
      'image_id': parent.imageId,
      'piece_id': parent.id,
    }, timeout: _slowRequestTimeout);
    return List.unmodifiable(
      (data['pieces'] as List<dynamic>).map((raw) {
        final p = raw as Map<String, dynamic>;
        return ScanPiece(
          id: p['id'] as String,
          imageId: parent.imageId,
          label: p['label'] as String,
          thumbJpeg: base64Decode(p['thumb_jpeg'] as String),
          parentId: parent.id,
          box: _pieceBox(p['box']),
          photoSize: parent.photoSize,
        );
      }),
    );
  }

  /// Cut the chosen pieces; the proxy packs up to 16 per SAM request.
  Future<ScanCutResult> scanCut({
    required List<ScanPiece> pieces,
    required CutStyle style,
    required CutSize size,
  }) async {
    final data = await _postJson('/scan/cut', {
      'pieces': [
        for (final p in pieces) {'image_id': p.imageId, 'piece_id': p.id},
      ],
      'cut_style': style.name,
      'cut_size': size.name,
    }, timeout: _slowRequestTimeout);
    return ScanCutResult(
      scraps: List.unmodifiable(
        (data['scraps'] as List<dynamic>).map((raw) {
          final s = raw as Map<String, dynamic>;
          return (
            imageId: s['image_id'] as String,
            scrap: CutoutScrap(
              maskId: s['piece_id'] as String,
              png: base64Decode(s['png_base64'] as String),
              width: s['width'] as int,
              height: s['height'] as int,
              palette: List.unmodifiable(
                (s['palette'] as List<dynamic>).cast<String>(),
              ),
              label: s['label'] as String?,
            ),
          );
        }),
      ),
      missedCount: (data['missed'] as List<dynamic>).length,
      samRequests: data['sam_requests'] as int,
    );
  }

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body, {
    Duration timeout = _requestTimeout,
  }) {
    return _send(
      () => _http.post(
        _uri(path),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ),
      timeout: timeout,
    );
  }

  /// Sends a request and unwraps the {ok, data, error} envelope.
  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() request, {
    Duration timeout = _requestTimeout,
  }) async {
    final http.Response response;
    try {
      response = await request().timeout(timeout);
    } on Exception {
      throw const ProxyException(
        'network_error',
        "Can't reach the EphemeraAI server. Check your connection and try again.",
      );
    }

    final Map<String, dynamic> envelope;
    try {
      envelope =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } on FormatException {
      throw ProxyException(
        'bad_response',
        'Unexpected server response (HTTP ${response.statusCode}).',
      );
    }

    if (envelope['ok'] == true) return envelope['data'] as Map<String, dynamic>;
    final error = envelope['error'] as Map<String, dynamic>? ?? const {};
    throw ProxyException(
      error['code'] as String? ?? 'unknown_error',
      error['message'] as String? ?? 'Something went wrong.',
    );
  }

  static MaskCandidate _mask(Map<String, dynamic> json) {
    final box = (json['bbox'] as List<dynamic>).cast<num>();
    return MaskCandidate(
      id: json['id'] as String,
      bbox: Rect.fromLTWH(
        box[0].toDouble(),
        box[1].toDouble(),
        box[2].toDouble(),
        box[3].toDouble(),
      ),
      score: (json['score'] as num).toDouble(),
      previewPng: base64Decode(json['preview_png'] as String),
      label: json['label'] as String?,
    );
  }
}
