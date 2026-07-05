import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:permission_handler/permission_handler.dart';

import '../../core/l10n/app_localizations.dart';
import '../scan/scanner_diagnostics.dart';

/// A "Device status" checklist in Settings: shows, at a glance, whether the
/// device capabilities DokoDocs relies on are actually available here —
/// camera permission, the Google Play services document scanner, and local
/// storage. Directly answers the recurring "camera won't open / is the
/// scanner installed?" question by making the state visible and testable.
class SystemStatusSection extends StatefulWidget {
  const SystemStatusSection({super.key});

  @override
  State<SystemStatusSection> createState() => _SystemStatusSectionState();
}

enum _Status { ok, warn, unknown }

class _SystemStatusSectionState extends State<SystemStatusSection> {
  _Status _camera = _Status.unknown;
  _Status _scanner = _Status.unknown;
  bool _testingScanner = false;

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
      // platform channel, or a misbehaving host) — degrade to "unknown"
      // rather than letting the async exception crash the Settings screen.
      result = _Status.unknown;
    }
    if (!mounted) return;
    setState(() => _camera = result);
  }

  Future<void> _testScanner() async {
    setState(() => _testingScanner = true);
    var ok = false;
    try {
      // A cancelled scan still proves the scanner launched — any non-throw is
      // success. A missing/outdated Play services throws instead.
      await CunningDocumentScanner.getPictures(
        scannerSource: ScannerSource.camera,
        noOfPages: 1,
      );
      ok = true;
      ScannerDiagnostics.recordNativeSuccess();
    } catch (error) {
      ok = false;
      // Record the real reason so it's visible below, not swallowed.
      ScannerDiagnostics.recordNativeError(error);
    }
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _scanner = ok ? _Status.ok : _Status.warn;
      _testingScanner = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? l10n.statusScannerOk : l10n.statusScannerFail)),
    );
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
        _statusTile(
          icon: Icons.document_scanner_outlined,
          title: l10n.statusDocumentScanner,
          subtitle: l10n.statusDocumentScannerBody,
          status: _scanner,
          trailing: TextButton(
            onPressed: _testingScanner ? null : _testScanner,
            child: _testingScanner
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.statusTest),
          ),
        ),
        // Local storage is always available on a supported device.
        _statusTile(
          icon: Icons.sd_storage_outlined,
          title: l10n.statusLocalStorage,
          status: _Status.ok,
        ),
        // Diagnostics: last scanner path + the ACTUAL native-scanner error
        // (so "why fallback?" is answerable on-device). Long-press to copy.
        if (ScannerDiagnostics.lastPath != null ||
            ScannerDiagnostics.lastNativeError != null)
          _scannerDiagnostics(context),
      ],
    );
  }

  Widget _scannerDiagnostics(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final path = ScannerDiagnostics.lastPath;
    final err = ScannerDiagnostics.lastNativeError;
    final pathLabel = switch (path) {
      ScannerPath.native => 'Native ML Kit / VisionKit',
      ScannerPath.fallback => 'Built-in fallback camera',
      null => 'Not used yet',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Scanner path: $pathLabel',
              style: Theme.of(context).textTheme.bodySmall),
          if (err != null) ...[
            const SizedBox(height: 4),
            Text(
              'Last native scanner error:',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
            const SizedBox(height: 2),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 160),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  err,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: Text(l10n.commonCopy),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: err));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.commonCopied)),
                    );
                  }
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusTile({
    required IconData icon,
    required String title,
    required _Status status,
    String? subtitle,
    Widget? trailing,
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
      trailing: trailing ?? Icon(badge, color: color),
    );
  }
}
