// lib/screens/gdpr/data_export_screen.dart
// ─── GDPR Article 20 — Right to data portability ─────────────────────────────
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';

class DataExportScreen extends StatefulWidget {
  const DataExportScreen({super.key});
  @override State<DataExportScreen> createState() => _DataExportScreenState();
}

class _DataExportScreenState extends State<DataExportScreen> {
  bool    _loading   = false;
  bool    _done      = false;
  String? _error;
  Map<String, dynamic>? _exportData;

  Future<void> _requestExport() async {
    setState(() { _loading = true; _error = null; _done = false; });
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        setState(() { _loading = false; _error = 'Please sign in again.'; });
        return;
      }
      final res = await http.get(
        Uri.parse('https://api.nipino-manabu.com/v1/account/export'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() { _loading = false; _done = true; _exportData = data; });
      } else {
        final body = jsonDecode(res.body);
        setState(() {
          _loading = false;
          _error   = body['message'] ?? 'Export failed. Try again later.';
        });
      }
    } catch (e) {
      setState(() { _loading = false; _error = 'Network error. Please try again.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Data'),
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.ink,
        elevation: 0,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ── Header ────────────────────────────────────────────────────────
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: AppColors.blueLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.folder_open_outlined,
                  color: AppColors.blue, size: 28),
            ),
            const SizedBox(height: 16),
            const Text('Your personal data',
              style: TextStyle(fontSize: 22,
                  fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 8),
            const Text(
              'Under GDPR Article 20 and the Philippine Data Privacy Act, '
              'you have the right to receive a copy of all personal data we '
              'hold about you in a portable, machine-readable format.',
              style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.6)),
            const SizedBox(height: 24),

            // ── What is included ──────────────────────────────────────────────
            _SectionTag(label: 'WHAT IS INCLUDED'),
            const SizedBox(height: 10),
            _InfoRow(icon: Icons.person_outline,
                label: 'Profile', desc: 'Username, email, level, coins, streak'),
            _InfoRow(icon: Icons.bar_chart,
                label: 'Progress', desc: 'Completion per JLPT level (N5–N1)'),
            _InfoRow(icon: Icons.quiz_outlined,
                label: 'Quiz history', desc: 'All quiz results and scores'),
            _InfoRow(icon: Icons.emoji_events_outlined,
                label: 'Badges', desc: 'All earned achievements with dates'),
            _InfoRow(icon: Icons.shopping_bag_outlined,
                label: 'Purchases', desc: 'In-app purchase records (no card data)'),
            _InfoRow(icon: Icons.notifications_outlined,
                label: 'Notifications', desc: 'Push notifications sent to you',
                isLast: true),
            const SizedBox(height: 24),

            // ── Error ─────────────────────────────────────────────────────────
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.redLight,
                  border: const Border(
                      left: BorderSide(color: AppColors.red, width: 3)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(_error!,
                    style: const TextStyle(color: AppColors.red, fontSize: 13)),
              ),
              const SizedBox(height: 16),
            ],

            // ── Success view ──────────────────────────────────────────────────
            if (_done && _exportData != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.greenLight,
                  border: Border.all(color: const Color(0xFF97C459)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.check_circle_outline,
                          color: AppColors.green, size: 20),
                      SizedBox(width: 8),
                      Text('Export ready',
                        style: TextStyle(fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.green)),
                    ]),
                    const SizedBox(height: 8),
                    _ExportStat('Profile exported',
                        _exportData!['profile'] != null ? 'Yes' : 'No'),
                    _ExportStat('Quiz results',
                        '${(_exportData!['quiz_history'] as List?)?.length ?? 0} records'),
                    _ExportStat('Badges earned',
                        '${(_exportData!['badges_earned'] as List?)?.length ?? 0} badges'),
                    _ExportStat('Purchases',
                        '${(_exportData!['purchases'] as List?)?.length ?? 0} transactions'),
                    const SizedBox(height: 12),
                    const Text(
                      'Your data was downloaded as JSON. You can view it '
                      'in any text editor or import it into a spreadsheet.',
                      style: TextStyle(fontSize: 12,
                          color: AppColors.green, height: 1.5)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _requestExport,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Download again'),
              ),
            ] else ...[
              // ── Download button ──────────────────────────────────────────────
              ElevatedButton.icon(
                onPressed: _loading ? null : _requestExport,
                icon: _loading
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.download_outlined, size: 18),
                label: Text(_loading ? 'Preparing export…' : 'Download my data (JSON)'),
              ),
            ],

            const SizedBox(height: 24),

            // ── Legal note ────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.bg2,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your rights',
                    style: TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w700, color: AppColors.ink)),
                  SizedBox(height: 6),
                  Text(
                    '• Request deletion of your account at any time\n'
                    '• Correct inaccurate data via Settings\n'
                    '• Withdraw notification consent in device settings\n'
                    '• Lodge a complaint with your local data authority\n\n'
                    'Contact: privacy@nipino-manabu.com',
                    style: TextStyle(fontSize: 11,
                        color: AppColors.muted, height: 1.6)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTag extends StatelessWidget {
  final String label;
  const _SectionTag({required this.label});
  @override Widget build(BuildContext context) => Row(children: [
    const Expanded(child: Divider(color: AppColors.border)),
    const SizedBox(width: 10),
    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(color: AppColors.blue,
          borderRadius: BorderRadius.circular(3)),
      child: Text(label, style: const TextStyle(color: Colors.white,
          fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5))),
    const SizedBox(width: 10),
    const Expanded(child: Divider(color: AppColors.border)),
  ]);
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, desc;
  final bool isLast;
  const _InfoRow({required this.icon, required this.label,
      required this.desc, this.isLast = false});
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: AppColors.bg,
      border: Border(
        left:   const BorderSide(color: AppColors.border),
        right:  const BorderSide(color: AppColors.border),
        top:    const BorderSide(color: AppColors.border),
        bottom: BorderSide(
            color: isLast ? AppColors.border : AppColors.border),
      ),
    ),
    child: Row(children: [
      Icon(icon, size: 16, color: AppColors.blue),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12,
              fontWeight: FontWeight.w700, color: AppColors.ink)),
          Text(desc, style: const TextStyle(fontSize: 11,
              color: AppColors.muted)),
        ])),
    ]),
  );
}

class _ExportStat extends StatelessWidget {
  final String label, value;
  const _ExportStat(this.label, this.value);
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(
          fontSize: 12, color: AppColors.green))),
      Text(value, style: const TextStyle(fontSize: 12,
          fontWeight: FontWeight.w700, color: AppColors.green)),
    ]),
  );
}
