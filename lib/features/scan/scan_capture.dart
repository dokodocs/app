import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/database/database_provider.dart';
import '../../core/l10n/app_localizations.dart';
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
  try {
    if (isGallery) {
      // image_picker's multi-select photo picker — unlike the native
      // document scanner's gallery mode, this lets the user pick MANY
      // images at once to turn into a multi-page document.
      final picked = await ImagePicker().pickMultiImage();
      paths = [for (final file in picked) file.path];
    } else {
      paths = await CunningDocumentScanner.getPictures(
        scannerSource: source,
        noOfPages: noOfPages,
      );
    }
  } catch (error) {
    // The ML Kit document scanner requires up-to-date Google Play services and
    // fails outright on devices/emulators without it — the "cannot open
    // camera / Google Play services issue". Rather than dead-end with an
    // error, fall back to the plain system camera (image_picker) so the user
    // can still capture a page. Gallery import has no such dependency.
    if (isGallery) {
      if (!context.mounted) return;
      _showScannerError(context, isGallery: true);
      return;
    }
    final fallback = await _captureWithBasicCamera(noOfPages);
    if (fallback.isEmpty) return; // user cancelled the fallback camera
    paths = fallback;
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

/// Basic-camera fallback used when the ML Kit document scanner is unavailable
/// (missing/outdated Google Play services). Captures one photo per shot; for
/// batch mode ([noOfPages] > 1) it keeps offering to snap another until the
/// user cancels. Returns the captured file paths (empty if none).
Future<List<String>> _captureWithBasicCamera(int noOfPages) async {
  final picker = ImagePicker();
  final paths = <String>[];
  final batch = noOfPages != 1;
  while (true) {
    final shot = await picker.pickImage(
      source: ImageSource.camera,
      // Documents are shot with the rear camera — never default to selfie.
      preferredCameraDevice: CameraDevice.rear,
    );
    if (shot == null) break; // user backed out of the camera
    paths.add(shot.path);
    if (!batch) break; // single-page mode: one shot only
  }
  return paths;
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
