// lib/screens/auth/email_verify_screen.dart
// ─── Shown after registration until email is verified ────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_provider.dart';
import '../../services/api_service.dart';

class EmailVerifyScreen extends StatefulWidget {
  const EmailVerifyScreen({super.key});
  @override State<EmailVerifyScreen> createState() => _EmailVerifyScreenState();
}

class _EmailVerifyScreenState extends State<EmailVerifyScreen> {
  bool _resending = false;
  bool _resentOk  = false;

  Future<void> _resend() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    setState(() { _resending = true; _resentOk = false; });
    await ApiService.resendVerification(user.email);
    if (mounted) setState(() { _resending = false; _resentOk = true; });
  }

  Future<void> _checkVerified() async {
    await context.read<AuthProvider>().refreshUser();
    final user = context.read<AuthProvider>().user;
    if (user != null && mounted) {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              // Logo
              Row(children: [
                Container(width:40, height:40,
                  decoration: BoxDecoration(color:AppColors.red,
                    borderRadius:BorderRadius.circular(8)),
                  child: const Center(child: Text('日',
                    style: TextStyle(fontFamily:'NotoSansJP', fontSize:20,
                      fontWeight:FontWeight.w700, color:Colors.white)))),
                const SizedBox(width:10),
                RichText(text:const TextSpan(
                  style:TextStyle(fontSize:18, fontWeight:FontWeight.w700,
                    color:AppColors.ink),
                  children:[
                    TextSpan(text:'Nipino-'),
                    TextSpan(text:'Manabu',
                      style:TextStyle(color:AppColors.red)),
                  ])),
              ]),
              const SizedBox(height: 48),

              Container(width:64, height:64,
                decoration: BoxDecoration(color:AppColors.goldLight,
                  borderRadius:BorderRadius.circular(14)),
                child: const Icon(Icons.mail_outline,
                  color:AppColors.gold, size:32)),
              const SizedBox(height: 20),

              const Text('Verify your email',
                style: TextStyle(fontSize:24, fontWeight:FontWeight.w700,
                  color:AppColors.ink)),
              const SizedBox(height: 8),
              Text(
                'We sent a verification link to\n${user?.email ?? 'your email address'}.\n\n'
                'Click the link in the email to activate your account.',
                style: const TextStyle(fontSize:13, color:AppColors.muted,
                  height:1.6)),
              const SizedBox(height: 32),

              // Already verified?
              ElevatedButton.icon(
                onPressed: _checkVerified,
                icon: const Icon(Icons.refresh, size:18),
                label: const Text("I've verified — continue"),
              ),
              const SizedBox(height: 12),

              // Resend
              OutlinedButton.icon(
                onPressed: _resending ? null : _resend,
                icon: _resending
                    ? const SizedBox(width:16, height:16,
                        child:CircularProgressIndicator(strokeWidth:2,
                          color:AppColors.red))
                    : const Icon(Icons.send_outlined, size:18),
                label: Text(_resentOk ? 'Sent! Check your inbox' : 'Resend verification email'),
              ),

              if (_resentOk) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.greenLight,
                    border: const Border(
                      left: BorderSide(color:AppColors.green, width:3)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('New link sent! Check your spam folder too.',
                    style: TextStyle(fontSize:12, color:AppColors.green)),
                ),
              ],

              const Spacer(),

              // Sign out option
              Center(child: TextButton(
                onPressed: () async {
                  await context.read<AuthProvider>().logout();
                  if (mounted) Navigator.pushReplacementNamed(context, '/login');
                },
                child: const Text('Sign out',
                  style: TextStyle(color:AppColors.muted, fontSize:13)),
              )),
            ],
          ),
        ),
      ),
    );
  }
}
