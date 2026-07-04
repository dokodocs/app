import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/folders/folders_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/scan/scan_capture.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/tools/tools_screen.dart';
import '../l10n/app_localizations.dart';

/// Persistent bottom-nav shell: Home / Folders / [center Scan FAB] / Tools
/// / Settings. Each tab keeps its own navigation stack (a nested
/// `Navigator` per tab inside an `IndexedStack`, so switching tabs doesn't
/// lose where you were). No router package added for this — `IndexedStack`
/// + per-tab `Navigator` satisfies "each destination preserves its own
/// stack" without a new dependency (see docs/DEPENDENCIES.md).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  final _navigatorKeys = List.generate(4, (_) => GlobalKey<NavigatorState>());

  static const _tabBuilders = <WidgetBuilder>[
    _buildHome,
    _buildFolders,
    _buildTools,
    _buildSettings,
  ];

  static Widget _buildHome(BuildContext context) => const HomeScreen();
  static Widget _buildFolders(BuildContext context) => const FoldersScreen();
  static Widget _buildTools(BuildContext context) => const ToolsScreen();
  static Widget _buildSettings(BuildContext context) => const SettingsScreen();

  void _selectTab(int index) {
    if (index == _index) {
      _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
    } else {
      setState(() => _index = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          for (var i = 0; i < _tabBuilders.length; i++)
            Navigator(
              key: _navigatorKeys[i],
              onGenerateRoute: (settings) =>
                  MaterialPageRoute(builder: _tabBuilders[i]),
            ),
        ],
      ),
      floatingActionButton: Semantics(
        label: l10n.navScan,
        child: FloatingActionButton(
          onPressed: () => startScanFlow(context, ref),
          child: const Icon(Icons.document_scanner_outlined),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                _NavItem(
                  icon: Icons.home_outlined,
                  selectedIcon: Icons.home,
                  label: l10n.navHome,
                  selected: _index == 0,
                  onTap: () => _selectTab(0),
                ),
                _NavItem(
                  icon: Icons.folder_outlined,
                  selectedIcon: Icons.folder,
                  label: l10n.navFolders,
                  selected: _index == 1,
                  onTap: () => _selectTab(1),
                ),
              ],
            ),
            Row(
              children: [
                _NavItem(
                  icon: Icons.build_outlined,
                  selectedIcon: Icons.build,
                  label: l10n.navTools,
                  selected: _index == 2,
                  onTap: () => _selectTab(2),
                ),
                _NavItem(
                  icon: Icons.settings_outlined,
                  selectedIcon: Icons.settings,
                  label: l10n.navSettings,
                  selected: _index == 3,
                  onTap: () => _selectTab(3),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 64, minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(selected ? selectedIcon : icon, color: color),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
