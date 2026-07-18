// lib/screens/profile/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_provider.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';
import '../../widgets/app_bottom_nav.dart';

Future<void> _openLegalUrl(BuildContext context, String url) async {
  final uri = Uri.parse(url);
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $url')),
      );
    }
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<AppBadge> _badges = <AppBadge>[];

  @override
  void initState() {
    super.initState();
    _loadBadges();
  }

  Future<void> _loadBadges() async {
    // GET /user/badges already exists server-side and returns each badge's
    // real per-user earned/earned_at state — this used to call getProfile()
    // twice (once discarded) and then hardcode 4 badges as always earned.
    final res = await ApiService.getBadges();
    if (mounted && res.success) {
      setState(() => _badges = res.data ?? <AppBadge>[]);
    }
  }

  Future<void> _confirmLogout(BuildContext context, AuthProvider auth) async {
    final user = auth.user;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Sign out?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Before you go, here is a reminder of your progress:',
            style: TextStyle(fontSize: 13, color: AppColors.muted)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.goldLight,
              border: Border.all(color: const Color(0xFFE8C56A)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              const Icon(Icons.monetization_on, color: AppColors.gold, size: 28),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${user?.coins ?? 0} coins',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.gold)),
                  const Text('saved to your account',
                    style: TextStyle(fontSize: 11, color: AppColors.muted)),
                ],
              )),
            ]),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.bg2,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(6)),
              child: Column(children: [
                Icon(Icons.local_fire_department, color: const Color(0xFFE65100), size: 18),
                const SizedBox(height: 2),
                Text('${user?.streakDays ?? 0} day streak',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.ink)),
              ]),
            )),
            const SizedBox(width: 8),
            Expanded(child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.bg2,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(6)),
              child: Column(children: [
                const Icon(Icons.school, color: AppColors.red, size: 18),
                const SizedBox(height: 2),
                Text(user?.currentLevel ?? 'N5',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.ink)),
              ]),
            )),
          ]),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out')),
        ],
      ),
    );
    if (confirmed != true) return;
    await auth.logout();
    if (context.mounted) Navigator.pushReplacementNamed(context, '/login');
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final pwCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete account?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'This will permanently delete your account and all data after 30 days. Enter your password to confirm.',
            style: TextStyle(fontSize: 13, color: Color(0xFF666666))),
          const SizedBox(height: 16),
          TextField(
            controller: pwCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              prefixIcon: Icon(Icons.lock_outlined, size: 18),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC0392B)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final res = await ApiService.requestAccountDeletion(pwCtrl.text);
    if (!mounted) return;
    if (res.success) {
      await context.read<AuthProvider>().logout();
      Navigator.pushReplacementNamed(context, '/login');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account deletion scheduled. You have 30 days to cancel.'),
          behavior: SnackBarBehavior.floating));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.error ?? 'Failed to delete account.'),
          backgroundColor: const Color(0xFFC0392B),
          behavior: SnackBarBehavior.floating));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header strip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border))),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(width:34,height:34,
                    decoration:BoxDecoration(color:AppColors.bg2,border:Border.all(color:AppColors.border),borderRadius:BorderRadius.circular(6)),
                    child:const Icon(Icons.arrow_back,size:18,color:AppColors.ink2))),
                const SizedBox(width:10),
                const Text('My Profile',style:TextStyle(fontSize:16,fontWeight:FontWeight.w700,color:AppColors.ink)),
                const Spacer(),
                TextButton(
                  onPressed: () => _confirmLogout(context, auth),
                  child: const Text('Sign out',style:TextStyle(color:AppColors.red,fontSize:13)),
                ),
              ]),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Avatar + name card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: AppColors.red,
                        child: Text(
                          user?.username[0].toUpperCase() ?? '?',
                          style: const TextStyle(fontSize: 28,
                            fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user?.username ?? '—',
                            style: const TextStyle(fontSize: 18,
                              fontWeight: FontWeight.w700, color: AppColors.ink)),
                          Text(user?.email ?? '—',
                            style: const TextStyle(fontSize: 12,
                              color: AppColors.muted)),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.redLight,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(user?.currentLevel ?? 'N5',
                              style: const TextStyle(fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.red)),
                          ),
                        ],
                      )),
                    ]),
                  ),
                  const SizedBox(height: 12),

                  // Stats row
                  Row(children: [
                    _StatTile(num: '${user?.coins ?? 0}',     label: 'Coins',    color: AppColors.gold),
                    const SizedBox(width: 8),
                    _StatTile(num: '${user?.streakDays ?? 0}', label: 'Streak',  color: const Color(0xFFE65100)),
                    const SizedBox(width: 8),
                    _StatTile(num: '${user?.totalScore ?? 0}', label: 'Score',   color: AppColors.red),
                  ]),
                  const SizedBox(height: 16),

                  // Badges section
                  _SectionTag(tag: 'BADGES'),
                  const SizedBox(height: 10),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.8,
                    ),
                    itemCount: _badges.length,
                    itemBuilder: (_, i) => _BadgeTile(badge: _badges[i]),
                  ),
                  const SizedBox(height: 16),

                  // Privacy policy link
                  _SectionTag(tag: 'LEGAL'),
                  const SizedBox(height: 10),
                  _LinkRow(icon: Icons.settings_outlined, label: 'Settings',
                    onTap: () => Navigator.pushNamed(context, '/settings')),
                  _LinkRow(icon: Icons.timer_outlined, label: 'Quiz Preferences',
                    onTap: () => Navigator.pushNamed(context, '/quiz-preferences')),
                  _LinkRow(icon: Icons.privacy_tip_outlined, label: 'Privacy Policy',
                    onTap: () => _openLegalUrl(context, 'https://nipino-manabu.com/privacy')),
                  _LinkRow(icon: Icons.description_outlined, label: 'Terms of Service',
                    onTap: () => _openLegalUrl(context, 'https://nipino-manabu.com/terms')),
                  _LinkRow(icon: Icons.delete_outline, label: 'Delete my account',
                    onTap: () => _confirmDelete(context), color: AppColors.red),
                ],
              ),
            ),

            AppBottomNav(
              currentIndex: 5,
              onTap: (i) {
                switch (i) {
                  case 0: Navigator.pushReplacementNamed(context, '/home'); break;
                  case 1: Navigator.pushReplacementNamed(context, '/lessons'); break;
                  case 2: Navigator.pushReplacementNamed(context, '/quiz', arguments: {'level': 'N5', 'category': 'kanji'}); break;
                  case 3: Navigator.pushReplacementNamed(context, '/leaderboard'); break;
                  case 4: Navigator.pushReplacementNamed(context, '/duels'); break;
                  case 5: Navigator.pushReplacementNamed(context, '/profile'); break;
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String num, label;
  final Color color;
  const _StatTile({required this.num, required this.label, required this.color});
  @override Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(children: [
        Text(num, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
      ]),
    ),
  );
}

class _BadgeTile extends StatelessWidget {
  final AppBadge badge;
  const _BadgeTile({required this.badge});
  @override Widget build(BuildContext context) => Opacity(
    opacity: badge.earned ? 1 : 0.3,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(badge.iconEmoji, style: const TextStyle(fontSize: 28)),
        const SizedBox(height: 4),
        Text(badge.name, style: const TextStyle(fontSize: 9,
          fontWeight: FontWeight.w600, color: AppColors.ink2),
          textAlign: TextAlign.center, maxLines: 2,
          overflow: TextOverflow.ellipsis),
      ],
    ),
  );
}

class _SectionTag extends StatelessWidget {
  final String tag;
  const _SectionTag({required this.tag});
  @override Widget build(BuildContext context) => Row(children: [
    const Expanded(child: Divider(color: AppColors.border)),
    const SizedBox(width: 10),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(3)),
      child: Text(tag, style: const TextStyle(color: Colors.white, fontSize: 10,
        fontWeight: FontWeight.w700, letterSpacing: 0.5)),
    ),
    const SizedBox(width: 10),
    const Expanded(child: Divider(color: AppColors.border)),
  ]);
}

class _LinkRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  const _LinkRow({required this.icon, required this.label, required this.onTap,
    this.color = AppColors.ink2});
  @override Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
        const Spacer(),
        Icon(Icons.chevron_right, size: 16, color: AppColors.muted2),
      ]),
    ),
  );
}
