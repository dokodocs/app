/// Captures WHY the native ML Kit / VisionKit scanner didn't run, so the
/// reason is visible on-device (Settings → Device status) instead of being
/// swallowed by the fallback `catch`. Populated the moment the native scanner
/// throws; read by the diagnostics UI. Deliberately a tiny global (not a
/// provider) so any capture path can record into it without plumbing.
class ScannerDiagnostics {
  ScannerDiagnostics._();

  /// The last exception thrown by the native scanner, as text (null = the
  /// native scanner has not failed this session).
  static String? lastNativeError;

  /// Which path the most recent capture actually used.
  static ScannerPath? lastPath;

  /// When [lastNativeError] was recorded (for display), millis since epoch.
  static int? lastErrorAtMillis;

  static void recordNativeError(Object error) {
    lastNativeError = error.toString();
    lastPath = ScannerPath.fallback;
  }

  static void recordNativeSuccess() {
    lastPath = ScannerPath.native;
  }
}

enum ScannerPath { native, fallback }
