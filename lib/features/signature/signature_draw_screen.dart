import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:signature/signature.dart';

import '../../core/database/database_provider.dart';
import '../../core/l10n/app_localizations.dart';

/// A draw-pad screen for capturing a new signature. Saves it as a transparent
/// PNG under the app's `signatures/` directory and records a row. Pops `true`
/// when a signature was saved.
class SignatureDrawScreen extends ConsumerStatefulWidget {
  const SignatureDrawScreen({super.key});

  @override
  ConsumerState<SignatureDrawScreen> createState() =>
      _SignatureDrawScreenState();
}

class _SignatureDrawScreenState extends ConsumerState<SignatureDrawScreen> {
  late final SignatureController _controller = SignatureController(
    penStrokeWidth: 3,
    penColor: const Color(0xFF1F2937),
    exportBackgroundColor: const Color(0x00000000), // transparent
  );
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    if (_controller.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.signatureEmptyPad)));
      return;
    }
    setState(() => _saving = true);
    try {
      final bytes = await _controller.toPngBytes();
      if (bytes == null) return;
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(appDir.path, 'signatures'));
      await dir.create(recursive: true);
      final path = p.join(
        dir.path,
        'sig_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await File(path).writeAsBytes(bytes);
      await ref.read(signaturesRepositoryProvider).add(path);
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.signatureNew),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: l10n.signatureClear,
            onPressed: () => _controller.clear(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_saving) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(l10n.signatureDrawHint),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFF9CCC8E), width: 1.5),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: Signature(
                controller: _controller,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _controller.clear(),
                      icon: const Icon(Icons.clear),
                      label: Text(l10n.signatureClear),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.check),
                      label: Text(l10n.dialogSave),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
