import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/database/database.dart';
import '../../core/database/database_provider.dart';
import '../../core/l10n/app_localizations.dart';
import '../onboarding/onboarding_flow.dart';
import 'providers/settings_provider.dart';
import 'system_status_section.dart';

/// Phase 1 scope: theme, language, scan defaults, storage mode (read-only,
/// fixed to Local until Phase 2 ships connectors). Security section
/// (app lock/biometric/secure folder) lands in Phase 3.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settingsAsync = ref.watch(userSettingsProvider);
    final repo = ref.read(userSettingsRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('$error')),
        data: (settings) => ListView(
          children: [
            _SectionHeader(l10n.settingsAppearance),
            ListTile(
              title: Text(l10n.settingsTheme),
              trailing: DropdownButton<String>(
                value: settings.theme,
                items: [
                  DropdownMenuItem(
                    value: 'system',
                    child: Text(l10n.settingsThemeSystem),
                  ),
                  DropdownMenuItem(
                    value: 'light',
                    child: Text(l10n.settingsThemeLight),
                  ),
                  DropdownMenuItem(
                    value: 'dark',
                    child: Text(l10n.settingsThemeDark),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) repo.setTheme(value);
                },
              ),
            ),
            ListTile(
              title: Text(l10n.settingsLanguage),
              trailing: SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'en',
                    label: Text(l10n.languageNameEnglish),
                  ),
                  ButtonSegment(
                    value: 'ne',
                    label: Text(l10n.languageNameNepali),
                  ),
                ],
                selected: {settings.language},
                onSelectionChanged: (selection) =>
                    repo.setLanguage(selection.first),
              ),
            ),
            ListTile(
              title: Text(l10n.settingsCalendar),
              trailing: SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'ad',
                    label: Text(l10n.settingsCalendarAd),
                  ),
                  ButtonSegment(
                    value: 'bs',
                    label: Text(l10n.settingsCalendarBs),
                  ),
                ],
                selected: {settings.calendar},
                onSelectionChanged: (selection) => repo.update(
                  UserSettingsCompanion(calendar: Value(selection.first)),
                ),
              ),
            ),
            const Divider(),
            _SectionHeader(l10n.settingsScanDefaults),
            ListTile(
              title: Text(l10n.settingsDefaultQuality),
              trailing: DropdownButton<String>(
                value: settings.defaultQuality,
                items: [
                  DropdownMenuItem(
                    value: 'low',
                    child: Text(l10n.settingsQualityLow),
                  ),
                  DropdownMenuItem(
                    value: 'medium',
                    child: Text(l10n.settingsQualityMedium),
                  ),
                  DropdownMenuItem(
                    value: 'high',
                    child: Text(l10n.settingsQualityHigh),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    repo.update(
                      UserSettingsCompanion(defaultQuality: Value(value)),
                    );
                  }
                },
              ),
            ),
            ListTile(
              title: Text(l10n.settingsDefaultColorMode),
              trailing: DropdownButton<String>(
                value: settings.defaultColorMode,
                items: [
                  DropdownMenuItem(
                    value: 'original',
                    child: Text(l10n.scanFilterOriginal),
                  ),
                  DropdownMenuItem(
                    value: 'grayscale',
                    child: Text(l10n.scanFilterGrayscale),
                  ),
                  DropdownMenuItem(
                    value: 'bw',
                    child: Text(l10n.scanFilterBw),
                  ),
                  DropdownMenuItem(
                    value: 'lighten',
                    child: Text(l10n.scanFilterLighten),
                  ),
                  DropdownMenuItem(
                    value: 'enhance',
                    child: Text(l10n.scanFilterEnhance),
                  ),
                  DropdownMenuItem(
                    value: 'high_contrast',
                    child: Text(l10n.scanFilterHighContrast),
                  ),
                  DropdownMenuItem(
                    value: 'warm',
                    child: Text(l10n.scanFilterWarm),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    repo.update(
                      UserSettingsCompanion(defaultColorMode: Value(value)),
                    );
                  }
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.branding_watermark_outlined),
              title: Text(l10n.settingsWatermarkBatch),
              trailing: IconButton(
                icon: const Icon(Icons.info_outline),
                tooltip: l10n.moreInfo,
                onPressed: () => _showInfoDialog(
                  context,
                  l10n.settingsWatermarkInfoTitle,
                  l10n.settingsWatermarkInfoBody,
                ),
              ),
            ),
            ListTile(
              title: Text(l10n.settingsWatermarkPosition),
              trailing: DropdownButton<String>(
                value: settings.watermarkPosition,
                items: [
                  DropdownMenuItem(
                    value: 'bottom_right',
                    child: Text(l10n.settingsWatermarkPosBottomRight),
                  ),
                  DropdownMenuItem(
                    value: 'top_right',
                    child: Text(l10n.settingsWatermarkPosTopRight),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    repo.update(
                      UserSettingsCompanion(watermarkPosition: Value(value)),
                    );
                  }
                },
              ),
            ),
            const Divider(),
            _SectionHeader(l10n.settingsStorage),
            ListTile(
              leading: const Icon(Icons.smartphone),
              title: Text(l10n.settingsStorageLocal),
              trailing: IconButton(
                icon: const Icon(Icons.info_outline),
                tooltip: l10n.moreInfo,
                onPressed: () => _showInfoDialog(
                  context,
                  l10n.settingsStorageInfoTitle,
                  l10n.settingsStorageInfoBody,
                ),
              ),
            ),
            const Divider(),
            const SystemStatusSection(),
            const Divider(),
            _SectionHeader(l10n.settingsAbout),
            ListTile(
              title: Text(l10n.appTitle),
              subtitle: Text(l10n.settingsAboutBody),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _openUrl(context, 'https://dokodocs.com'),
            ),
            ListTile(
              leading: const Icon(Icons.language_outlined),
              title: Text(l10n.settingsVisitWebsite),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _openUrl(context, 'https://dokodocs.com'),
            ),
            ListTile(
              leading: const Icon(Icons.replay_outlined),
              title: Text(l10n.settingsReplayIntro),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => OnboardingFlow(
                    onFinished: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ),
            const Divider(),
            _SectionHeader(l10n.settingsLegal),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(l10n.settingsPrivacyPolicy),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _openUrl(context, 'https://dokodocs.com/privacy'),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(l10n.settingsTerms),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _openUrl(context, 'https://dokodocs.com/terms'),
            ),
            const Divider(),
            _SectionHeader(l10n.settingsConnect),
            for (final site in _socialSites)
              ListTile(
                leading: Icon(site.icon),
                title: Text(site.label),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: () => _openUrl(context, site.url),
              ),
            const SizedBox(height: 24),
            _MadeInNepal(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Shows a simple titled info dialog — used by the (i) buttons that reveal
/// details on demand instead of crowding the row with a long subtitle.
Future<void> _showInfoDialog(
  BuildContext context,
  String title,
  String body,
) {
  final l10n = AppLocalizations.of(context);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.dialogClose),
        ),
      ],
    ),
  );
}

