forgot_screen = '''// lib/screens/auth/forgot_password_screen.dart
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _form     = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _loading   = false;
  bool _sent      = false;
  String? _error;

  @override
  void dispose() { _emailCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    final res = await ApiService.forgotPassword(_emailCtrl.text.trim());
    if (!mounted) return;
    if (res.success) {
      setState(() { _loading = false; _sent = true; });
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
                Row(children: [
                  Container(width:40, height:40,
                    decoration: BoxDecoration(color:AppColors.red,
                      borderRadius:BorderRadius.circular(8)),
                    child: const Center(child: Text('日',
                      style: TextStyle(fontFamily:'NotoSansJP', fontSize:20,
                        fontWeight:FontWeight.w700, color:Colors.white)))),
                  const SizedBox(width: 10),
                  RichText(text: const TextSpan(
                    style: TextStyle(fontSize:18, fontWeight:FontWeight.w700,
                      color:AppColors.ink),
                    children: [
                      TextSpan(text: 'Nipino-'),
                      TextSpan(text: 'Manabu',
                        style: TextStyle(color: AppColors.red)),
                    ])),
                ]),
                const SizedBox(height: 48),
                Container(width:64, height:64,
                  decoration: BoxDecoration(color:AppColors.redLight,
                    borderRadius:BorderRadius.circular(14)),
                  child: const Icon(Icons.lock_reset,
                    color:AppColors.red, size:32)),
                const SizedBox(height: 20),
                const Text('Forgot password?',
                  style: TextStyle(fontSize:24, fontWeight:FontWeight.w700,
                    color:AppColors.ink)),
                const SizedBox(height: 8),
                const Text(
                  'Enter your email address and we will send you a link to reset your password.',
                  style: TextStyle(fontSize:13, color:AppColors.muted, height:1.6)),
                const SizedBox(height: 32),

                if (_sent) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.greenLight,
                      border: const Border(left: BorderSide(color:AppColors.green, width:3)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Email sent!',
                        style: TextStyle(fontSize:14, fontWeight:FontWeight.w700,
                          color:AppColors.green)),
                      const SizedBox(height: 4),
                      Text('We sent a reset link to ${_emailCtrl.text}. Check your inbox and spam folder.',
                        style: const TextStyle(fontSize:12, color:AppColors.green)),
                    ]),
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Back to login'),
                  ),
                ] else ...[
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.redLight,
                        border: const Border(left: BorderSide(color:AppColors.red, width:3)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(_error!,
                        style: const TextStyle(color:AppColors.red, fontSize:13)),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                      prefixIcon: Icon(Icons.email_outlined, size:18),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Email is required';
                      if (!v.contains('@')) return 'Enter a valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(width:20, height:20,
                            child: CircularProgressIndicator(
                              color:Colors.white, strokeWidth:2))
                        : const Text('Send reset link'),
                  ),
                  const SizedBox(height: 16),
                  Center(child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Back to login',
                      style: TextStyle(color:AppColors.muted, fontSize:13)),
                  )),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
'''

open('lib/screens/auth/forgot_password_screen.dart', 'w', encoding='utf-8').write(forgot_screen)
print("forgot_password_screen.dart created!")
