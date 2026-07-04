import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/l10n/app_localizations.dart';

/// Explains WHY camera access is needed BEFORE the OS dialog appears (spec
/// requirement). Denied/permanently-denied paths offer a retry / "Open
/// settings" action but never dead-end — onboarding always completes even
/// if camera access is withheld here; `scan_capture.dart` re-prompts the
/// next time the user actually taps Scan.
class PermissionPrimingScreen extends StatefulWidget {
  const PermissionPrimingScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<PermissionPrimingScreen> createState() =>
      _PermissionPrimingScreenState();
}

class _PermissionPrimingScreenState extends State<PermissionPrimingScreen> {
  PermissionStatus? _status;
  bool _requesting = false;

  Future<void> _continue() async {
    setState(() => _requesting = true);
    final status = await Permission.camera.request();
    if (!mounted) return;
    setState(() {
      _status = status;
      _requesting = false;
    });
    if (status.isGranted) {
      widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final denied = _status != null && !_status!.isGranted;
    final permanentlyDenied = _status?.isPermanentlyDenied ?? false;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.camera_alt_outlined,
                size: 72,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 28),
              Text(
                l10n.onboardingPermissionPrimingTitle,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.onboardingPermissionPrimingBody,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (!denied)
                FilledButton(
                  onPressed: _requesting ? null : _continue,
                  child: Text(l10n.onboardingContinue),
                )
              else ...[
                FilledButton(
                  onPressed: permanentlyDenied ? openAppSettings : _continue,
                  child: Text(
                    permanentlyDenied
                        ? l10n.scanOpenSettings
                        : l10n.scanTryAgain,
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: widget.onDone,
                  child: Text(l10n.onboardingStartScanning),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
