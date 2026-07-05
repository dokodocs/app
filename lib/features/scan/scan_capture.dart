import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
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
import 'scanner_diagnostics.dart';
import 'providers/scan_session_provider.dart';
import 'scan_review_screen.dart';

/// What the user picked in the unified capture chooser.
enum ScanChoice { singleCamera, multiCamera, gallery }

/// Entry point for the whole scan flow. Shows ONE chooser offering single-page
/// camera, multi-page (batch) camera, and gallery import together (spec §1 /
/// user feedback: these belong in one place, not scattered tabs), requests
/// camera permission when needed, invokes the native scanner, appends the
/// results to a FRESH [scanSessionProvider] session, and opens
/// [ScanReviewScreen].
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
  final source = isGallery ? ScannerSource.gallery : ScannerSource.camera;
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

  // If the native scanner is already known to be broken on this device (it
  // throws an internal NullPointerException inside ML Kit Document Scanner
  // 16.0.0 on some devices), skip it entirely and go straight to the OpenCV
  // custom camera — no repeated error dialog, no wasted launch attempt.
  final skipNative = !isGallery && await _nativeScannerBroken();
  if (skipNative) {
    if (!context.mounted) return;
    final fallback = await _captureWithCustomCamera(context, noOfPages);
    if (fallback.isEmpty) return;
    paths = fallback;
  } else {
  try {
    if (isGallery) {
      // image_picker's multi-select photo picker — unlike the native
      // document scanner's gallery mode, this lets the user pick MANY
      // images at once to turn into a multi-page document.
      final picked = await ImagePicker().pickMultiImage();
      // Normalize each pick so formats the render pipeline can't decode
      // (HEIC/HEIF, some progressive/CMYK JPEGs) are converted up front
      // instead of failing later with "Could not decode image". Undecodable
      // files are dropped and reported rather than aborting the whole import.
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
      if (skipped > 0 && context.mounted) {
        _showSkippedImages(context, skipped);
      }
      paths = normalized;
    } else {
      paths = await CunningDocumentScanner.getPictures(
        scannerSource: source,
        noOfPages: noOfPages,
      );
      ScannerDiagnostics.recordNativeSuccess();
    }
  } catch (error, stackTrace) {
    // Record the REAL reason the native scanner didn't run (previously
    // swallowed) so it's visible in logs and on-device (Settings → Device
    // status), then fall back to the built-in camera so capture still works.
    debugPrint('Native document scanner failed: $error');
    debugPrintStack(stackTrace: stackTrace);
    ScannerDiagnostics.recordNativeError(error, stackTrace);

    if (isGallery) {
      if (!context.mounted) return;
      _showScannerError(context, isGallery: true);
      return;
    }
    if (!context.mounted) return;
    // Surface the actual error to the user (truncated) so the fallback is no
    // longer a silent dead-end — this is the diagnostic signal.
    // Remember the native scanner is broken here so future scans skip it and
    // go straight to the working OpenCV camera (no repeated error).
    await _markNativeScannerBroken();
    if (!context.mounted) return;
    _showUsingFallbackCamera(context, error);
    final fallback = await _captureWithCustomCamera(context, noOfPages);
    if (fallback.isEmpty) return; // user cancelled the fallback camera
    paths = fallback;
  }
  }

  if (paths == null || paths.isEmpty) return; // user cancelled

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

/// Custom-camera fallback used when the ML Kit document scanner is unavailable
/// (missing/outdated Google Play services). Uses [CameraScannerScreen], which
/// STRICTLY opens the rear lens (the old image_picker fallback opened the
/// front camera because its rear hint is ignored on most Android devices) and
/// shows a live green document border. Each captured page is passed straight
/// into [CropEditorScreen] for auto-detect + manual adjust + perspective
/// correction, so the crop happens right after the shot. For batch mode
/// ([noOfPages] > 1) it keeps offering another page until the user backs out.
/// Returns the corrected file paths (empty if none).
Future<List<String>> _captureWithCustomCamera(
  BuildContext context,
  int noOfPages,
) async {
  final batch = noOfPages != 1;

  if (batch) {
    // Continuous capture: the camera stays open and returns ALL raw pages at
    // once (no bounce back to the dashboard between pages). Each page is then
    // auto-cropped; low-confidence ones open the editor.
    final shots = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(builder: (_) => const CameraScannerScreen(batch: true)),
    );
    if (shots == null || shots.isEmpty) return [];
    final paths = <String>[];
    for (final shot in shots) {
      if (!context.mounted) break;
      final done = await _autoCropOrEdit(context, shot);
      paths.add(done);
    }
    return paths;
  }

  // Single page.
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

/// Marker file recording that the native ML Kit scanner is broken on this
/// device (its internal NPE), so we stop attempting it and go straight to the
/// OpenCV custom camera. Cleared when the Device-status scanner self-test
/// succeeds. A plain file avoids a DB migration for this one flag.
Future<File> _nativeMarkerFile() async {
  final dir = await getApplicationSupportDirectory();
  return File(p.join(dir.path, 'native_scanner_broken.flag'));
}

Future<bool> _nativeScannerBroken() async {
  try {
    return (await _nativeMarkerFile()).existsSync();
  } catch (_) {
    return false;
  }
}

Future<void> _markNativeScannerBroken() async {
  try {
    await (await _nativeMarkerFile()).create(recursive: true);
  } catch (_) {/* best effort */}
}

/// Clears the broken-marker so the native scanner is retried (e.g. after a
/// successful Device-status self-test, or a Play services update).
Future<void> clearNativeScannerBrokenFlag() async {
  try {
    final f = await _nativeMarkerFile();
    if (f.existsSync()) await f.delete();
  } catch (_) {/* best effort */}
}

void _showSkippedImages(BuildContext context, int count) {
  final l10n = AppLocalizations.of(context);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(l10n.scanSkippedImages(count))),
  );
}

void _showUsingFallbackCamera(BuildContext context, Object error) {
  final l10n = AppLocalizations.of(context);
  final short = error.toString();
  final trimmed = short.length > 120 ? '${short.substring(0, 120)}…' : short;
  final full = ScannerDiagnostics.lastNativeError ?? short;
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 8),
      content: Text('${l10n.scanUsingFallbackCamera}\n$trimmed'),
      action: SnackBarAction(
        label: l10n.scanErrorDetails,
        onPressed: () => showScannerErrorDialog(context, full),
      ),
    ),
  );
}

/// A scrollable, SELECTABLE dialog showing the full native-scanner error with
/// a Copy button — so the whole log can be copied and shared for diagnosis.
Future<void> showScannerErrorDialog(BuildContext context, String fullError) {
  final l10n = AppLocalizations.of(context);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.scanErrorDetails),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: SelectableText(
            fullError,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy, size: 18),
          label: Text(l10n.commonCopy),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: fullError));
            if (dialogContext.mounted) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                SnackBar(content: Text(l10n.commonCopied)),
              );
            }
          },
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.dialogClose),
        ),
      ],
    ),
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
