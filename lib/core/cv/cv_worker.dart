import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../../features/scan/document_detector_cv.dart';

/// Result of one live-frame detection from the [CvWorker], in the ROTATED
/// (upright, preview-oriented) pixel space of the analysed frame.
class LiveDetection {
  const LiveDetection({
    required this.corners,
    required this.confidence,
    required this.width,
    required this.height,
  });

  /// 8 doubles: TLx,TLy, TRx,TRy, BRx,BRy, BLx,BLy.
  final List<double> corners;
  final double confidence;

  /// Dimensions of the (rotated) analysed frame the corners refer to —
  /// normalise against these.
  final int width;
  final int height;
}

/// A LONG-LIVED OpenCV worker isolate for live document detection (V3).
///
/// Replaces the per-frame `compute()` + PNG-encode hot path: raw grayscale
/// pixels travel to a single persistent isolate via [TransferableTypedData]
/// (zero-copy transfer, no codec anywhere), the isolate builds a Mat directly
/// and runs the Canny/contour pipeline (`detectDocumentCvGray`).
///
/// Latest-frame-only mailbox: at most ONE request is in flight and at most
/// ONE is queued. Submitting while a frame is queued REPLACES the queued
/// frame (its future resolves null). So under load the worker always
/// processes the freshest frame and detection throughput self-paces to
/// whatever the device can sustain — no wall-clock throttle needed.
class CvWorker {
  CvWorker._(this._isolate, this._toWorker, this._fromWorker) {
    _sub = _fromWorker.listen(_onResult);
  }

  final Isolate _isolate;
  final SendPort _toWorker;
  final ReceivePort _fromWorker;
  late final StreamSubscription<dynamic> _sub;

  int _nextId = 0;
  bool _disposed = false;

  // In-flight request and the single queued (latest) one.
  _Request? _inFlight;
  _Request? _queued;

  static Future<CvWorker> spawn() async {
    final handshake = ReceivePort();
    final isolate = await Isolate.spawn(
      _workerMain,
      handshake.sendPort,
      debugName: 'cv_worker',
    );
    final fromWorker = ReceivePort();
    // First message from the worker is its command port.
    final toWorker = await handshake.first as SendPort;
    toWorker.send(fromWorker.sendPort);
    handshake.close();
    return CvWorker._(isolate, toWorker, fromWorker);
  }

  /// Whether the worker is saturated (a frame in flight AND one queued).
  /// Callers can use this to skip even building the grayscale for a frame.
  bool get isSaturated => _inFlight != null && _queued != null;

  /// Detect a document quad on a raw grayscale frame ([width]×[height],
  /// row-major 8-bit). [rotationDegrees] is the sensor orientation baked in
  /// worker-side via native cv.rotate. Resolves with the detection, null when
  /// no quad was found, or null when this frame was superseded by a newer one.
  Future<LiveDetection?> detect(
    Uint8List gray,
    int width,
    int height, {
    int rotationDegrees = 0,
    double? focusX,
    double? focusY,
  }) {
    if (_disposed) return Future.value(null);
    final id = _nextId++;
    final req = _Request(
      id: id,
      payload: [
        id,
        width,
        height,
        rotationDegrees,
        focusX ?? -1.0,
        focusY ?? -1.0,
        TransferableTypedData.fromList([gray]),
      ],
    );
    if (_inFlight == null) {
      _dispatch(req);
    } else {
      // Replace any queued frame — latest-only.
      _queued?.completer.complete(null);
      _queued = req;
    }
    return req.completer.future;
  }

  void _dispatch(_Request req) {
    _inFlight = req;
    _toWorker.send(req.payload);
  }

  void _onResult(dynamic message) {
    final list = message as List<dynamic>;
    final id = list[0] as int;
    final current = _inFlight;
    if (current == null || current.id != id) return; // stale/unknown
    _inFlight = null;

    LiveDetection? result;
    if (list[1] != null) {
      result = LiveDetection(
        corners: (list[1] as List).cast<double>(),
        confidence: list[2] as double,
        width: list[3] as int,
        height: list[4] as int,
      );
    }
    current.completer.complete(result);

    final next = _queued;
    _queued = null;
    if (next != null && !_disposed) _dispatch(next);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _inFlight?.completer.complete(null);
    _inFlight = null;
    _queued?.completer.complete(null);
    _queued = null;
    _sub.cancel();
    _fromWorker.close();
    _isolate.kill(priority: Isolate.immediate);
  }

  // ---- isolate side ----

  static Future<void> _workerMain(SendPort handshake) async {
    final commands = ReceivePort();
    handshake.send(commands.sendPort);

    SendPort? results;
    await for (final message in commands) {
      if (message is SendPort) {
        results = message;
        continue;
      }
      final list = message as List<dynamic>;
      final id = list[0] as int;
      final width = list[1] as int;
      final height = list[2] as int;
      final rotation = list[3] as int;
      final fx = list[4] as double;
      final fy = list[5] as double;
      final bytes =
          (list[6] as TransferableTypedData).materialize().asUint8List();

      List<double>? corners;
      double confidence = 0;
      var outW = width, outH = height;
      try {
        final hit = detectDocumentCvGray(
          bytes,
          width,
          height,
          rotationDegrees: rotation,
          focusX: fx >= 0 ? fx : null,
          focusY: fy >= 0 ? fy : null,
        );
        if (rotation % 180 != 0) {
          outW = height;
          outH = width;
        }
        if (hit != null) {
          final q = hit.quad;
          corners = [
            q.tl.x, q.tl.y, q.tr.x, q.tr.y,
            q.br.x, q.br.y, q.bl.x, q.bl.y,
          ];
          confidence = hit.confidence;
        }
      } catch (_) {
        // Never let a bad frame kill the worker.
      }
      results?.send([id, corners, confidence, outW, outH]);
    }
  }
}

class _Request {
  _Request({required this.id, required this.payload});
  final int id;
  final List<Object> payload;
  final completer = Completer<LiveDetection?>();
}
