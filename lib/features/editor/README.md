# editor

**Status:** implemented (Phase 1 Stage A) — reorder/delete pages, re-combine to PDF, share, open in viewer. Full annotation suite still **Phase 3**.

## Responsibility
Spec §4 screen 6, Document Editor: reorder pages, add/remove pages, merge/split, watermark, annotate (draw/highlight/underline/strikethrough/sticky note/text/erase/shapes/images), signature/stamp placement, export.

- **Phase 1 scope only:** reorder pages, combine pages → PDF, export PDF/images.
- **Phase 3 adds:** full annotation suite, watermark, signature/stamp placement (reads from `core/database` `Signatures`/`Stamps` tables, already in the Phase 0 schema — see `docs/DATABASE.md`).

## Key packages
- `pdf` (Phase 1, via `core/pdf/pdf_builder.dart`) — combine-to-PDF
- Phase 3 adds: an annotate/merge/split/watermark package — open-source pick, avoiding Syncfusion per the Nepal overrides

## Contents
- `editor_screen.dart` — `ReorderableGridView` of pages, delete, re-generate PDF, share, view
