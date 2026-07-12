// lib/screens/auth/login_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form     = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _pwCtrl    = TextEditingController();
  bool _obscurePw  = true;

  @override
  void dispose() {
    _emailCtrl.dispose(); _pwCtrl.dispose(); super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final ok   = await auth.login(_emailCtrl.text, _pwCtrl.text);
    if (ok && mounted) {
      final user = context.read<AuthProvider>().user;
      if (user != null && !user.isVerified) {
        Navigator.pushReplacementNamed(context, '/verify-email');
      } else {
        Navigator.pushReplacementNamed(context, '/home');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 40),
                // Logo
                Row(children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.red,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text('日', style: TextStyle(
                        fontFamily: 'NotoSansJP', fontSize: 20,
                        fontWeight: FontWeight.w700, color: Colors.white,
                      )),
                    ),
                  ),
                  const SizedBox(width: 10),
                  RichText(text: const TextSpan(
                    style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                    children: [
                      TextSpan(text: 'Nipino-'),
                      TextSpan(text: 'Manabu',
                        style: TextStyle(color: AppColors.red)),
                    ],
                  )),
                ]),
                const SizedBox(height: 40),
                const Text('Welcome back',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700,
                    color: AppColors.ink)),
                const SizedBox(height: 6),
                const Text('Sign in to continue your Japanese journey.',
                  style: TextStyle(fontSize: 13, color: AppColors.muted)),
                const SizedBox(height: 32),

                // Error banner
                if (auth.error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.redLight,
                      border: const Border(left: BorderSide(color: AppColors.red, width: 3)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(auth.error!,
                      style: const TextStyle(color: AppColors.red, fontSize: 13)),
                  ),
                  const SizedBox(height: 16),
                ],

                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Email address',
                    prefixIcon: Icon(Icons.email_outlined, size: 18),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Email is required';
                    if (!v.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _pwCtrl,
                  obscureText: _obscurePw,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outlined, size: 18),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePw ? Icons.visibility_off : Icons.visibility,
                        size: 18,
                      ),
                      onPressed: () => setState(() => _obscurePw = !_obscurePw),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Password is required';
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pushNamed(context, '/forgot-password'),
                    child: const Text('Forgot password?',
                      style: TextStyle(color: AppColors.red, fontSize: 12)),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: auth.loading ? null : _submit,
                  child: auth.loading
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                      : const Text('Sign In'),
                ),
                const SizedBox(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text("Don't have an account? ",
                    style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  GestureDetector(
                    onTap: () => Navigator.pushNamed(context, '/register'),
                    child: const Text('Register',
                      style: TextStyle(
                        color: AppColors.red, fontSize: 13,
                        fontWeight: FontWeight.w700)),
                  ),
                ]),
                const SizedBox(height: 40),
                // Privacy note
                Center(
                  child: Text(
                    'By signing in you agree to our Terms & Privacy Policy.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 10, color: AppColors.muted2),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
