/// Proxy base URL. Defaults to the Android emulator's alias for the host machine.
/// On a physical phone, pass your computer's LAN IP:
///   flutter run --dart-define=PROXY_URL=http://192.168.1.20:8000
const proxyUrl = String.fromEnvironment(
  'PROXY_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

/// Picker re-encodes photos to at most this size before upload (the proxy
/// downscales to 1536 px anyway, so larger uploads only waste bandwidth).
const maxCaptureSide = 2048.0;
const captureJpegQuality = 90;
