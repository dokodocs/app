import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// The four document corners, in source-image pixel coordinates, ordered
/// top-left, top-right, bottom-right, bottom-left (clockwise from TL).
class Quad {
  const Quad(this.tl, this.tr, this.br, this.bl);
  final ({double x, double y}) tl;
  final ({double x, double y}) tr;
  final ({double x, double y}) br;
  final ({double x, double y}) bl;

  List<double> toList() =>
      [tl.x, tl.y, tr.x, tr.y, br.x, br.y, bl.x, bl.y];

  static Quad fromList(List<double> v) => Quad(
        (x: v[0], y: v[1]),
        (x: v[2], y: v[3]),
        (x: v[4], y: v[5]),
        (x: v[6], y: v[7]),
      );
}

/// Argument bundle passed to [rectifyDocument] so it can run under
/// `compute()` on a background isolate (all fields are primitives — the out
/// path is resolved on the main isolate because path_provider needs a
/// platform channel).
class CropRequest {
  const CropRequest({
    required this.srcPath,
    required this.corners,
    required this.outPath,
    this.quarterTurns = 0,
  });

  final String srcPath;

  /// 8 doubles: tlx,tly, trx,try, brx,bry, blx,bly (source pixel coords).
  final List<double> corners;
  final String outPath;

  /// Extra clockwise 90° rotations to bake in (0-3).
  final int quarterTurns;

  Map<String, dynamic> toMap() => {
        'srcPath': srcPath,
        'corners': corners,
        'outPath': outPath,
        'quarterTurns': quarterTurns,
      };

  static CropRequest fromMap(Map<String, dynamic> m) => CropRequest(
        srcPath: m['srcPath'] as String,
        corners: (m['corners'] as List).cast<double>(),
        outPath: m['outPath'] as String,
        quarterTurns: m['quarterTurns'] as int? ?? 0,
      );
}

/// Warps the quadrilateral described by [CropRequest.corners] to a flat,
/// rectangular, perspective-corrected image and writes it to `outPath` as a
/// high-quality JPEG. Returns the output path.
///
/// Top-level + primitive I/O only, so it is safe to hand to `compute()`.
/// The output dimensions are derived from the quad's own edge lengths, so
/// the flattened document keeps its real aspect ratio (no stretching), and
/// the entire quad — every corner, margin, and stamp inside it — is
/// preserved (nothing is clipped).
String rectifyDocument(Map<String, dynamic> raw) {
  final req = CropRequest.fromMap(raw);
  final bytes = File(req.srcPath).readAsBytesSync();
  var src = img.decodeImage(bytes);
  if (src == null) {
    throw StateError('Could not decode image at ${req.srcPath}');
  }

  final q = Quad.fromList(req.corners);

  double dist(({double x, double y}) a, ({double x, double y}) b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return (dx * dx + dy * dy);
  }

  // Average opposite edges so the target rectangle matches the document's
  // true proportions rather than either single (foreshortened) edge.
  final topW = _len(q.tl, q.tr);
  final bottomW = _len(q.bl, q.br);
  final leftH = _len(q.tl, q.bl);
  final rightH = _len(q.tr, q.br);
  var outW = ((topW + bottomW) / 2).round().clamp(1, 10000);
  var outH = ((leftH + rightH) / 2).round().clamp(1, 10000);
  // Guard against degenerate quads.
  if (dist(q.tl, q.br) < 4 && dist(q.tr, q.bl) < 4) {
    outW = src.width;
    outH = src.height;
  }

  final out = img.Image(width: outW, height: outH);
  img.copyRectify(
    src,
    topLeft: img.Point(q.tl.x, q.tl.y),
    topRight: img.Point(q.tr.x, q.tr.y),
    bottomLeft: img.Point(q.bl.x, q.bl.y),
    bottomRight: img.Point(q.br.x, q.br.y),
    toImage: out,
    interpolation: img.Interpolation.linear,
  );

  var result = out;
  final turns = req.quarterTurns % 4;
  if (turns != 0) {
    result = img.copyRotate(result, angle: turns * 90);
  }

  File(req.outPath).writeAsBytesSync(img.encodeJpg(result, quality: 92));
  return req.outPath;
}

double _len(({double x, double y}) a, ({double x, double y}) b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}
