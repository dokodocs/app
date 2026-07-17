import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/database/database.dart';
import '../../core/database/database_provider.dart';
import '../../core/l10n/app_localizations.dart';

/// Local-only profile: picture, name, email, mobile number. No account/auth
/// semantics — this is display info the user chooses to keep on-device,
/// stored in the single-row `UserProfile` table (same pattern as
/// `UserSettings`).
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _mobileController = TextEditingController();

  String? _avatarPath;
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _mobileController.dispose();
    super.dispose();
  }

  void _initFromProfile(UserProfileData profile) {
    if (_initialized) return;
    _initialized = true;
    _nameController.text = profile.name;
    _emailController.text = profile.email;
    _mobileController.text = profile.mobileNumber;
    _avatarPath = profile.avatarPath;
  }

  Future<void> _pickAvatar() async {
    final l10n = AppLocalizations.of(context);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.profilePickFromGallery),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l10n.profileTakePhoto),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            if (_avatarPath != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(l10n.profileRemovePicture),
                onTap: () => Navigator.of(sheetContext).pop(),
              ),
          ],
        ),
      ),
    );

    if (source == null) {
      if (_avatarPath != null && mounted) {
        setState(() => _avatarPath = null);
      }
      return;
    }

    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null) return;

    final appDir = await getApplicationDocumentsDirectory();
    final avatarDir = Directory(p.join(appDir.path, 'profile'));
    await avatarDir.create(recursive: true);
    final destPath = p.join(
      avatarDir.path,
      'avatar_${DateTime.now().millisecondsSinceEpoch}${p.extension(picked.path)}',
    );
    await File(picked.path).copy(destPath);

    if (!mounted) return;
    setState(() => _avatarPath = destPath);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final repo = ref.read(userProfileRepositoryProvider);
    await repo.update(
      UserProfileCompanion(
        name: Value(_nameController.text.trim()),
        email: Value(_emailController.text.trim()),
        mobileNumber: Value(_mobileController.text.trim()),
        avatarPath: Value(_avatarPath),
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.profileSaved)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profileAsync = ref.watch(userProfileProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileTitle)),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('$error')),
        data: (profile) {
          _initFromProfile(profile);
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Center(
                  child: GestureDetector(
                    onTap: _pickAvatar,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 56,
                          backgroundImage: _avatarPath != null
                              ? FileImage(File(_avatarPath!))
                              : null,
                          child: _avatarPath == null
                              ? const Icon(Icons.person, size: 56)
                              : null,
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Tooltip(
                            message: l10n.profileChangePicture,
                            child: CircleAvatar(
                              radius: 18,
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              child: Icon(
                                Icons.camera_alt,
                                size: 18,
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: l10n.profileName,
                    prefixIcon: const Icon(Icons.person_outline),
                    border: const OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: l10n.profileEmail,
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    final ok = RegExp(
                      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                    ).hasMatch(value.trim());
                    return ok ? null : l10n.profileEmailInvalid;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _mobileController,
                  decoration: InputDecoration(
                    labelText: l10n.profileMobileNumber,
                    prefixIcon: const Icon(Icons.phone_outlined),
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.profileSave),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