/// Opens [url] in an external browser, surfacing a snackbar if it can't be
/// launched (no browser, offline before the page loads, etc.).
Future<void> _openUrl(BuildContext context, String url) async {
  final uri = Uri.parse(url);
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(url)));
  }
}

/// The DokoDocs social presence (launch kit handles). Labels are brand names,
/// so they're intentionally not localized.
class _SocialSite {
  const _SocialSite(this.label, this.url, this.icon);
  final String label;
  final String url;
  final IconData icon;
}

const _socialSites = <_SocialSite>[
  _SocialSite('GitHub', 'https://github.com/dokodocs/app', Icons.code),
  _SocialSite('Instagram', 'https://instagram.com/dokodocs', Icons.camera_alt_outlined),
  _SocialSite('X (Twitter)', 'https://x.com/dokodocs', Icons.alternate_email),
  _SocialSite('TikTok', 'https://tiktok.com/@dokodocs', Icons.music_note_outlined),
  _SocialSite('YouTube', 'https://youtube.com/@dokodocs', Icons.smart_display_outlined),
  _SocialSite('Facebook', 'https://facebook.com/dokodocs', Icons.facebook),
  _SocialSite('LinkedIn', 'https://linkedin.com/company/dokodocs', Icons.business_outlined),
];

/// "Made with ❤ in Nepal 🇳🇵" — a small credit in the About section.
class _MadeInNepal extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.settingsMadeWith, style: muted),
          const SizedBox(width: 4),
          const Icon(Icons.favorite, size: 14, color: Color(0xFFC1533F)),
          const SizedBox(width: 4),
          Text(l10n.settingsInNepal, style: muted),
          const SizedBox(width: 4),
          const Text('🇳🇵', style: TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
