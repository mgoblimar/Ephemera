/// Proxy base URL. Defaults to the Android emulator's alias for the host machine.
/// On a physical phone, pass your computer's LAN IP:
///   flutter run --dart-define=PROXY_URL=http://192.168.1.20:8000
const proxyUrl = String.fromEnvironment(
  'PROXY_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

/// Picker re-encodes photos to at most this size before upload. The proxy's
/// models see a 1536 px copy, but scraps are cut from this full-size photo,
/// so it matches the proxy's max_original_side.
const maxCaptureSide = 3072.0;
const captureJpegQuality = 90;

/// SAM cuts up to this many pieces per billed request (the proxy batches them).
const piecesPerSamRequest = 16;

/// Shown to the user before cutting; SAM 3.1 is $0.0025 per request at ₱64/USD.
const samRequestCostPesos = 0.16;
