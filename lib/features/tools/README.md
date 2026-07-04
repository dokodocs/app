# tools

**Status:** implemented (Stage B) — a small grid of Phase-1-appropriate utilities. Not in the original spec §4 screen list; added by the "First-Launch Journey" bottom-nav prompt. Future tiles are simply not rendered until their feature ships, rather than shown-and-disabled.

## Responsibility
Entry points into the scan/import pipeline built in `features/scan`: "Combine to PDF" (camera capture) and "Import images → PDF" (gallery). Both currently route into the same underlying scan-review → save pipeline — no separate "merge existing documents" feature exists yet (that's Phase 3 merge/split territory).

## Contents
- `tools_screen.dart` — 2-tile grid
