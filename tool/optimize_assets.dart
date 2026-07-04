// One-off asset optimizer: downscales oversized PNGs and re-encodes them
// with stronger compression while preserving transparency, to keep the APK
// within the Nepal ≤40MB target. Run with: dart run tool/optimize_assets.dart
import 'dart:io';

import 'package:image/image.dart' as img;

Future<void> _optimize(String path, int maxSide) async {
  final file = File(path);
  if (!file.existsSync()) {
    stdout.writeln('skip (missing): $path');
    return;
  }
  final before = file.lengthSync();
  final image = img.decodeImage(await file.readAsBytes());
  if (image == null) {
    stdout.writeln('skip (undecodable): $path');
    return;
  }
  var out = image;
  if (image.width > maxSide || image.height > maxSide) {
    if (image.width >= image.height) {
      out = img.copyResize(image, width: maxSide);
    } else {
      out = img.copyResize(image, height: maxSide);
    }
  }
  await file.writeAsBytes(img.encodePng(out, level: 9));
  final after = file.lengthSync();
  stdout.writeln(
    '$path  ${image.width}x${image.height} ${(before / 1024).round()}KB'
    ' -> ${out.width}x${out.height} ${(after / 1024).round()}KB',
  );
}

Future<void> main() async {
  await _optimize('assets/illustrations/onboard_scan.png', 1080);
  await _optimize('assets/illustrations/onboard_organize.png', 1080);
  await _optimize('assets/illustrations/onboard_own.png', 1080);
  await _optimize('assets/logo/wordmark.png', 900);
  await _optimize('assets/logo/wordmark_ne.png', 900);
  await _optimize('assets/icon/icon_1024_dark.png', 1024);
}
