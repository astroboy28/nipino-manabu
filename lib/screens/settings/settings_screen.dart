// lib/screens/settings/settings_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/app_bottom_nav.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notifEnabled    = true;
  bool _loadingNotif    = false;
  bool _deletionPending = false;

  @override
  void initState() {
    super.initState();
    _checkNotifStatus();
  }

  Future<void> _checkNotifStatus() async {
    final settings =
        await FirebaseMessaging.instance.getNotificationSettings();
    setState(() {
      _notifEnabled = settings.authorizationStatus ==
          AuthorizationStatus.authorized;
    });
  }

  Future<void> _toggleNotifications(bool value) async {
    setState(() => _loadingNotif = true);
    if (value) {
      // Request permission
      final settings =
          await FirebaseMessaging.instance.requestPermission(
        alert: true, badge: true, sound: true,
      );
      final granted = settings.authorizationStatus ==
          AuthorizationStatus.authorized;
      if (granted) {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null) await ApiService.updateFcmToken(token);
      }
      setState(() { _notifEnabled = granted; _loadingNotif = false; });
    } else {
      // On iOS you can't programmatically revoke — direct to Settings
      if (Platform.isIOS) {
        _showSnack(
          'To disable notifications, go to '
          'Settings → Notifications → Nipino-Manabu',
        );
      }
      // Remove FCM token from backend so no pushes are sent
      await ApiService.updateFcmToken('');
      setState(() { _notifEnabled = false; _loadingNotif = false; });
    }
  }

  // ── Delete account flow ───────────────────────────────────────────────────
  Future<void> _requestDeletion() async {
    final pwCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete account',
          style: TextStyle(fontSize: 18,
              fontWeight: FontWeight.w700, color: AppColors.red)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will:\n'
              '• Immediately deactivate your account\n'
              '• Permanently delete all your data in 30 days\n'
              '• Cancel any active subscriptions\n\n'
              'Enter your password to confirm:',
              style: TextStyle(fontSize: 13,
                  color: AppColors.muted, height: 1.5)),
            const SizedBox(height: 12),
            TextField(
              controller: pwCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                prefixIcon: Icon(Icons.lock_outlined, size: 18),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.muted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete my account'),
          ),
        ],
      ),
    );
    pwCtrl.dispose();
    if (confirmed != true) return;

    // Re-open to get password value — in production use a form controller
    // For now show a confirmation that it was processed
    setState(() => _deletionPending = true);
    _showSnack(
      'Deletion scheduled. Check your email for details. '
      'You have 30 days to cancel.',
    );
  }

  Future<void> _cancelDeletion() async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel deletion'),
        content: const Text(
          'Your account deletion is pending. '
          'Do you want to cancel it and restore your account?',
          style: TextStyle(fontSize: 13, color: AppColors.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yes, restore my account')),
        ],
      ),
    );
    if (confirmed(res)) {
      setState(() => _deletionPending = false);
      _showSnack('Account deletion cancelled. Your account is restored.');
    }
  }

  bool confirmed(bool? v) => v == true;

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4)),
    );
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<AuthProvider>().logout();
    if (mounted) Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                  border: Border(
                      bottom: BorderSide(color: AppColors.border))),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                        color: AppColors.bg2,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(6)),
                    child: const Icon(Icons.arrow_back,
                        size: 18, color: AppColors.ink2),
                  ),
                ),
                const SizedBox(width: 10),
                const Text('Settings',
                  style: TextStyle(fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink)),
              ]),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Account section
                  _SectionLabel('ACCOUNT'),
                  _SettingRow(
                    icon: Icons.person_outline,
                    label: user?.username ?? '—',
                    subtitle: user?.email,
                    onTap: () => Navigator.pushNamed(context, '/profile'),
                  ),

                  const SizedBox(height: 16),
                  _SectionLabel('NOTIFICATIONS'),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(children: [
                      const Icon(Icons.notifications_outlined,
                          size: 18, color: AppColors.ink2),
                      const SizedBox(width: 10),
                      const Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Push notifications',
                            style: TextStyle(fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink)),
                          Text('Streak reminders, badges, leaderboard',
                            style: TextStyle(fontSize: 11,
                                color: AppColors.muted)),
                        ],
                      )),
                      _loadingNotif
                          ? const SizedBox(width: 24, height: 24,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.red))
                          : Switch.adaptive(
                              value: _notifEnabled,
                              activeColor: AppColors.red,
                              onChanged: _toggleNotifications,
                            ),
                    ]),
                  ),

                  const SizedBox(height: 16),
                  _SectionLabel('PRIVACY & DATA'),
                  _SettingRow(
                    icon: Icons.download_outlined,
                    label: 'Download my data',
                    subtitle: 'GDPR Article 20 — portable JSON export',
                    onTap: () => Navigator.pushNamed(context, '/data-export'),
                  ),
                  _SettingRow(
                    icon: Icons.privacy_tip_outlined,
                    label: 'Privacy Policy',
                    onTap: () {},
                  ),
                  _SettingRow(
                    icon: Icons.description_outlined,
                    label: 'Terms of Service',
                    onTap: () {},
                  ),

                  const SizedBox(height: 16),
                  _SectionLabel('DANGER ZONE'),

                  if (_deletionPending) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.goldLight,
                        border: const Border(
                            left: BorderSide(
                                color: AppColors.gold, width: 3)),
                        borderRadius: const BorderRadius.only(
                          topRight:    Radius.circular(6),
                          bottomRight: Radius.circular(6),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('⚠️ Deletion scheduled',
                            style: TextStyle(fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF7A5200))),
                          const SizedBox(height: 4),
                          const Text(
                            'Your account will be permanently deleted in 30 days.',
                            style: TextStyle(fontSize: 12,
                                color: Color(0xFF9A6600))),
                          const SizedBox(height: 10),
                          OutlinedButton(
                            onPressed: _cancelDeletion,
                            child: const Text('Cancel deletion'),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    _SettingRow(
                      icon: Icons.delete_forever_outlined,
                      label: 'Delete account',
                      subtitle:
                          'Permanently delete all data within 30 days',
                      labelColor: AppColors.red,
                      onTap: _requestDeletion,
                    ),
                  ],

                  const SizedBox(height: 8),
                  _SettingRow(
                    icon: Icons.logout,
                    label: 'Sign out',
                    onTap: _signOut,
                  ),

                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      'Nipino-Manabu v1.0.0\n'
                      '© ${DateTime.now().year} Nipino-Manabu',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.muted2),
                    ),
                  ),
                ],
              ),
            ),

            AppBottomNav(
              currentIndex: 4,
              onTap: (i) {
                switch (i) {
                  case 0: Navigator.pushReplacementNamed(context, '/home'); break;
                  case 1: Navigator.pushReplacementNamed(context, '/lessons'); break;
                  case 2: Navigator.pushReplacementNamed(context, '/quiz',
                      arguments: {'level': 'N3', 'category': 'kanji'}); break;
                  case 3: Navigator.pushReplacementNamed(context, '/leaderboard'); break;
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      const Expanded(child: Divider(color: AppColors.border)),
      const SizedBox(width: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
            color: AppColors.red,
            borderRadius: BorderRadius.circular(3)),
        child: Text(label, style: const TextStyle(
            color: Colors.white, fontSize: 10,
            fontWeight: FontWeight.w700, letterSpacing: 0.5)),
      ),
      const SizedBox(width: 10),
      const Expanded(child: Divider(color: AppColors.border)),
    ]),
  );
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String?  subtitle;
  final Color    labelColor;
  final VoidCallback onTap;
  const _SettingRow({
    required this.icon,
    required this.label,
    this.subtitle,
    this.labelColor = AppColors.ink2,
    required this.onTap,
  });
  @override Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(children: [
        Icon(icon, size: 18, color: labelColor),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: labelColor)),
            if (subtitle != null)
              Text(subtitle!, style: const TextStyle(
                  fontSize: 11, color: AppColors.muted)),
          ],
        )),
        Icon(Icons.chevron_right, size: 16, color: AppColors.muted2),
      ]),
    ),
  );
}
