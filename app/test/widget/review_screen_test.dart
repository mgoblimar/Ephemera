import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:ephemera_ai/data/proxy_client.dart';
import 'package:ephemera_ai/features/capture/review_screen.dart';
import 'package:ephemera_ai/providers.dart';

import '../fakes.dart';

Widget _app(http.Client httpClient) => ProviderScope(
  overrides: [
    proxyClientProvider.overrideWithValue(
      ProxyClient(baseUrl: 'http://proxy', httpClient: httpClient),
    ),
  ],
  child: MaterialApp(
    home: CaptureReviewScreen(
      photo: Uint8List.fromList([1]),
      filename: 'desk.jpg',
    ),
  ),
);

void main() {
  testWidgets('shows found masks as chips, all kept by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(fakeProxy((_) => okEnvelope(segmentAutoData(masks: 3)))),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FilterChip), findsNWidgets(3));
    expect(find.text('Save 3 scraps'), findsOneWidget);
  });

  testWidgets('fits a small phone screen without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(fakeProxy((_) => okEnvelope(segmentAutoData(masks: 6)))),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Save 6 scraps'), findsOneWidget);
  });

  testWidgets('toggling a chip discards that mask', (tester) async {
    await tester.pumpWidget(
      _app(fakeProxy((_) => okEnvelope(segmentAutoData(masks: 3)))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterChip, '2'));
    await tester.pump();

    expect(find.text('Save 2 scraps'), findsOneWidget);
  });

  testWidgets('tapping the photo adds a mask via point segmentation', (
    tester,
  ) async {
    final log = <http.Request>[];
    final proxy = fakeProxy(
      (request) => request.url.path == '/segment/point'
          ? okEnvelope({
              'mask': maskJson('added', [150, 100, 50, 50]),
            })
          : okEnvelope(segmentAutoData(masks: 1)),
      log: log,
    );
    await tester.pumpWidget(_app(proxy));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Image).first);
    await tester.pumpAndSettle();

    final pointRequest = log.singleWhere((r) => r.url.path == '/segment/point');
    expect((jsonDecode(pointRequest.body) as Map)['image_id'], 'img1');
    expect(find.byType(FilterChip), findsNWidgets(2));
    expect(find.text('Save 2 scraps'), findsOneWidget);
  });

  testWidgets('shows the server error with a retry button', (tester) async {
    await tester.pumpWidget(
      _app(
        fakeProxy(
          (_) => {
            'ok': false,
            'data': null,
            'error': {
              'code': 'unsupported_image',
              'message': "That file isn't a readable image.",
            },
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("That file isn't a readable image."), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
