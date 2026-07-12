// lib/screens/settings/quiz_preferences_screen.dart
// ─── Per-user timer settings for regular (non-duel) quizzes ─────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../services/social_api_service.dart';
import '../../services/auth_provider.dart';
import '../../services/sound_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QuizPreferencesScreen extends StatefulWidget {
  const QuizPreferencesScreen({super.key});
  @override State<QuizPreferencesScreen> createState() =>
      _QuizPreferencesScreenState();
}

class _QuizPreferencesScreenState
    extends State<QuizPreferencesScreen> {
  bool   _timedMode    = true;
  int    _secondsPerQ  = 15;
  bool   _saving       = false;
  bool   _saved        = false;
  String? _error;
  bool   _soundEnabled = true;
  final _sound = SoundService();

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await _sound.init();
    if (!mounted) return;
    setState(() {
      _timedMode    = prefs.getBool('quiz_timed_mode') ?? true;
      _secondsPerQ  = prefs.getInt('quiz_seconds_per_q') ?? 15;
      _soundEnabled = _sound.enabled;
    });
  }

  // Presets for quick selection
  static const _presets = [
    {'label': 'Relaxed',  'timed': false, 'secs': 0,  'desc': 'No time pressure — focus on learning'},
    {'label': 'Normal',   'timed': true,  'secs': 20, 'desc': '20 seconds per question'},
    {'label': 'Fast',     'timed': true,  'secs': 10, 'desc': '10 seconds — sharpen your reflexes'},
    {'label': 'Blitz',    'timed': true,  'secs': 5,  'desc': '5 seconds — extreme challenge'},
  ];

  Future<void> _save() async {
    setState(() { _saving = true; _saved = false; _error = null; });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('quiz_timed_mode', _timedMode);
    await prefs.setInt('quiz_seconds_per_q', _secondsPerQ);
    await _sound.setEnabled(_soundEnabled);
    final res = await SocialApiService.updateQuizPreferences(
      timedMode: _timedMode, secondsPerQ: _secondsPerQ);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = true;
      if (!res.success) _error = res.error;
    });
    if (_saved) {
      await context.read<AuthProvider>().refreshUser();
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _saved = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quiz preferences'),
        bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1), child: Divider(height: 1))),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [

          // Explanation banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: AppColors.blueLight,
                border: const Border(
                    left: BorderSide(color: AppColors.blue, width: 3)),
                borderRadius: const BorderRadius.only(
                    topRight:    Radius.circular(6),
                    bottomRight: Radius.circular(6))),
            child: const Text(
              'These settings apply to your regular practice quizzes. '
              'Duel and challenge quizzes always use their own timer '
              'settings configured by the room host or admin.',
              style: TextStyle(
                  fontSize: 12, color: AppColors.blue, height: 1.6)),
          ),
          const SizedBox(height: 24),

          // Quick presets
          _sectionLabel('QUICK PRESETS'),
          const SizedBox(height: 10),
          ...(_presets.map((p) {
            final isSelected = p['timed'] == _timedMode &&
                (!(p['timed'] as bool) || p['secs'] == _secondsPerQ);
            return GestureDetector(
              onTap: () => setState(() {
                _timedMode   = p['timed'] as bool;
                _secondsPerQ = p['secs'] as int;
              }),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.redLight : AppColors.bg,
                  border: Border.all(
                      color: isSelected ? AppColors.red : AppColors.border,
                      width: isSelected ? 1.5 : 1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(
                    p['timed'] == false
                        ? Icons.self_improvement
                        : (p['secs'] as int) <= 5
                            ? Icons.bolt
                            : (p['secs'] as int) <= 10
                                ? Icons.speed
                                : Icons.timer,
                    color: isSelected ? AppColors.red : AppColors.muted,
                    size: 22),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(p['label'] as String,
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700,
                            color: isSelected
                                ? AppColors.red : AppColors.ink)),
                    Text(p['desc'] as String,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.muted)),
                  ])),
                  if (isSelected)
                    const Icon(Icons.check_circle,
                        color: AppColors.red, size: 20),
                ]),
              ),
            );
          })),

          const SizedBox(height: 20),
          _sectionLabel('CUSTOM SETTINGS'),
          const SizedBox(height: 14),

          // Timer toggle
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
                color: AppColors.bg,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(8)),
            child: SwitchListTile.adaptive(
              value: _timedMode,
              activeColor: AppColors.red,
              contentPadding: EdgeInsets.zero,
              title: const Text('Timed mode',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text(
                _timedMode
                    ? 'Each question has a countdown timer'
                    : 'Take as long as you need — no pressure',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.muted)),
              onChanged: (v) => setState(() => _timedMode = v),
            ),
          ),
          const SizedBox(height: 12),

          // Seconds slider (only when timed)
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState: _timedMode
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: AppColors.bg,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(8)),
              child: Column(children: [
                Row(children: [
                  const Text('Seconds per question',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                        color: AppColors.redLight,
                        borderRadius: BorderRadius.circular(20)),
                    child: Text('$_secondsPerQ s',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700,
                            color: AppColors.red)),
                  ),
                ]),
                Slider.adaptive(
                  value: _secondsPerQ.toDouble(),
                  min: 5, max: 60, divisions: 11,
                  activeColor: AppColors.red,
                  label: '$_secondsPerQ seconds',
                  onChanged: (v) =>
                      setState(() => _secondsPerQ = v.round()),
                ),
                // Visual guide
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _TimeLabel('5s', 'Expert', AppColors.red),
                    _TimeLabel('15s', 'Normal', AppColors.muted),
                    _TimeLabel('60s', 'Relaxed', AppColors.green),
                  ],
                ),
              ]),
            ),
            secondChild: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: AppColors.greenLight,
                  border: Border.all(color: AppColors.green),
                  borderRadius: BorderRadius.circular(8)),
              child: const Row(children: [
                Icon(Icons.self_improvement,
                    color: AppColors.green, size: 20),
                SizedBox(width: 10),
                Text('No timer — study at your own pace',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.green,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ),

          const SizedBox(height: 24),
          _sectionLabel('SOUND'),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
                color: AppColors.bg,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(8)),
            child: SwitchListTile.adaptive(
              value: _soundEnabled,
              activeColor: AppColors.red,
              contentPadding: EdgeInsets.zero,
              title: const Text('Sound effects',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text(
                _soundEnabled
                    ? 'Hear a sound for correct and wrong answers'
                    : 'Quiz sounds are muted',
                style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              onChanged: (v) => setState(() => _soundEnabled = v),
            ),
          ),

          const SizedBox(height: 24),

          // Error
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: AppColors.redLight,
                  border: const Border(
                      left: BorderSide(color: AppColors.red, width: 3)),
                  borderRadius: BorderRadius.circular(4)),
              child: Text(_error!,
                  style: const TextStyle(
                      color: AppColors.red, fontSize: 13))),
            const SizedBox(height: 12),
          ],

          // Save button
          ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : Icon(_saved ? Icons.check : Icons.save_outlined,
                    size: 18),
            label: Text(_saved ? 'Saved!' : 'Save preferences'),
            style: ElevatedButton.styleFrom(
                backgroundColor: _saved ? AppColors.green : AppColors.red),
          ),
          const SizedBox(height: 8),
          const Text(
            'Changes apply to your next quiz session.',
            style: TextStyle(fontSize: 11, color: AppColors.muted),
            textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  Widget _sectionLabel(String label) => Row(children: [
    const Expanded(child: Divider(color: AppColors.border)),
    const SizedBox(width: 10),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
          color: AppColors.red, borderRadius: BorderRadius.circular(3)),
      child: Text(label, style: const TextStyle(
          color: Colors.white, fontSize: 10,
          fontWeight: FontWeight.w700, letterSpacing: 0.5))),
    const SizedBox(width: 10),
    const Expanded(child: Divider(color: AppColors.border)),
  ]);
}

class _TimeLabel extends StatelessWidget {
  final String time, label;
  final Color color;
  const _TimeLabel(this.time, this.label, this.color);
  @override Widget build(BuildContext context) => Column(children: [
    Text(time, style: TextStyle(fontSize: 11,
        fontWeight: FontWeight.w700, color: color)),
    Text(label, style: const TextStyle(
        fontSize: 10, color: AppColors.muted)),
  ]);
}
