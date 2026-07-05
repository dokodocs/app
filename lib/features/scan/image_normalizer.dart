import 'dart:io';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Ensures an imported image can be read by the `image` package pipeline
/// (filters, crop, PDF/JPEG export).
///
/// Gallery pickers hand back whatever the OS stored — including formats the
/// pure-Dart `image` package cannot decode (HEIC/HEIF from modern iPhones and
/// many Android phones, some progressive or CMYK JPEGs). Those later failed
/// deep in the render isolate with "Could not decode image at …" and the
/// document silently failed to save.
///
/// Strategy: first try the fast path (`img.decodeImage`). If that fails, fall
/// back to Flutter's platform image codec (`dart:ui`), which uses the OS
/// decoder and handles essentially anything the gallery can show, then
/// re-encode to a PNG the pipeline is guaranteed to read. Returns a path safe
/// for the rest of the pipeline, or null if the file is genuinely unreadable
/// (e.g. corrupt / not an image) so the caller can skip it.
Future<String?> normalizeImageForPipeline(String path) async {
  final file = File(path);
  if (!file.existsSync()) return null;

  final bytes = await file.readAsBytes();

  // Fast path: the `image` package can already decode it — use as-is.
  if (img.decodeImage(bytes) != null) return path;

  // Fallback: decode via the platform codec and re-encode to PNG.
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final data =
        await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    if (data == null) return null;

    final dir = await getTemporaryDirectory();
    final outPath = p.join(
      dir.path,
      'import_${DateTime.now().microsecondsSinceEpoch}_'
          '${p.basenameWithoutExtension(path)}.png',
    );
    await File(outPath).writeAsBytes(data.buffer.asUint8List());
    return outPath;
  } catch (_) {
    return null; // genuinely undecodable — caller skips it
  }
}
