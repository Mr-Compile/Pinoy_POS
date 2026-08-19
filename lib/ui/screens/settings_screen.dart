import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/ui/screens/ai_config_screen.dart';
import 'package:pinoy_pos/ui/screens/backup_restore_screen.dart';
import 'package:pinoy_pos/ui/screens/profile_screen.dart';
import 'package:pinoy_pos/ui/screens/settings/appearance_settings_page.dart';
import 'package:pinoy_pos/ui/screens/settings/pin_settings_page.dart';
import 'package:pinoy_pos/ui/screens/settings/security_settings_page.dart';
import 'package:pinoy_pos/ui/screens/settings/store_information_settings_page.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';

/// Settings hub — a container screen that links to all user-accessible
/// configuration sub-pages.
///
/// Role-based visibility:
///   - Profile:        all roles
///   - Security:       all roles
///   - PIN:            all roles
///   - Appearance:     all roles
///   - Store Info:     Owner only (edit_settings without backup_restore)
///   - Backup & Restore: Admin only (backup_restore)
///   - AI Config:      Admin only (manage_ai_config)
///
/// This screen does NOT contain any settings logic itself — each
/// sub-page owns its own state and persistence.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authNotifier = ref.read(authStateProvider.notifier);

    // Role checks
    final canEditBusiness = authNotifier.hasPermission('edit_settings') &&
        !authNotifier.hasPermission('backup_restore');
    final canBackup = authNotifier.hasPermission('backup_restore');
    final canManageAi = authNotifier.hasPermission('manage_ai_config');

    final entries = <_SettingsEntry>[];

    // ── Personal (all roles) ──
    entries.add(_SettingsEntry(
      icon: Icons.person_outline,
      title: 'Profile',
      subtitle: 'View and edit your profile information',
      screen: const ProfileScreen(),
    ));
    entries.add(_SettingsEntry(
      icon: Icons.lock_outline,
      title: 'Security',
      subtitle: 'Change your password',
      screen: const SecuritySettingsPage(),
    ));
    entries.add(_SettingsEntry(
      icon: Icons.pin_outlined,
      title: 'PIN',
      subtitle: 'Manage your login PIN',
      screen: const PinSettingsPage(),
    ));
    entries.add(_SettingsEntry(
      icon: Icons.palette_outlined,
      title: 'Appearance',
      subtitle: 'Theme mode and display preferences',
      screen: const AppearanceSettingsPage(),
    ));

    // ── Business (Owner only) ──
    if (canEditBusiness) {
      entries.add(_SettingsEntry(
        icon: Icons.store_outlined,
        title: 'Store Information',
        subtitle: 'Store name, address, contact, receipt footer, currency',
        screen: const StoreInformationSettingsPage(),
      ));
    }

    // ── System (Admin only) ──
    if (canBackup) {
      entries.add(_SettingsEntry(
        icon: Icons.backup_outlined,
        title: 'Backup & Restore',
        subtitle: 'Create, restore, and manage database backups',
        screen: const BackupRestoreScreen(),
      ));
    }
    if (canManageAi) {
      entries.add(_SettingsEntry(
        icon: Icons.smart_toy_outlined,
        title: 'AI Configuration',
        subtitle: 'Configure Groq API key and model',
        screen: const AIConfigScreen(),
      ));
    }

    return Scaffold(
      appBar: const AppHeader(title: 'Settings'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (canEditBusiness) _SectionLabel(label: 'Personal'),
          AppCard(
            child: Column(
              children: entries
                  .map((entry) => _SettingsTile(entry: entry))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}

class _SettingsEntry {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget screen;

  const _SettingsEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.screen,
  });
}

class _SettingsTile extends StatelessWidget {
  final _SettingsEntry entry;

  const _SettingsTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(entry.icon, color: Theme.of(context).colorScheme.primary),
      title: Text(entry.title),
      subtitle: Text(
        entry.subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => entry.screen),
      ),
    );
  }
}
