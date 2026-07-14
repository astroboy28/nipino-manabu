// lib/screens/admin/admin_screen.dart
// ─── Admin panel: create challenges, invite users, finalize winners ──────────

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../services/api_service.dart';
import '../../services/social_api_service.dart';
import '../../models/social_models.dart';
import '../../theme/app_theme.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin panel'),
        bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1), child: Divider(height: 1))),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          _AdminTile(
            icon: Icons.add_circle_outline,
            label: 'Create challenge event',
            desc: 'Set prize, timer, level, and schedule',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(
                    builder: (_) => const CreateChallengeScreen())),
          ),
          _AdminTile(
            icon: Icons.emoji_events,
            label: 'Finalize a challenge',
            desc: 'Award winner coins + feature on home screen',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(
                    builder: (_) => const FinalizeChallengeScreen())),
          ),
          _AdminTile(
            icon: Icons.notifications_outlined,
            label: 'Notify all users',
            desc: 'Send push notification to all active users',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(
                    builder: (_) => const BroadcastNotificationScreen())),
          ),
        ]),
      ),
    );
  }
}

class _AdminTile extends StatelessWidget {
  final IconData icon; final String label, desc;
  final VoidCallback onTap;
  const _AdminTile({required this.icon, required this.label,
      required this.desc, required this.onTap});
  @override Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppColors.bg,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        Container(width: 44, height: 44,
            decoration: BoxDecoration(
                color: AppColors.redLight,
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: AppColors.red, size: 22)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(label, style: const TextStyle(fontSize: 14,
              fontWeight: FontWeight.w700, color: AppColors.ink)),
          Text(desc, style: const TextStyle(
              fontSize: 12, color: AppColors.muted)),
        ])),
        const Icon(Icons.chevron_right, color: AppColors.muted2),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Create challenge form (admin)
// ─────────────────────────────────────────────────────────────────────────────
class CreateChallengeScreen extends StatefulWidget {
  const CreateChallengeScreen({super.key});
  @override State<CreateChallengeScreen> createState() =>
      _CreateChallengeScreenState();
}

class _CreateChallengeScreenState extends State<CreateChallengeScreen> {
  final _form        = GlobalKey<FormState>();
  final _titleCtrl   = TextEditingController();
  final _descCtrl    = TextEditingController();
  final _badgeNameCtrl  = TextEditingController();
  final _badgeEmojiCtrl = TextEditingController(text: '🏆');
  String _level      = 'N3';
  String _category   = 'kanji';
  int    _prizeCoins = 500;
  int    _secsPerQ   = 20;
  int    _qCount     = 15;
  bool   _featured   = true;
  DateTime _startsAt = DateTime.now().add(const Duration(hours: 1));
  DateTime _endsAt   = DateTime.now().add(const Duration(days: 1));
  bool   _loading    = false;
  String? _error;
  bool   _done       = false;

