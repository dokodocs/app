import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/database/database_provider.dart';
import '../../core/l10n/app_localizations.dart';
import '../editor/editor_screen.dart';
import 'camera_scanner_screen.dart';
import 'document_builder.dart';
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
  // Background crops start immediately; auto-save waits for them.
  autoCropSessionPagesInBackground(ref, paths);

  if (!context.mounted) return;
  // FULLY AUTOMATIC SAVE (client): no review stop, no save button — the
  // captured pages save as a PDF right away and the PDF opens directly.
  await autoSaveSessionAndOpen(context, ref, folderId: targetFolderId);
}

/// Waits for the background crops, saves the session as a PDF with an
/// auto-generated name, clears the session, and opens the saved PDF in the
/// editor — no dialogs, no review stop, no visible "saving" screen beyond a
/// brief inline progress indicator.
Future<void> autoSaveSessionAndOpen(
  BuildContext context,
  WidgetRef ref, {
  int? folderId,
}) async {
  final l10n = AppLocalizations.of(context);
  // Minimal progress while crops+save run (typically 1–3 s with the native
  // pipeline). The dialog is closed via [closeDialog] on EVERY exit path —
  // an early return that skipped the pop left the app "stuck saving"
  // forever even though the file was already on disk.
  var dialogClosed = false;
  void closeDialog() {
    if (dialogClosed || !context.mounted) return;
    dialogClosed = true;
    Navigator.of(context, rootNavigator: true).pop();
  }

  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  ).then((_) => dialogClosed = true));

  List<int>? documentIds;
  try {
    // Wait for background crops (bounded).
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (ref.read(scanSessionProvider).any((p) => p.processing) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final pages = ref.read(scanSessionProvider);
    if (pages.isNotEmpty) {
      final settings = await ref.read(userSettingsRepositoryProvider).get();
      documentIds = await saveScanSessionAsDocument(
        pages: pages,
        documentsRepository: ref.read(documentsRepositoryProvider),
        pagesRepository: ref.read(pagesRepositoryProvider),
        title: 'dokodocs_${DateTime.now().millisecondsSinceEpoch}',
        format: ExportFormat.pdf,
        folderId: folderId,
        applyWatermark: true,
        watermarkPosition: settings.watermarkPosition,
      );
      ref.read(scanSessionProvider.notifier).clear();
    }
  } catch (error) {
    closeDialog();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.scanSaveFailed('$error'))),
      );
    }
    return;
  }

  closeDialog();
  if (documentIds == null || documentIds.isEmpty || !context.mounted) return;
  final firstId = documentIds.first;
  // Open the saved PDF directly.
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => EditorScreen(documentId: firstId),
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
/// returns all pages at once; single mode returns one. Returns the RAW shot
/// paths immediately (empty if the user cancelled) — cropping happens in the
/// BACKGROUND via [autoCropSessionPagesInBackground], not here, so the review
/// screen opens instantly (client: capture → review with no crop-editor stop;
/// "crop should be done in background").
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
    return shots ?? [];
  }

  final shot = await Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => const CameraScannerScreen()),
  );
  return shot == null ? [] : [shot];
}

/// Kicks a BACKGROUND full-resolution re-detect + perspective crop for each
/// raw page in [paths]. Each page is processed off the UI thread and, when
/// the detection is confident enough (≥ medium), the session page is swapped
/// in-place — matched by PATH, so deleting/reordering pages while one is
/// still processing can never touch the wrong page. Low-confidence pages
/// stay raw; the user can still crop manually from the review screen.
void autoCropSessionPagesInBackground(WidgetRef ref, List<String> paths) {
  final session = ref.read(scanSessionProvider.notifier);
  for (final shot in paths) {
    session.setProcessing(shot, true);
    unawaited(() async {
      try {
        final dir = await getTemporaryDirectory();
        final outPath = p.join(
          dir.path,
          'autocrop_${DateTime.now().microsecondsSinceEpoch}_'
          '${shot.hashCode.toRadixString(16)}.jpg',
        );
        final result = await compute(autoDetectAndCrop, <String, dynamic>{
          'srcPath': shot,
          'outPath': outPath,
        });
        if (result['cropped'] == true) {
          // replacePath also clears the processing badge.
          session.replacePath(shot, result['path'] as String);
        } else {
          session.setProcessing(shot, false);
        }
      } catch (_) {
        // A failed crop leaves the raw page in place — never breaks review.
        session.setProcessing(shot, false);
      }
    }());
  }
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
