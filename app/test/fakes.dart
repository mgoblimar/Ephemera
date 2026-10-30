import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Valid 1×1 PNG, so Image.memory decodes cleanly in widget tests.
const tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

Map<String, dynamic> okEnvelope(Object data) => {
  'ok': true,
  'data': data,
  'error': null,
};

Map<String, dynamic> maskJson(String id, List<int> bbox) => {
  'id': id,
  'bbox': bbox,
  'score': 0.9,
  'label': 'sticker',
  'preview_png': tinyPngBase64,
};

Map<String, dynamic> segmentAutoData({int masks = 3}) => {
  'image_id': 'img1',
  'width': 400,
  'height': 300,
  'photo_jpeg': tinyPngBase64,
  'masks': [
    for (var i = 0; i < masks; i++) maskJson('m$i', [10 + i * 100, 20, 80, 60]),
  ],
};

Map<String, dynamic> scanDetectData(String imageId, {int pieces = 2}) => {
  'image_id': imageId,
  'width': 400,
  'height': 300,
  'pieces': [
    for (var i = 0; i < pieces; i++)
      {
        'id': 'p$i',
        'label': i.isEven ? 'sticker' : 'ticket',
        'box': [10, 10, 50, 50],
        'thumb_jpeg': tinyPngBase64,
      },
  ],
};

Map<String, dynamic> scanCutData(List<Map<String, dynamic>> refs) => {
  'scraps': [
    for (final r in refs)
      {
        'image_id': r['image_id'],
        'piece_id': r['piece_id'],
        'label': 'sticker',
        'png_base64': tinyPngBase64,
        'width': 1,
        'height': 1,
        'palette': ['#FFFFFF'],
      },
  ],
  'missed': <dynamic>[],
  'sam_requests': 1,
};

/// A fake proxy: [handler] returns the envelope for each request, which is
/// optionally recorded in [log]. Error envelopes get HTTP 404.
MockClient fakeProxy(
  Map<String, dynamic> Function(http.Request) handler, {
  List<http.Request>? log,
}) {
  return MockClient((request) async {
    log?.add(request);
    final body = handler(request);
    final status = body['ok'] == false ? 404 : 200;
    return http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );
  });
}
