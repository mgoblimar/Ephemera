import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ephemera_ai/data/proxy_client.dart';
import 'package:ephemera_ai/models/segmentation.dart';

import '../fakes.dart';

void main() {
  group('ProxyClient', () {
    test('segmentAuto parses masks and photo from the envelope', () async {
      final log = <http.Request>[];
      final client = ProxyClient(
        baseUrl: 'http://proxy',
        httpClient: fakeProxy(
          (_) => okEnvelope(segmentAutoData(masks: 2)),
          log: log,
        ),
      );

      final result = await client.segmentAuto(Uint8List.fromList([1, 2, 3]));

      expect(log.single.url.toString(), 'http://proxy/segment/auto');
      expect(result.imageId, 'img1');
      expect(result.masks.map((m) => m.id), ['m0', 'm1']);
      expect(result.masks[1].bbox, const Rect.fromLTWH(110, 20, 80, 60));
      expect(result.photoJpeg, base64Decode(tinyPngBase64));
    });

    test('cutout sends style and size and parses scraps', () async {
      final log = <http.Request>[];
      final client = ProxyClient(
        baseUrl: 'http://proxy',
        httpClient: fakeProxy(
          (_) => okEnvelope({
            'scraps': [
              {
                'mask_id': 'm0',
                'png_base64': tinyPngBase64,
                'width': 1,
                'height': 1,
                'palette': ['#FFFFFF'],
              },
            ],
          }),
          log: log,
        ),
      );

      final scraps = await client.cutout(
        imageId: 'img1',
        maskIds: ['m0'],
        style: CutStyle.sticker,
        size: CutSize.l,
      );

      expect(jsonDecode(log.single.body), {
        'image_id': 'img1',
        'mask_ids': ['m0'],
        'cut_style': 'sticker',
        'cut_size': 'l',
      });
      expect(scraps.single.palette, ['#FFFFFF']);
    });

    test(
      'error envelope becomes a ProxyException with the server message',
      () async {
        final client = ProxyClient(
          baseUrl: 'http://proxy',
          httpClient: fakeProxy(
            (_) => {
              'ok': false,
              'data': null,
              'error': {'code': 'image_not_found', 'message': 'Photo expired.'},
            },
          ),
        );

        expect(
          client.segmentPoint('gone', const [TapPoint(1, 1)]),
          throwsA(
            isA<ProxyException>()
                .having((e) => e.code, 'code', 'image_not_found')
                .having((e) => e.message, 'message', 'Photo expired.'),
          ),
        );
      },
    );

    test('network failure becomes a friendly network_error', () async {
      final client = ProxyClient(
        baseUrl: 'http://proxy',
        httpClient: MockClient(
          (_) => throw http.ClientException('connection refused'),
        ),
      );

      expect(
        client.segmentPoint('img1', const [TapPoint(1, 1)]),
        throwsA(
          isA<ProxyException>().having((e) => e.code, 'code', 'network_error'),
        ),
      );
    });

    test('non-JSON response becomes bad_response', () async {
      final client = ProxyClient(
        baseUrl: 'http://proxy',
        httpClient: MockClient(
          (_) async => http.Response('<html>502</html>', 502),
        ),
      );

      expect(
        client.segmentPoint('img1', const [TapPoint(1, 1)]),
        throwsA(
          isA<ProxyException>().having((e) => e.code, 'code', 'bad_response'),
        ),
      );
    });
  });
}
