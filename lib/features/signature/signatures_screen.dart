import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/database/database.dart';
import '../../core/database/database_provider.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/widgets/empty_state.dart';
import 'signature_draw_screen.dart';
import 'signature_import_screen.dart';

/// Manages saved signatures, and doubles as a picker. When [picking] is true,
/// tapping a signature pops it back to the caller (used by the editor to
/// choose which signature to place). Otherwise it's a plain manage screen.
class SignaturesScreen extends ConsumerWidget {
  const SignaturesScreen({super.key, this.picking = false});

  final bool picking;

  Future<void> _addSignature(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.draw_outlined),
              title: Text(l10n.signatureDraw),
              subtitle: Text(l10n.signatureDrawHint),
              onTap: () => Navigator.of(sheetContext).pop('draw'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.signatureImportGallery),
              onTap: () => Navigator.of(sheetContext).pop('gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l10n.signatureImportCamera),
              onTap: () => Navigator.of(sheetContext).pop('camera'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;

    if (choice == 'draw') {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SignatureDrawScreen()),
      );
      return;
    }

    final picked = await ImagePicker().pickImage(
      source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (picked == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SignatureImportScreen(sourcePath: picked.path),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final signaturesAsync = ref.watch(signaturesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.signatureTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addSignature(context),
        icon: const Icon(Icons.add),
        label: Text(l10n.signatureNew),
      ),
      body: signaturesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (signatures) {
          if (signatures.isEmpty) {
            return EmptyState(
              icon: Icons.draw_outlined,
              title: l10n.signatureNone,
              body: l10n.signatureDrawHint,
              primaryActionLabel: l10n.signatureNew,
              onPrimaryAction: () => _addSignature(context),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: signatures.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final signature = signatures[index];
              return ListTile(
                leading: Container(
                  width: 72,
                  height: 40,
                  color: Colors.white,
                  child: Image.file(File(signature.imagePath), fit: BoxFit.contain),
                ),
                title: Text('#${signature.id}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDelete(context, ref, signature),
                ),
                onTap: picking
                    ? () => Navigator.of(context).pop(signature)
                    : null,
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Signature signature,
  ) async {
    final l10n = AppLocalizations.of(context);
    await ref.read(signaturesRepositoryProvider).delete(signature);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.signatureDeleted)));
    }
  }
}
