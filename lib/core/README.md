# core

Shared code every feature module depends on — nothing in `core/` depends on `features/`.

| Folder | Responsibility | Phase |
|---|---|---|
| `database/` | drift schema + `AppDatabase` + `databaseProvider` — local-first source of truth. See `docs/DATABASE.md`. | 0 (local tables), 2 (sync fields activate) |
| `theme/` | Material 3 theme, shared light/dark seed color. | 0 |
| `l10n/` | ARB source strings (`app_en.arb`, `app_ne.arb`); `flutter gen-l10n` (config: `l10n.yaml` at repo root) generates `AppLocalizations` here. | 0 |
| `router/` | Not yet created — added in Phase 1 once there's more than one screen to navigate between. Package choice is a Stop-Condition decision (not silently added). | 1 |

See `docs/ARCHITECTURE.md` for the full module map and data-flow diagram.
