import 'package:flutter/foundation.dart';

/// Lightweight, toggleable stage timing for the scan pipeline (V3 Phase 0).
///
/// Usage:
///   final r = ScanPerf.time('warp', () => warpQuadCv(...));
///   final r = await ScanPerf.timeAsync('renderPage', () => renderPage(...));
///
/// Prints `[ScanPerf] <stage>: <ms>ms` via debugPrint. Works inside worker
/// isolates too (each isolate gets its own copy of the static state; prints
/// from any isolate reach the same log). Enabled only in debug/profile builds
/// by default; flip [enabled] to force on/off.
///
/// This is deliberately dependency-free and allocation-light so wrapping a
/// hot stage does not perturb what it measures.
class ScanPerf {
  ScanPerf._();

  /// Master switch. ON in all build modes while the scanner is being
  /// stabilised — the client-side release APK must emit `[ScanPerf]` lines
  /// to adb logcat so slow stages can be diagnosed from the field. Flip to
  /// `!kReleaseMode` once V3 performance is signed off.
  static bool enabled = true;

  /// Most recent duration per stage (ms) — read by the debug overlay/screen.
  static final Map<String, int> lastMs = {};

  /// Running count + total per stage so averages can be dumped.
  static final Map<String, int> _count = {};
  static final Map<String, int> _totalMs = {};

  static T time<T>(String stage, T Function() body) {
    if (!enabled) return body();
    final sw = Stopwatch()..start();
    try {
      return body();
    } finally {
      _record(stage, sw.elapsedMilliseconds);
    }
  }

  static Future<T> timeAsync<T>(String stage, Future<T> Function() body) async {
    if (!enabled) return body();
    final sw = Stopwatch()..start();
    try {
      return await body();
    } finally {
      _record(stage, sw.elapsedMilliseconds);
    }
  }

  static void _record(String stage, int ms) {
    lastMs[stage] = ms;
    _count[stage] = (_count[stage] ?? 0) + 1;
    _totalMs[stage] = (_totalMs[stage] ?? 0) + ms;
    debugPrint('[ScanPerf] $stage: ${ms}ms');
  }

  /// One-shot summary (stage → count/avg/last), for the hidden debug screen.
  static String dump() {
    final b = StringBuffer('[ScanPerf] summary\n');
    for (final stage in _count.keys) {
      final n = _count[stage]!;
      final avg = (_totalMs[stage]! / n).toStringAsFixed(1);
      b.writeln('  $stage: n=$n avg=${avg}ms last=${lastMs[stage]}ms');
    }
    return b.toString();
  }

  static void reset() {
    lastMs.clear();
    _count.clear();
    _totalMs.clear();
  }
}
