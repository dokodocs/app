# pdf_viewer

**Status:** implemented (Phase 1 Stage A) — basic viewer. Page-thumbnail sidebar and inline annotate/sign land in **Phase 3**.

## Responsibility
Spec §4 screen 7: view a PDF; Phase 3 adds a page-thumbnail sidebar and inline annotate/sign.

## Key packages
- `pdfrx` — picked over `syncfusion_flutter_pdfviewer` (open-source, avoids the Syncfusion community-license question — see `docs/DEPENDENCIES.md`)

## Contents
- `pdf_viewer_screen.dart` — `PdfViewer.file(path)`
