import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:http/http.dart' as http;

import 'package:ephemera_ai/models/segmentation.dart';

const _requestTimeout = Duration(seconds: 30);

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

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) {
    return _send(
      () => _http.post(
        _uri(path),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ),
    );
  }

  /// Sends a request and unwraps the {ok, data, error} envelope.
  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() request,
  ) async {
    final http.Response response;
    try {
      response = await request().timeout(_requestTimeout);
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
