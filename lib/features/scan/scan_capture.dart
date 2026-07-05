import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/database/database_provider.dart';
import '../../core/l10n/app_localizations.dart';
import 'camera_scanner_screen.dart';
import 'crop_editor_screen.dart';
import 'document_detector.dart';
import 'image_normalizer.dart';
import 'providers/scan_session_provider.dart';
import 'scan_review_screen.dart';

/// What the user picked in the unified capture chooser.
enum ScanChoice { singleCamera, multiCamera, gallery }

/// Entry point for the whole scan flow. Shows ONE chooser offering single-page
/// camera, multi-page (batch) camera, and gallery import together, requests
/// camera permission when needed, drives the OpenCV scanner (or gallery
/// import), appends the results to a FRESH [scanSessionProvider] session, and
/// opens [ScanReviewScreen].
///
/// Scanner engine: the app uses its OWN OpenCV pipeline (live edge detection,
/// auto-crop, perspective correction, continuous multi-shot) as the single
/// scanner — no ML Kit / VisionKit — so it behaves identically on every device
/// with no dependency on Google Play services.
///
/// [folderId], if given, is the folder the resulting document(s) save into.
Future<void> startScanFlow(
  BuildContext context,
  WidgetRef ref, {
  int? folderId,
}) async {
  final choice = await _chooseScanMode(context);
  if (choice == null || !context.mounted) return; // dismissed
  await _runCapture(context, ref, choice: choice, folderId: folderId);
}

/// Direct gallery import (Home empty-state secondary action) — same pipeline,
/// skipping the chooser.
Future<void> startImportFromGalleryFlow(
  BuildContext context,
  WidgetRef ref, {
  int? folderId,
}) async {
  await _runCapture(
    context,
    ref,
    choice: ScanChoice.gallery,
    folderId: folderId,
  );
}

Future<void> _runCapture(
  BuildContext context,
  WidgetRef ref, {
  required ScanChoice choice,
  int? folderId,
}) async {
  // Start every capture from a clean session. Without this, a session the
  // user backed out of (without saving) leaves stale pages behind, so the
  // NEXT scan/gallery import appends to them or appears to "only work once".
  ref.read(scanSessionProvider.notifier).clear();

  final isGallery = choice == ScanChoice.gallery;
  final noOfPages = choice == ScanChoice.singleCamera ? 1 : 100;

  // Camera capture needs the camera permission; the system photo picker used
  // for gallery import does not (Android 13+/iOS handle access themselves).
  if (!isGallery) {
    final status = await Permission.camera.status;
    if (!status.isGranted) {
      final requested = await Permission.camera.request();
      if (!requested.isGranted) {
        if (!context.mounted) return;
        await _showPermissionDeniedDialog(
          context,
          requested.isPermanentlyDenied,
        );
        return;
      }
    }
  }

  List<String>? paths;

  if (isGallery) {
    // Multi-select photo picker → many images into one multi-page document.
    // Normalize each pick so formats the render pipeline can't decode
    // (HEIC/HEIF, some progressive/CMYK JPEGs) are converted up front instead
    // of failing later; undecodable files are skipped and reported.
    try {
      final picked = await ImagePicker().pickMultiImage();
      final normalized = <String>[];
      var skipped = 0;
      for (final file in picked) {
        final safe = await normalizeImageForPipeline(file.path);
        if (safe == null) {
          skipped++;
        } else {
          normalized.add(safe);
        }
      }
      if (skipped > 0) {
        if (!context.mounted) return;
        _showSkippedImages(context, skipped);
      }
      paths = normalized;
    } catch (error, stackTrace) {
      debugPrint('Gallery import failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!context.mounted) return;
      _showScannerError(context, isGallery: true);
      return;
    }
  } else {
    // The OpenCV scanner — the ONLY camera scanner. Live edge detection,
    // auto-crop, perspective correction and continuous multi-shot all run on
    // our own OpenCV pipeline.
    if (!context.mounted) return;
    final captured = await _captureWithCustomCamera(context, noOfPages);
    if (captured.isEmpty) return; // user cancelled
    paths = captured;
  }

  if (paths.isEmpty) return; // user cancelled

  // When no folder was specified (e.g. the center Scan button or gallery
  // import from Home), default the save destination to the user's default
  // favourite folder ("My Documents" out of the box), so scans land in a
  // folder instead of the loose root.
  var targetFolderId = folderId;
  if (targetFolderId == null) {
    final defaultFolder =
        await ref.read(foldersRepositoryProvider).getDefaultFolder();
    targetFolderId = defaultFolder?.id;
  }

  ref.read(scanIsBatchProvider.notifier).set(noOfPages != 1);
  ref.read(scanSessionProvider.notifier).addPaths(paths);

  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ScanReviewScreen(folderId: targetFolderId),
    ),
  );
}

