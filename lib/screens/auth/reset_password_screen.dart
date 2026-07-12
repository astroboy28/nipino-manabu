// lib/screens/auth/reset_password_screen.dart
// Landing screen for the password-reset email link
// (https://nipino-manabu.com/reset-password?token=...). The backend endpoint
// (POST /auth/reset-password) has existed since launch, but nothing in the
// app could ever reach it — there was no screen to enter a new password.
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String token;
  const ResetPasswordScreen({super.key, required this.token});
  @override State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _form         = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl  = TextEditingController();
  bool _loading = false;
  bool _done    = false;
  String? _error;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    final res = await ApiService.resetPassword(
        token: widget.token, newPassword: _passwordCtrl.text);
    if (!mounted) return;
    if (res.success) {
      setState(() { _loading = false; _done = true; });
    } else {
      setState(() { _loading = false; _error = res.error ?? 'Something went wrong.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
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
                Container(width: 64, height: 64,
                  decoration: BoxDecoration(color: AppColors.redLight,
                    borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.lock_reset,
                    color: AppColors.red, size: 32)),
                const SizedBox(height: 20),
                const Text('Set a new password',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700,
                    color: AppColors.ink)),
                const SizedBox(height: 8),
                const Text(
                  'Choose a new password for your account. Must be 8+ characters '
                  'with at least one uppercase letter and one number.',
                  style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.6)),
                const SizedBox(height: 32),

                if (widget.token.isEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.redLight,
                      border: const Border(left: BorderSide(color: AppColors.red, width: 3)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'This reset link is missing its token. Please use the link from your email again.',
                      style: TextStyle(color: AppColors.red, fontSize: 13)),
                  ),
                ] else if (_done) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.greenLight,
                      border: const Border(left: BorderSide(color: AppColors.green, width: 3)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Password updated!',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                          color: AppColors.green)),
                      SizedBox(height: 4),
                      Text('You can now log in with your new password.',
                        style: TextStyle(fontSize: 12, color: AppColors.green)),
                    ]),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => Navigator.pushNamedAndRemoveUntil(
                        context, '/login', (_) => false),
                    child: const Text('Back to login'),
                  ),
                ] else ...[
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.redLight,
                        border: const Border(left: BorderSide(color: AppColors.red, width: 3)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(_error!,
                        style: const TextStyle(color: AppColors.red, fontSize: 13)),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _passwordCtrl,
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'New password',
                      prefixIcon: Icon(Icons.lock_outline, size: 18),
                    ),
                    validator: (v) {
                      if (v == null || v.length < 8) return 'At least 8 characters';
                      if (!RegExp(r'[A-Z]').hasMatch(v)) return 'Needs an uppercase letter';
                      if (!RegExp(r'[0-9]').hasMatch(v)) return 'Needs a number';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmCtrl,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: 'Confirm new password',
                      prefixIcon: Icon(Icons.lock_outline, size: 18),
                    ),
                    validator: (v) {
                      if (v != _passwordCtrl.text) return 'Passwords do not match';
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                        : const Text('Update password'),
                  ),
                ],
                const SizedBox(height: 16),
                Center(child: TextButton(
                  onPressed: () => Navigator.pushNamedAndRemoveUntil(
                      context, '/login', (_) => false),
                  child: const Text('Back to login',
                    style: TextStyle(color: AppColors.muted, fontSize: 13)),
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
