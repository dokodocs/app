import 'package:share_plus/share_plus.dart';

/// Shares one or more saved document files through the native share sheet.
/// Centralized so every "Share" entry point (tiles, editor, tools) behaves
/// identically.
Future<void> shareDocumentFiles(List<String> paths) {
  if (paths.isEmpty) return Future.value();
  return SharePlus.instance.share(
    ShareParams(files: [for (final path in paths) XFile(path)]),
  );
}

Future<void> shareDocumentFile(String path) => shareDocumentFiles([path]);