/// Unified chooser: single camera page, multiple camera pages, or gallery
/// import — all in one sheet.
Future<ScanChoice?> _chooseScanMode(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showModalBottomSheet<ScanChoice>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(l10n.scanModeSingle),
            subtitle: Text(l10n.scanModeSingleBody),
            onTap: () =>
                Navigator.of(sheetContext).pop(ScanChoice.singleCamera),
          ),
          ListTile(
            leading: const Icon(Icons.auto_stories_outlined),
            title: Text(l10n.scanModeBatch),
            subtitle: Text(l10n.scanModeBatchBody),
            onTap: () =>
                Navigator.of(sheetContext).pop(ScanChoice.multiCamera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(l10n.homeImportFromGallery),
            subtitle: Text(l10n.scanModeGalleryBody),
            onTap: () => Navigator.of(sheetContext).pop(ScanChoice.gallery),
          ),
        ],
      ),
    ),
  );
}

/// Drives the OpenCV [CameraScannerScreen] — the app's only camera scanner.
/// Batch mode keeps the camera open across pages (continuous scanning) and
/// returns all pages at once; single mode returns one. Each captured page is
/// then auto-cropped + perspective-corrected; low-confidence pages open the
/// crop editor. Returns the final page paths (empty if the user cancelled).
Future<List<String>> _captureWithCustomCamera(
  BuildContext context,
  int noOfPages,
) async {
  final batch = noOfPages != 1;

  if (batch) {
    final shots = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => const CameraScannerScreen(batch: true),
      ),
    );
    if (shots == null || shots.isEmpty) return [];
    final paths = <String>[];
    for (final shot in shots) {
      if (!context.mounted) break;
      paths.add(await _autoCropOrEdit(context, shot));
    }
    return paths;
  }

  final shot = await Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => const CameraScannerScreen()),
  );
  if (shot == null || !context.mounted) return [];
  return [await _autoCropOrEdit(context, shot)];
}

/// Full-resolution re-detection + confidence-gated auto-crop for one captured
/// page. High confidence → auto-crop + perspective-correct, skip the editor.
/// Medium/low → open the crop editor (which auto-detects). Returns the final
/// page path (never fails a page — falls back to the raw/auto path).
Future<String> _autoCropOrEdit(BuildContext context, String shot) async {
  final dir = await getTemporaryDirectory();
  final outPath = p.join(
    dir.path,
    'autocrop_${DateTime.now().microsecondsSinceEpoch}.jpg',
  );
  final result = await compute(autoDetectAndCrop, <String, dynamic>{
    'srcPath': shot,
    'outPath': outPath,
  });
  final confidence = (result['confidence'] as num).toDouble();
  final autoPath = result['path'] as String;

  if (confidence >= kHighConfidence && result['cropped'] == true) {
    return autoPath; // trust the auto-crop, no editor
  }
  if (!context.mounted) return autoPath;
  final seed = result['cropped'] == true ? autoPath : shot;
  final cropped = await Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => CropEditorScreen(imagePath: seed)),
  );
  return cropped ?? seed;
}

void _showSkippedImages(BuildContext context, int count) {
  final l10n = AppLocalizations.of(context);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(l10n.scanSkippedImages(count))),
  );
}

void _showScannerError(BuildContext context, {required bool isGallery}) {
  final l10n = AppLocalizations.of(context);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        isGallery ? l10n.scanGalleryError : l10n.scanScannerError,
      ),
    ),
  );
}

Future<void> _showPermissionDeniedDialog(
  BuildContext context,
  bool permanentlyDenied,
) {
  final l10n = AppLocalizations.of(context);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.scanCameraPermissionTitle),
      content: Text(l10n.scanCameraPermissionBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(
            permanentlyDenied ? l10n.scanOpenSettings : l10n.scanTryAgain,
          ),
        ),
      ],
    ),
  ).then((_) {
    if (permanentlyDenied) {
      openAppSettings();
    }
  });
}
