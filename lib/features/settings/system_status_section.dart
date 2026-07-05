import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/l10n/app_localizations.dart';

/// A "Device status" checklist in Settings: shows, at a glance, whether the
/// device capabilities DokoDocs relies on are available — camera permission,
/// the document scanner, and local storage. The scanner is the app's OWN
/// OpenCV engine, so it is always available (no Google Play services / ML Kit
/// dependency).
class SystemStatusSection extends StatefulWidget {
  const SystemStatusSection({super.key});

  @override
  State<SystemStatusSection> createState() => _SystemStatusSectionState();
}

enum _Status { ok, warn, unknown }

class _SystemStatusSectionState extends State<SystemStatusSection> {
  _Status _camera = _Status.unknown;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    _Status result;
    try {
      final cam = await Permission.camera.status;
      result = cam.isGranted ? _Status.ok : _Status.warn;
    } catch (_) {
      // The permission plugin is unavailable (e.g. in a widget test with no
      // platform channel) — degrade to "unknown" rather than crashing.
      result = _Status.unknown;
    }
    if (!mounted) return;
    setState(() => _camera = result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.settingsSystemStatus,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: l10n.statusRefresh,
                onPressed: _refresh,
              ),
            ],
          ),
        ),
        _statusTile(
          icon: Icons.photo_camera_outlined,
          title: l10n.statusCamera,
          status: _camera,
          onTap: _camera == _Status.ok
              ? null
              : () async {
                  await Permission.camera.request();
                  await _refresh();
                },
        ),
        // The document scanner is the built-in OpenCV engine — always
        // available, no Play services / ML Kit dependency.
        _statusTile(
          icon: Icons.document_scanner_outlined,
          title: l10n.statusDocumentScanner,
          subtitle: l10n.statusDocumentScannerBody,
          status: _Status.ok,
        ),
        // Local storage is always available on a supported device.
        _statusTile(
          icon: Icons.sd_storage_outlined,
          title: l10n.statusLocalStorage,
          status: _Status.ok,
        ),
      ],
    );
  }

  Widget _statusTile({
    required IconData icon,
    required String title,
    required _Status status,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    final l10n = AppLocalizations.of(context);
    final (badge, label, color) = switch (status) {
      _Status.ok => (Icons.check_circle, l10n.statusAvailable, Colors.green),
      _Status.warn => (
          Icons.error_outline,
          onTap != null ? l10n.statusPermissionNeeded : l10n.statusScannerFail,
          Colors.orange,
        ),
      _Status.unknown => (Icons.help_outline, l10n.statusUnknown, Colors.grey),
    };
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle == null ? label : '$subtitle\n$label'),
      isThreeLine: subtitle != null,
      onTap: onTap,
      trailing: Icon(badge, color: color),
    );
  }
}
