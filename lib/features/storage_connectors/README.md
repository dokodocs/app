# storage_connectors

**Status:** not yet implemented. Lands in **Phase 2**.

## Responsibility
Spec §4 screen 10: one setup screen per connector type — Google Drive OAuth, OneDrive OAuth, Dropbox OAuth, WebDAV/FTP form, LAN server discovery/pairing, custom API endpoint form — each with a "Test Connection" action. Writes the chosen connector into `UserSettings.storageMode`/`server*` fields (already in the Phase 0 schema).

## Key decision — flagged, not yet made
Backend language for the self-hosted reference backend these connectors talk to: Node.js/NestJS vs Go. See `docs/ROADMAP.md` Step 3.

## Key packages (planned)
- `dio`, a WebDAV client, `googleapis` (Drive), Microsoft Graph REST (OneDrive), Dropbox REST, an FTP/SFTP client, a custom mDNS LAN-discovery module

## Contents (planned)
- One `*_setup_screen.dart` per connector, `providers/storage_connector_provider.dart`, `data/connectors/` (one repository per connector implementing a shared interface).
