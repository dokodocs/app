# folders

**Status:** implemented (Stage B). Dedicated folder management tab — Home's inline folder-chip filter (Stage A) remains as the fast path for casual filtering.

## Responsibility
List/create/rename(-pending)/delete folders; tap a folder to view its documents. Backed by the same `Folder`/`Document` tables and repositories as Home.

## Contents
- `folders_screen.dart` — folder list, create dialog, `EmptyState` (`homeFoldersEmptyTitle`/`Body`) when none exist
- `folder_documents_screen.dart` — documents grid scoped to one folder, reuses `home`'s `DocumentTile`
