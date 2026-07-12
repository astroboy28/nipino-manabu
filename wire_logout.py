c = open('lib/screens/profile/profile_screen.dart', encoding='utf-8').read()

# 1. Replace the logout TextButton onPressed with a confirmation dialog
old = """                TextButton(
                  onPressed: () async {
                    await auth.logout();
                    if (mounted) Navigator.pushReplacementNamed(context, '/login');
                  },
                  child: const Text('Sign out',style:TextStyle(color:AppColors.red,fontSize:13)),
                ),"""

new = """                TextButton(
                  onPressed: () => _confirmLogout(context, auth),
                  child: const Text('Sign out',style:TextStyle(color:AppColors.red,fontSize:13)),
                ),"""

if old in c:
    c = c.replace(old, new)
    print("1. Logout button wired to confirmation")
else:
    print("1. NOT FOUND")
    idx = c.find('Sign out')
    print(repr(c[idx-300:idx+50]))

# 2. Add the _confirmLogout method (reuse the _confirmDelete insertion point)
old2 = "  Future<void> _confirmDelete(BuildContext context) async {"
new2 = """  Future<void> _confirmLogout(BuildContext context, AuthProvider auth) async {
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

  Future<void> _confirmDelete(BuildContext context) async {"""

if old2 in c:
    c = c.replace(old2, new2)
    print("2. _confirmLogout method added")
else:
    print("2. NOT FOUND")

open('lib/screens/profile/profile_screen.dart', 'w', encoding='utf-8').write(c)
print("\nprofile_screen.dart saved!")