  @override void dispose() {
    _titleCtrl.dispose(); _descCtrl.dispose();
    _badgeNameCtrl.dispose(); _badgeEmojiCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isStart) async {
    final initial = isStart ? _startsAt : _endsAt;
    final d = await showDatePicker(context: context,
        initialDate: initial,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365)));
    if (d == null) return;
    final t = await showTimePicker(context: context,
        initialTime: TimeOfDay.fromDateTime(initial));
    if (t == null) return;
    final dt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    setState(() {
      if (isStart) _startsAt = dt; else _endsAt = dt;
    });
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_endsAt.isBefore(_startsAt)) {
      setState(() => _error = 'End time must be after start time'); return;
    }
    setState(() { _loading = true; _error = null; });

    // Call challenge create endpoint via direct HTTP
    // (SocialApiService doesn't expose admin endpoints — add inline)
    final token = await ApiService.getToken();
    final res = await http.post(
      Uri.parse('https://api.nipino-manabu.com/v1/challenge/create'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'title':           _titleCtrl.text.trim(),
        'description':     _descCtrl.text.trim(),
        'level':           _level,
        'category':        _category,
        'prize_coins':     _prizeCoins,
        'seconds_per_q':   _secsPerQ,
        'question_count':  _qCount,
        'featured':        _featured,
        'starts_at':       _startsAt.toIso8601String(),
        'ends_at':         _endsAt.toIso8601String(),
        'prize_badge_name':  _badgeNameCtrl.text.trim(),
        'prize_badge_emoji': _badgeEmojiCtrl.text.trim(),
      }),
    );

    if (!mounted) return;
    final b = jsonDecode(res.body);
    setState(() {
      _loading = false;
      if (res.statusCode == 201) {
        _done = true;
      } else {
        _error = b['message'] ?? 'Failed to create challenge';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return Scaffold(
      appBar: AppBar(title: const Text('Challenge created')),
      body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center,
          children: [
        const Icon(Icons.check_circle, color: AppColors.green, size: 64),
        const SizedBox(height: 16),
        const Text('Challenge created!', style: TextStyle(
            fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text('Users will be notified when it goes live.',
            style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 24),
        ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back to admin')),
      ])),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Create challenge')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            if (_error != null) ...[
              Container(padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.redLight,
                      border: const Border(
                          left: BorderSide(color: AppColors.red, width: 3)),
                      borderRadius: BorderRadius.circular(4)),
                  child: Text(_error!, style: const TextStyle(
                      color: AppColors.red, fontSize: 13))),
              const SizedBox(height: 16),
            ],

            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Challenge title *'),
              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 16),

            Row(children: [
              Expanded(child: _DropField(
                  label: 'Level', value: _level,
                  items: ['N5','N4','N3','N2','N1'],
                  onChanged: (v) => setState(() => _level = v!))),
              const SizedBox(width: 12),
              Expanded(child: _DropField(
                  label: 'Category', value: _category,
                  items: ['kanji','vocabulary','grammar','listening'],
                  onChanged: (v) => setState(() => _category = v!))),
            ]),
            const SizedBox(height: 16),

            _SliderField(label: 'Prize coins', value: _prizeCoins.toDouble(),
                min: 100, max: 5000, divisions: 49,
                onChanged: (v) => setState(() => _prizeCoins = v.round())),
            _SliderField(label: 'Seconds per Q', value: _secsPerQ.toDouble(),
                min: 5, max: 60, divisions: 11,
                onChanged: (v) => setState(() => _secsPerQ = v.round())),
            _SliderField(label: 'Questions', value: _qCount.toDouble(),
                min: 5, max: 30, divisions: 25,
                onChanged: (v) => setState(() => _qCount = v.round())),
            const SizedBox(height: 12),

            Row(children: [
              Expanded(child: TextFormField(
                  controller: _badgeNameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Winner badge name'))),
              const SizedBox(width: 12),
              SizedBox(width: 70, child: TextFormField(
                  controller: _badgeEmojiCtrl,
                  decoration: const InputDecoration(labelText: 'Emoji'))),
            ]),
            const SizedBox(height: 16),

            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Starts at', style: TextStyle(fontSize: 13)),
              subtitle: Text(_fmtDt(_startsAt),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.calendar_today, size: 18),
              onTap: () => _pickDate(true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ends at', style: TextStyle(fontSize: 13)),
              subtitle: Text(_fmtDt(_endsAt),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.calendar_today, size: 18),
              onTap: () => _pickDate(false),
            ),
            SwitchListTile.adaptive(
              value: _featured, activeColor: AppColors.red,
              contentPadding: EdgeInsets.zero,
              title: const Text('Feature on home screen',
                  style: TextStyle(fontSize: 13)),
              onChanged: (v) => setState(() => _featured = v),
            ),
            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Create challenge'),
            ),
          ]),
        ),
      ),
    );
  }

  String _fmtDt(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Finalize challenge screen (admin)
// ─────────────────────────────────────────────────────────────────────────────
class FinalizeChallengeScreen extends StatefulWidget {
  const FinalizeChallengeScreen({super.key});
  @override State<FinalizeChallengeScreen> createState() =>
      _FinalizeChallengeScreenState();
}

class _FinalizeChallengeScreenState
    extends State<FinalizeChallengeScreen> {
  List<ChallengeEvent> _events = [];
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    // Was a permanent stub (_events always []) — this screen could never
    // actually list anything to finalize.
    final res = await SocialApiService.listChallenges('active');
    if (!mounted) return;
    setState(() {
      _events  = res.data ?? [];
      _loading = false;
    });
  }

  Future<void> _finalize(int eventId, String title) async {
    final ok = await showDialog<bool>(context: context, builder: (_) =>
        AlertDialog(
          title: const Text('Finalize challenge'),
          content: Text('Award the winner of "$title"?\n\n'
              'This will:\n• Find the top scorer\n'
              '• Award prize coins\n• Feature them on Home screen\n'
              '• This cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true),
                child: const Text('Finalize')),
          ],
        ));
    if (ok != true) return;

    final token = await ApiService.getToken();
    final res = await http.post(
      Uri.parse('https://api.nipino-manabu.com/v1/challenge/finalize'),
      headers: {'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token'},
      body: jsonEncode({'event_id': eventId}),
    );
    if (!mounted) return;
    final b = jsonDecode(res.body);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(b['message'] ?? 'Done'),
          behavior: SnackBarBehavior.floating));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Finalize challenge')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(
              color: AppColors.red, strokeWidth: 2))
          : _events.isEmpty
              ? const Center(child: Text('No active challenges.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _events.length,
                  itemBuilder: (_, i) {
                    final e = _events[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: AppColors.bg,
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(8)),
                      child: Row(children: [
                        Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(e.title,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                          Text('${e.joinedCount} participants · '
                              '${e.prizeCoins} coins prize',
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.muted)),
                        ])),
                        ElevatedButton(
                          onPressed: () => _finalize(e.id, e.title),
                          style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8)),
                          child: const Text('Finalize'),
                        ),
                      ]),
                    );
                  }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Broadcast notification screen (admin)
