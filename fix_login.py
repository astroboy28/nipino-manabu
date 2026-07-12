import re

# ── Fix login_screen.dart ──────────────────────────────────────────────────
c = open('lib/screens/auth/login_screen.dart', encoding='utf-8').read()

# Fix 1: Forgot password button navigates to forgot password screen
old = """                  child: TextButton(
                    onPressed: () {},
                    child: const Text('Forgot password?',
                      style: TextStyle(color: AppColors.red, fontSize: 12)),
                  ),"""
new = """                  child: TextButton(
                    onPressed: () => Navigator.pushNamed(context, '/forgot-password'),
                    child: const Text('Forgot password?',
                      style: TextStyle(color: AppColors.red, fontSize: 12)),
                  ),"""

if old in c:
    c = c.replace(old, new)
    print("Fix 1: Forgot password button fixed!")
else:
    print("Fix 1: Not found")

# Fix 2: After login, check if email verified before going to /home
old2 = """    final ok   = await auth.login(_emailCtrl.text, _pwCtrl.text);
    if (ok && mounted) {
      Navigator.pushReplacementNamed(context, '/home');
    }"""
new2 = """    final ok   = await auth.login(_emailCtrl.text, _pwCtrl.text);
    if (ok && mounted) {
      final user = context.read<AuthProvider>().user;
      if (user != null && !user.isVerified) {
        Navigator.pushReplacementNamed(context, '/verify-email');
      } else {
        Navigator.pushReplacementNamed(context, '/home');
      }
    }"""

if old2 in c:
    c = c.replace(old2, new2)
    print("Fix 2: Email verification redirect fixed!")
else:
    print("Fix 2: Not found")

open('lib/screens/auth/login_screen.dart', 'w', encoding='utf-8').write(c)
print("login_screen.dart saved!")
