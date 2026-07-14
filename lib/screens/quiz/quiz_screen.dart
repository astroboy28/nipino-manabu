// lib/screens/quiz/quiz_screen.dart  –  UPDATED with image + audio support
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../services/auth_provider.dart';
import '../../widgets/quiz_media_widget.dart';
import '../../services/sound_service.dart';
import 'result_screen.dart';

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});
  @override State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  QuizSession? _session;
  bool    _loading  = true;
  bool    _revealed = false;
  int?    _selected;
  int     _secondsLeft = 0;
  bool    _timedMode   = true;
  int     _secondsPerQ = 15;
  Timer?  _timer;
  int     _qStartMs    = 0;
  String? _error;
  bool    _outOfCoins  = false;
  final _sound = SoundService();

  @override
  void initState() {
    super.initState();
    _sound.init();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadQuestions());
  }

  Future<void> _loadQuestions() async {
    final args = ModalRoute.of(context)?.settings.arguments
        as Map<String, dynamic>? ?? {};
    final level    = args['level']    as String? ?? 'N5';
    final category = args['category'] as String? ?? 'kanji';

    final res = await ApiService.getQuestions(
        level: level, category: category, count: 10);
    if (!mounted) return;

    if (res.success && res.data != null && res.data!.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final timedMode   = prefs.getBool('quiz_timed_mode') ?? true;
      final secondsPerQ = prefs.getInt('quiz_seconds_per_q') ?? 15;
      setState(() {
        _session   = QuizSession(questions: res.data!);
        _loading   = false;
        _timedMode = timedMode;
        _secondsPerQ = secondsPerQ;
        _secondsLeft = secondsPerQ;
        _qStartMs  = DateTime.now().millisecondsSinceEpoch;
      });
      if (_timedMode) _startTimer();
    } else {
      setState(() {
        _loading = false;
        _error = res.error ?? 'No questions found.';
        _outOfCoins = res.statusCode == 402;
      });
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _secondsLeft = _secondsPerQ;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) { t.cancel(); if (!_revealed) _pickAnswer(null); }
    });
  }

  Future<void> _pickAnswer(int? chosen) async {
    if (_revealed || _session == null) return;
    _timer?.cancel();

    final elapsed = DateTime.now().millisecondsSinceEpoch - _qStartMs;
    _session!.totalMs += elapsed;

    final q         = _session!.current;
    final isCorrect = chosen != null && chosen == q.correctIndex;
    _session!.chosenIndices[_session!.currentIndex] = chosen;
    HapticFeedback.lightImpact();
    if (isCorrect) {
      _session!.correctCount++;
      _sound.playCorrect();
    } else if (chosen != null) {
      // Only play wrong sound if user actually selected an answer (not timeout)
      _sound.playWrong();
    }

    setState(() { _selected = chosen; _revealed = true; });
    if (q.isListening || q.questionType == 'grammar_fill') return;
    await Future.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;

    if (_session!.isLast) {
      // Submit and go to results
      await _submitResult();
      return;
    }

    _session!.currentIndex++;
    setState(() {
      _selected    = null;
      _revealed    = false;
      _qStartMs    = DateTime.now().millisecondsSinceEpoch;
      _secondsLeft = _secondsPerQ;
    });
    if (_timedMode) _startTimer();
  }

  Future<void> _nextQuestion() async {
  if (_session == null) return;
  if (_session!.isLast) {
    await _submitResult();
    return;
  }
  _session!.currentIndex++;
  setState(() {
    _selected = null;
    _revealed = false;
    _qStartMs = DateTime.now().millisecondsSinceEpoch;
    _secondsLeft = _secondsPerQ;
  });
  if (_timedMode) _startTimer();
}Future<void> _submitResult() async {
    final session = _session!;
    final submitRes = await ApiService.submitQuizResult(
      level:            session.questions.first.level,
      category:         session.questions.first.category,
      answers:          session.answersPayload,
      timeTakenSeconds: session.totalMs ~/ 1000,
    );
    if (submitRes.success && submitRes.data != null) {
      session.coinsEarned = (submitRes.data!['coins_earned'] as num?)?.toInt() ?? 0;
      session.coinsLost   = (submitRes.data!['coins_lost'] as num?)?.toInt() ?? 0;
    }
    await context.read<AuthProvider>().refreshUser();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/result', arguments: session);
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(
        body: Center(child: CircularProgressIndicator(
            color: AppColors.red, strokeWidth: 2)));

    if (_outOfCoins) return Scaffold(
        appBar: AppBar(title: const Text('Quiz')),
        body: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.monetization_on_outlined,
                size: 56, color: AppColors.gold),
            const SizedBox(height: 16),
            const Text("You're out of coins",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                    color: AppColors.ink)),
            const SizedBox(height: 8),
            Text(_error ?? 'Purchase more coins to keep taking quizzes.',
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.pushReplacementNamed(context, '/store'),
              icon: const Icon(Icons.add_shopping_cart, size: 18),
              label: const Text('Get more coins'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back'),
            ),
          ]),
        )));

    if (_error != null) return Scaffold(
        appBar: AppBar(title: const Text('Quiz')),
        body: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, style: const TextStyle(
              color: AppColors.muted, fontSize: 14)),
        )));

    final session = _session!;
    final q       = session.current;
    final total   = session.questions.length;
    final tRatio  = _timedMode ? _secondsLeft / _secondsPerQ : 1.0;
    final urgent  = _timedMode && _secondsLeft <= 5;

    return WillPopScope(
      onWillPop: () async {
        final leave = await showDialog<bool>(context: context,
          builder: (_) => AlertDialog(
            title: const Text('Leave quiz?'),
            content: const Text('Your progress will be lost.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false),
                  child: const Text('Stay')),
              ElevatedButton(onPressed: () => Navigator.pop(context, true),
                  child: const Text('Leave')),
            ],
          ));
        return leave == true;
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(children: [
            // ── Header bar ───────────────────────────────────────────────────
            Container(
              color: AppColors.red,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Column(children: [
                Row(children: [
                  Text('${q.level} · ${q.category}',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12)),
                  const Spacer(),
                  if (_timedMode) _TimerPill(
                      seconds: _secondsLeft, urgent: urgent),
                ]),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: session.progress,
                  backgroundColor: Colors.white.withOpacity(0.2),
                  color: Colors.white, minHeight: 4),
                const SizedBox(height: 4),
                if (_timedMode) LinearProgressIndicator(
                  value: tRatio.clamp(0.0, 1.0),
                  backgroundColor: Colors.white.withOpacity(0.15),
                  color: urgent ? Colors.yellow : Colors.white70,
                  minHeight: 3),
              ]),
            ),
            // Q counter
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 6),
              child: Row(children: [
                Text('Q${session.currentIndex + 1} of $total',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.muted)),
                const Spacer(),
                Text('${session.correctCount} correct',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: AppColors.green)),
              ]),
            ),

            Expanded(child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
              // ── Question type label ───────────────────────────────────────
              _TypeBadge(type: q.questionType),
              const SizedBox(height: 10),

              // ── AUDIO player (listening questions) ────────────────────────
              if (q.hasAudio) ...[
                QuizAudioWidget(
                    key: ValueKey('audio_${session.currentIndex}'),
                    url: q.audioUrl!, autoPlay: false),
                const SizedBox(height: 12),
              ],

              // ── IMAGE (image_reading / image_meaning questions) ───────────
              if (q.hasImage && !q.hasAudio) ...[
                QuizImageWidget(url: q.imageUrl!, credit: q.mediaCredit),
                const SizedBox(height: 12),
              ],

              // ── Question text card ────────────────────────────────────────
              // For listening questions, the card shows a mic icon instead
              // of large kanji so the audio is clearly the stimulus.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: AppColors.bg,
                  border: Border(
                      top:    BorderSide(color: AppColors.red, width: 3),
                      left:   BorderSide(color: AppColors.border),
                      right:  BorderSide(color: AppColors.border),
                      bottom: BorderSide(color: AppColors.border)),
                  borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(8),
                      bottomRight: Radius.circular(8)),
                ),
                child: q.isListening
                    ? const Column(children: [
                        Icon(Icons.hearing, size: 52, color: AppColors.red),
                        SizedBox(height: 6),
                        Text('What did you hear?',
                            style: TextStyle(fontSize: 15,
                                color: AppColors.muted)),
                      ])
                    : Text(q.questionText,
                        style: TextStyle(
                            fontFamily: 'NotoSansJP', fontSize: q.questionType == 'grammar_fill' || q.isListening ? 18.0 : 48.0,
                            fontWeight: FontWeight.w700, color: AppColors.ink),
                        textAlign: TextAlign.center),
              ),
              const SizedBox(height: 14),

              // ── Options grid ──────────────────────────────────────────────
              // -- Options ----------------------------------------------------------
              if (q.isListening || q.questionType == 'grammar_fill')
                Column(
                  children: List.generate(q.options.length, (i) {
                    Color border = AppColors.border;
                    Color bg     = AppColors.bg;
                    Color text   = AppColors.ink;
                    Color labelBg = AppColors.bg3;
                    Color labelText = AppColors.muted;
                    if (_revealed) {
                      if (i == q.correctIndex) {
                        border = AppColors.green; bg = AppColors.greenLight;
                        text = AppColors.green; labelBg = AppColors.green;
                        labelText = Colors.white;
                      } else if (i == _selected) {
                        border = AppColors.red; bg = AppColors.redLight;
                        text = AppColors.red; labelBg = AppColors.red;
                        labelText = Colors.white;
                      }
                    }
                    return GestureDetector(
                      onTap: _revealed ? null : () => _pickAnswer(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                            color: bg,
                            border: Border.all(color: border, width: 1.5),
                            borderRadius: BorderRadius.circular(8)),
                        child: Row(children: [
                          Container(
                            width: 26, height: 26,
                            decoration: BoxDecoration(
                                color: labelBg,
                                borderRadius: BorderRadius.circular(4)),
                            child: Center(child: Text(
                                ['A','B','C','D'][i],
                                style: TextStyle(fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: labelText))),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Text(q.options[i],
                              style: TextStyle(
                                  fontFamily: 'NotoSansJP', fontSize: 14,
                                  fontWeight: FontWeight.w600, color: text))),
                        ]),
                      ),
                    );
                  }),
                )
              else
                GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8, crossAxisSpacing: 8,
                childAspectRatio: 1.7,
                children: List.generate(q.options.length, (i) {
                  Color border = AppColors.border;
                  Color bg     = AppColors.bg;
                  Color text   = AppColors.ink;
                  if (_revealed) {
                    if (i == q.correctIndex) {
                      border = AppColors.green; bg = AppColors.greenLight;
                      text = AppColors.green;
                    } else if (i == _selected) {
                      border = AppColors.red; bg = AppColors.redLight;
                      text = AppColors.red;
                    }
                  }
                  return GestureDetector(
                    onTap: _revealed ? null : () => _pickAnswer(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: bg,
                          border: Border.all(color: border, width: 1.5),
                          borderRadius: BorderRadius.circular(8)),
                      child: Center(child: Text(q.options[i],
                          style: TextStyle(
                              fontFamily: 'NotoSansJP', fontSize: 16,
                              fontWeight: FontWeight.w700, color: text),
                          textAlign: TextAlign.center)),
                    ),
                  );
                }),
              ),


              // Next button for listening and grammar
              if (_revealed && (_session!.current.isListening || _session!.current.questionType == 'grammar_fill')) ...[
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: _nextQuestion,
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: const Text('Next Question'),
                ),
              ],

              // ── Memory tip (shown after answer revealed) ──────────────────
              if (_revealed && _selected != null && q.memoryTip != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: AppColors.blueLight,
                      border: const Border(
                          left: BorderSide(color: AppColors.blue, width: 3)),
                      borderRadius: const BorderRadius.only(
                          topRight:    Radius.circular(6),
                          bottomRight: Radius.circular(6))),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('MEMORY TIP',
                        style: TextStyle(fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.blue, letterSpacing: 0.4)),
                    const SizedBox(height: 4),
                    Text(q.memoryTip!,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF1E3A6E),
                            height: 1.5)),
                  ]),
                ),
              ],
            ])),
          ]),
        ),
      ),
    );
  }
}

class _TimerPill extends StatelessWidget {
  final int seconds; final bool urgent;
  const _TimerPill({required this.seconds, required this.urgent});
  @override Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 300),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
        color: urgent ? Colors.white : Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.timer, size: 14,
          color: urgent ? AppColors.red : Colors.white),
      const SizedBox(width: 4),
      Text('$seconds',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
              color: urgent ? AppColors.red : Colors.white)),
    ]),
  );
}

class _TypeBadge extends StatelessWidget {
  final String type;
  const _TypeBadge({required this.type});
  static const _labels = {
    'reading':       'Reading',
    'meaning':       'Meaning',
    'grammar_fill':  'Grammar',
    'listening':     'Listening',
    'image_reading': 'Image — Reading',
    'image_meaning': 'Image — Meaning',
  };
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
        color: AppColors.redLight, borderRadius: BorderRadius.circular(4)),
    child: Text((_labels[type] ?? type).toUpperCase(),
        style: const TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700,
            color: AppColors.red, letterSpacing: 0.5)),
  );
}
