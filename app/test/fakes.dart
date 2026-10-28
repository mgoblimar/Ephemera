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
