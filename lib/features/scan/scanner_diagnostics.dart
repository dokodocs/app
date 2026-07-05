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

  static void recordNativeError(Object error, [StackTrace? stackTrace]) {
    final buf = StringBuffer(error.toString());
    // PlatformException carries the native (Java/Kotlin) stack in .stacktrace,
    // which is the useful part for diagnosing an ML Kit NPE — include it.
    try {
      final dynamic e = error;
      final native = e.stacktrace ?? e.stackTrace;
      if (native != null) buf.write('\n\nNative stack:\n$native');
    } catch (_) {/* not a PlatformException */}
    if (stackTrace != null) buf.write('\n\nDart stack:\n$stackTrace');
    lastNativeError = buf.toString();
    lastPath = ScannerPath.fallback;
  }

  static void recordNativeSuccess() {
    lastPath = ScannerPath.native;
  }
}

enum ScannerPath { native, fallback }