// ─────────────────────────────────────────────────────────────────────────────
class BroadcastNotificationScreen extends StatefulWidget {
  const BroadcastNotificationScreen({super.key});
  @override State<BroadcastNotificationScreen> createState() =>
      _BroadcastNotificationScreenState();
}

class _BroadcastNotificationScreenState
    extends State<BroadcastNotificationScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Broadcast notification')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Use the invite-all endpoint via the challenge events screen, '
            'or call POST /v1/challenge/invite-all with an event_id.\n\n'
            'Direct FCM broadcast to all users is handled server-side '
            'through the challenge invite-all API.',
            style: TextStyle(color: AppColors.muted, height: 1.6),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

// ─── Helper widgets ───────────────────────────────────────────────────────────
class _DropField extends StatelessWidget {
  final String label, value; final List<String> items;
  final ValueChanged<String?> onChanged;
  const _DropField({required this.label, required this.value,
      required this.items, required this.onChanged});
  @override Widget build(BuildContext context) => DropdownButtonFormField<String>(
    value: value, decoration: InputDecoration(labelText: label),
    items: items.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
    onChanged: onChanged,
  );
}

class _SliderField extends StatelessWidget {
  final String label; final double value, min, max; final int divisions;
  final ValueChanged<double> onChanged;
  const _SliderField({required this.label, required this.value,
      required this.min, required this.max, required this.divisions,
      required this.onChanged});
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: const TextStyle(
            fontSize: 13, color: AppColors.muted)),
        const Spacer(),
        Text(value.round().toString(), style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700)),
      ]),
      Slider.adaptive(value: value, min: min, max: max,
          divisions: divisions, activeColor: AppColors.red,
          onChanged: onChanged),
    ]),
  );
}
