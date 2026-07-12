c = open('lib/screens/profile/profile_screen.dart', encoding='utf-8').read()

# Fix delete account button
old = "                  _LinkRow(icon: Icons.delete_outline, label: 'Delete my account',\n                    onTap: () {}, color: AppColors.red),"
new = """                  _LinkRow(icon: Icons.delete_outline, label: 'Delete my account',
                    onTap: () => _confirmDelete(context), color: AppColors.red),"""

if old in c:
    c = c.replace(old, new)
    print("Delete button fixed!")
else:
    print("Not found - checking...")
    idx = c.find('Delete my account')
    print(repr(c[idx-50:idx+100]))

# Add _confirmDelete method before build()
old2 = "  @override\n  Widget build(BuildContext context) {"
new2 = """  Future<void> _confirmDelete(BuildContext context) async {
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
  Widget build(BuildContext context) {"""

if old2 in c:
    c = c.replace(old2, new2)
    print("_confirmDelete method added!")
else:
    print("Build method not found")

open('lib/screens/profile/profile_screen.dart', 'w', encoding='utf-8').write(c)
print("profile_screen.dart saved!")
