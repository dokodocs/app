# Architecture

## Module boundaries

```
lib/
  main.dart                 # app entry point, ProviderScope + MaterialApp.router
  core/
    database/                # drift schema + AppDatabase (local-first source of truth)
    theme/                   # Material 3 (Android) + Cupertino-appropriate (iOS) shared theme
    router/                  # go_router route table, one entry per feature
    l10n/                    # ARB source strings (en, ne) — see l10n.yaml at repo root
  features/
    onboarding/               # Phase 0/1 — splash, local-first explainer
    home/                     # Phase 1 — grid/list, folders, tags, favorites, search
    auth/                     # Phase 1 — Google/Apple/Email/Phone-OTP/Guest
    scan/                     # Phase 1 — camera, edge detect, crop, filters, multi-page tray
    editor/                   # Phase 1 (basic) / Phase 3 (full) — reorder, merge/split, annotate, sign
    pdf_viewer/                # Phase 1 — view; Phase 3 — annotate/sign inline
    settings/                 # Phase 1 — account, storage, security, scan defaults, printer, about
    storage_connectors/        # Phase 2 — one screen per connector type + Test Connection
    secure_folder/             # Phase 3 — biometric-gated hidden documents
    qr/                        # Phase 3 — QR scan/generate
    trash/                     # Phase 3 — restore / permanently delete
test/                          # unit + widget tests, mirrors lib/ structure
```

Each `features/<module>/` directory owns its own widgets, providers, and (once relevant) a `data/` subfolder for repositories that talk to `core/database`. Modules do not import each other's internals — cross-feature navigation goes through `core/router`, and cross-feature data access goes through `core/database` repositories, never through another feature's provider directly.

Every module folder carries a `README.md` stating its responsibility, target phase, and key packages, kept up to date as the module is built — see each folder for specifics.

## Data flow (Phase 0/1 — local only)

```
UI widget (feature) → Riverpod provider (feature) → drift DAO (core/database) → SQLite (device disk)
```

No network calls exist until Phase 2. `UserSettings.storageMode` defaults to `local`; every other mode (Phase 2+) is additive — the local path always keeps working.

## Sync engine design (Phase 2+, not yet implemented)

Placeholder for when Phase 2 lands: a `SyncStatus` field already exists on `Document` (`none|pending|synced|failed|conflict`) so the UI and schema are ready before the sync engine itself is built. The engine will be a background isolate that walks documents with `syncStatus != synced`, pushes/pulls via the active storage connector, and applies last-write-wins with a visible conflict marker (full merge UI deferred past Phase 2).

## State management

Riverpod (`flutter_riverpod` + `riverpod_annotation`/`riverpod_generator`, code-gen style). One provider file per feature, colocated with that feature's widgets.

## Persistence

`drift` over SQLite (via `drift_flutter`'s `driftDatabase()` helper), chosen over raw `sqflite` for compile-time-safe queries and a real migration story as the schema grows across phases (spec §2.1).

## i18n

`flutter gen-l10n` generates `AppLocalizations` from `lib/core/l10n/app_en.arb` and `app_ne.arb` (configured via `l10n.yaml`). Every user-facing string goes through localization from the first widget — Nepal override, not deferred to Phase 4.
