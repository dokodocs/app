# home

**Status:** implemented (Phase 1 Stage A) — real grid, folders, search. Verified live on the `dokodocs_test` emulator. List-view toggle, tags, archive, and trash entry point still to come (grid + favorite/trash actions exist; list toggle and archive/trash *screens* are Phase 3).

## Responsibility
The app's landing screen: grid of scanned documents, folder chips (create/filter), filename search, favorite/trash actions per document, scan FAB. Spec §4 screen 3. OCR-content search lands in Phase 4.

## Key packages
- `flutter_riverpod` — state (document/folder list providers)
- `core/database` — reads via repository classes, no direct SQL here

## Contents
- `home_screen.dart` — search bar, folder chips + "New folder", document grid, empty state (upgraded to the full reusable `EmptyState` in Stage B), scan FAB
- `widgets/document_tile.dart` — grid tile: thumbnail, title, page count/date, favorite/trash popup menu

See `docs/ARCHITECTURE.md` for how this module talks to `core/database` and `core/navigation`.
