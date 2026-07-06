import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/scan_page.dart';

/// Default enhancement applied to every freshly captured/imported page, so a
/// scan looks clean and UNIFORM out of the box (shadow-removed, whitened,
/// sharpened colour — the "Magic Color" look) without the user having to pick a
/// filter per page. They can still switch any page (incl. back to Original) in
/// the review/edit filter row.
const kDefaultScanFilter = 'magic';

/// Holds the in-progress multi-page scan session (capture -> reorder ->
/// retake -> filter -> save). Cleared once the session is saved as a
/// [Document], or discarded.
class ScanSessionNotifier extends Notifier<List<ScanPage>> {
  @override
  List<ScanPage> build() => const [];

  void addPaths(List<String> paths) {
    state = [
      ...state,
      ...paths.map((p) => ScanPage(imagePath: p, filter: kDefaultScanFilter)),
    ];
  }

  /// `newIndex` is expected already adjusted for the removed item at
  /// `oldIndex` — i.e. the value `ReorderableListView.onReorderItem` hands
  /// back (not the legacy, unadjusted `onReorder` value).
  void reorder(int oldIndex, int newIndex) {
    final list = [...state];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    state = list;
  }

  void removeAt(int index) {
    final list = [...state]..removeAt(index);
    state = list;
  }

  void replaceAt(int index, String newImagePath) {
    final list = [...state];
    list[index] = list[index].copyWith(
      imagePath: newImagePath,
      // A retaken/auto-cropped page keeps the default enhancement so the set
      // stays uniform (was 'original', which left retakes looking different).
      filter: kDefaultScanFilter,
      rotation: 0,
      processing: false,
    );
    state = list;
  }

  /// Swaps the page currently holding [oldPath] to [newPath] — used by the
  /// BACKGROUND auto-crop: keyed by path (not index) so reorder/delete while
  /// a page is still processing can never swap the wrong page. No-op if the
  /// page was deleted meanwhile. Always clears the processing badge.
  void replacePath(String oldPath, String newPath) {
    final index = state.indexWhere((p) => p.imagePath == oldPath);
    if (index < 0) return;
    replaceAt(index, newPath);
  }

  /// Marks/unmarks the page holding [path] as background-processing (Phase 2
  /// queue). No-op if the page was deleted meanwhile.
  void setProcessing(String path, bool value) {
    final index = state.indexWhere((p) => p.imagePath == path);
    if (index < 0) return;
    final list = [...state];
    list[index] = list[index].copyWith(processing: value);
    state = list;
  }

  /// True while any page's background crop is still running.
  bool get anyProcessing => state.any((p) => p.processing);

  void setFilter(int index, String filter) {
    final list = [...state];
    list[index] = list[index].copyWith(filter: filter);
    state = list;
  }

  void rotate(int index) {
    final list = [...state];
    list[index] =
        list[index].copyWith(rotation: (list[index].rotation + 90) % 360);
    state = list;
  }

  /// Resets a page to its original uncropped, unfiltered capture.
  void revertToOriginal(int index) {
    final list = [...state];
    list[index] = list[index].copyWith(
      filter: 'original',
      rotation: 0,
      clearCrop: true,
    );
    state = list;
  }

  void clear() => state = const [];
}

final scanSessionProvider = NotifierProvider<ScanSessionNotifier, List<ScanPage>>(
  ScanSessionNotifier.new,
);

/// Whether the active session was started in batch (multi-page) mode —
/// governs the default watermark resolution at save time (spec §2: batch
/// default ON, single default OFF). Set by the scan entry point.
class ScanIsBatchNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final scanIsBatchProvider =
    NotifierProvider<ScanIsBatchNotifier, bool>(ScanIsBatchNotifier.new);
