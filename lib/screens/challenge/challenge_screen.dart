// lib/screens/challenge/challenge_screen.dart
// ─── Admin challenge events: browse, join, timed quiz, results ───────────────
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../models/social_models.dart';
import '../../models/models.dart';
import '../../services/social_api_service.dart';
import '../../services/api_service.dart';
import '../../services/auth_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Challenge list hub
// ─────────────────────────────────────────────────────────────────────────────
class ChallengeHubScreen extends StatefulWidget {
  const ChallengeHubScreen({super.key});
  @override State<ChallengeHubScreen> createState() =>
      _ChallengeHubScreenState();
}

class _ChallengeHubScreenState extends State<ChallengeHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  List<ChallengeEvent> _active   = [];
  List<ChallengeEvent> _upcoming = [];
  List<ChallengeEvent> _finished = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      SocialApiService.listChallenges('active'),
      SocialApiService.listChallenges('upcoming'),
      SocialApiService.listChallenges('finished'),
    ]);
    if (mounted) {
      setState(() {
        _active   = results[0].data ?? [];
        _upcoming = results[1].data ?? [];
        _finished = results[2].data ?? [];
        _loading  = false;
      });
    }
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Challenges'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.red,
          unselectedLabelColor: AppColors.muted,
          indicatorColor: AppColors.red,
          tabs: [
            Tab(text: 'Live (${_active.length})'),
            Tab(text: 'Upcoming (${_upcoming.length})'),
            Tab(text: 'Finished'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(
              color: AppColors.red, strokeWidth: 2))
          : TabBarView(
              controller: _tabs,
              children: [
                _ChallengeList(events: _active,   onRefresh: _load),
                _ChallengeList(events: _upcoming, onRefresh: _load),
                _ChallengeList(events: _finished, onRefresh: _load),
              ],
            ),
    );
  }
}

class _ChallengeList extends StatelessWidget {
  final List<ChallengeEvent> events;
  final Future<void> Function() onRefresh;
  const _ChallengeList({required this.events, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Center(
        child: Text('No challenges here yet.',
            style: TextStyle(color: AppColors.muted)));
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.red,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: events.length,
        itemBuilder: (_, i) => _ChallengeCard(
          event: events[i],
          onTap: () => Navigator.push(context,
              MaterialPageRoute(
                  builder: (_) => ChallengeDetailScreen(event: events[i])))
            .then((_) => onRefresh()),
        ),
      ),
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  final ChallengeEvent event;
  final VoidCallback onTap;
  const _ChallengeCard({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isLive     = event.status == 'active';
    final isFinished = event.status == 'finished';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.bg,
          border: Border(
            left: BorderSide(
              color: isLive
                  ? AppColors.red
                  : isFinished
                      ? AppColors.green
                      : AppColors.muted2,
              width: 4),
            top:    const BorderSide(color: AppColors.border),
            right:  const BorderSide(color: AppColors.border),
            bottom: const BorderSide(color: AppColors.border),
          ),
          borderRadius: const BorderRadius.only(
            topRight:    Radius.circular(8),
            bottomRight: Radius.circular(8)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(event.title,
                  style: const TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w700, color: AppColors.ink))),
              if (isLive) Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: AppColors.red, borderRadius: BorderRadius.circular(3)),
                child: const Text('LIVE',
                    style: TextStyle(color: Colors.white, fontSize: 10,
                        fontWeight: FontWeight.w700, letterSpacing: 0.5))),
              if (isFinished && event.prizeBadgeEmoji != null)
                Text(event.prizeBadgeEmoji!, style: const TextStyle(fontSize: 20)),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              _Tag(label: event.level, color: AppTheme.levelColor(event.level)),
              const SizedBox(width: 6),
              _Tag(label: '🪙 ${event.prizeCoins}', color: AppColors.gold),
              const SizedBox(width: 6),
              _Tag(label: '⏱ ${event.secondsPerQ}s/Q', color: AppColors.muted),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.people_outline, size: 14, color: AppColors.muted),
              const SizedBox(width: 4),
              Text('${event.joinedCount}/${event.maxParticipants} joined',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted)),
              const Spacer(),
              if (isFinished && event.winnerUsername != null)
                Text('🏆 ${event.winnerUsername}',
                    style: const TextStyle(fontSize: 11,
                        fontWeight: FontWeight.w600, color: AppColors.green)),
              if (!isFinished) Text(
                isLive
                    ? 'Ends ${_timeLeft(event.endsAt)}'
                    : 'Starts ${_timeLeft(event.startsAt)}',
                style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            ]),
            if (event.userCompleted) ...[
              const SizedBox(height: 6),
              const Row(children: [
                Icon(Icons.check_circle, size: 14, color: AppColors.green),
                SizedBox(width: 4),
                Text('You submitted', style: TextStyle(
                    fontSize: 11, color: AppColors.green)),
              ]),
            ],
          ]),
        ),
      ),
    );
  }

  String _timeLeft(String isoStr) {
    final dt = DateTime.tryParse(isoStr);
    if (dt == null) return '';
    final diff = dt.difference(DateTime.now());
    if (diff.isNegative) return 'ended';
    if (diff.inDays > 0) return 'in ${diff.inDays}d';
    if (diff.inHours > 0) return 'in ${diff.inHours}h';
    return 'in ${diff.inMinutes}m';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Challenge detail + join + leaderboard
// ─────────────────────────────────────────────────────────────────────────────
class ChallengeDetailScreen extends StatefulWidget {
  final ChallengeEvent event;
  const ChallengeDetailScreen({super.key, required this.event});
  @override State<ChallengeDetailScreen> createState() =>
      _ChallengeDetailScreenState();
}

class _ChallengeDetailScreenState extends State<ChallengeDetailScreen> {
  late ChallengeEvent _event;
  List<ChallengeEntry> _leaderboard = [];
  bool _loadingLb  = false;
  bool _joining    = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _event = widget.event;
    _loadLeaderboard();
  }

  Future<void> _loadLeaderboard() async {
    setState(() => _loadingLb = true);
    final res = await SocialApiService.challengeLeaderboard(_event.id);
    if (mounted) {
      setState(() {
        _leaderboard = res.data ?? [];
        _loadingLb   = false;
      });
    }
  }

  Future<void> _join() async {
    setState(() { _joining = true; _error = null; });
    final res = await SocialApiService.joinChallenge(_event.id);
    if (!mounted) return;
    setState(() => _joining = false);
    if (res.success) {
      // Navigate to quiz
      Navigator.push(context, MaterialPageRoute(
          builder: (_) => ChallengeQuizScreen(event: _event)))
        .then((_) => _loadLeaderboard());
    } else {
      setState(() => _error = res.error ?? 'Failed to join challenge');
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId     = context.read<AuthProvider>().user?.id;
    final isLive   = _event.status == 'active';
    final canJoin  = isLive && !_event.userCompleted;

    return Scaffold(
      appBar: AppBar(
        title: Text(_event.title),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1), child: Divider(height: 1)),
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [

          // Prize banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.goldLight,
              border: Border.all(color: const Color(0xFFE8C56A)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              Text(
                _event.prizeBadgeEmoji ?? '🏆',
                style: const TextStyle(fontSize: 36)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Prize: ${_event.prizeCoins} coins',
                    style: const TextStyle(fontSize: 16,
                        fontWeight: FontWeight.w700, color: const Color(0xFFE88C00))),
                if (_event.prizeBadgeEmoji != null)
                  const Text('+ Exclusive winner badge',
                      style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ])),
            ]),
          ),
          const SizedBox(height: 14),

          // Details grid
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: AppColors.bg2,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(8)),
            child: Column(children: [
              _DetailRow('Level',     _event.level),
              _DetailRow('Category',  _event.category),
              _DetailRow('Questions', '${_event.questionCount}'),
              _DetailRow('Timer',     '${_event.secondsPerQ}s per question'),
              _DetailRow('Joined',    '${_event.joinedCount}/${_event.maxParticipants}'),
              _DetailRow('Status',    _event.status.toUpperCase()),
            ]),
          ),
          const SizedBox(height: 14),

          if (_event.description.isNotEmpty) ...[
            Text(_event.description,
                style: const TextStyle(fontSize: 13,
                    color: AppColors.muted, height: 1.6)),
            const SizedBox(height: 14),
          ],

          // Winner featured card
          if (_event.status == 'finished' && _event.winnerUsername != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.greenLight,
                border: const Border(
                    left: BorderSide(color: AppColors.green, width: 4)),
                borderRadius: const BorderRadius.only(
                    topRight:    Radius.circular(8),
                    bottomRight: Radius.circular(8)),
              ),
              child: Row(children: [
                const Icon(Icons.emoji_events,
                    color: AppColors.green, size: 28),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Challenge winner',
                      style: TextStyle(fontSize: 11,
                          color: AppColors.green, fontWeight: FontWeight.w600,
                          letterSpacing: 0.4)),
                  Text(_event.winnerUsername!,
                      style: const TextStyle(fontSize: 16,
                          fontWeight: FontWeight.w700, color: AppColors.green)),
                ]),
              ]),
            ),
            const SizedBox(height: 14),
          ],

          // Error
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: AppColors.redLight,
                  border: const Border(
                      left: BorderSide(color: AppColors.red, width: 3)),
                  borderRadius: BorderRadius.circular(4)),
              child: Text(_error!, style: const TextStyle(
                  color: AppColors.red, fontSize: 13))),
            const SizedBox(height: 12),
          ],

          // CTA
          if (canJoin)
            ElevatedButton.icon(
              onPressed: _joining ? null : _join,
              icon: _joining
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.play_arrow, size: 18),
              label: const Text('Enter challenge'),
            )
          else if (_event.userCompleted)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: AppColors.greenLight,
                  border: Border.all(color: AppColors.green),
                  borderRadius: BorderRadius.circular(6)),
              child: const Row(children: [
                Icon(Icons.check_circle, color: AppColors.green, size: 18),
                SizedBox(width: 8),
                Text('You have completed this challenge',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.green,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          const SizedBox(height: 24),

          // Leaderboard
          _SectionTag(label: 'LEADERBOARD'),
          const SizedBox(height: 10),
          if (_loadingLb)
            const Center(child: CircularProgressIndicator(
                color: AppColors.red, strokeWidth: 2))
          else if (_leaderboard.isEmpty)
            const Center(child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No submissions yet.',
                  style: TextStyle(color: AppColors.muted))))
          else
            ..._leaderboard.take(20).map((e) =>
                _LeaderRow(entry: e, myId: myId)),
        ]),
      ),
    );
  }
}

class _LeaderRow extends StatelessWidget {
  final ChallengeEntry entry;
  final int? myId;
  const _LeaderRow({required this.entry, required this.myId});

  @override
  Widget build(BuildContext context) {
    final isMe = entry.userId == myId;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isMe ? AppColors.redLight : AppColors.bg,
        border: Border(
          left: BorderSide(
              color: isMe ? AppColors.red : Colors.transparent, width: 3),
          top:    const BorderSide(color: AppColors.border),
          right:  const BorderSide(color: AppColors.border),
          bottom: const BorderSide(color: AppColors.border),
        ),
        borderRadius: const BorderRadius.only(
            topRight:    Radius.circular(6),
            bottomRight: Radius.circular(6)),
      ),
      child: Row(children: [
        SizedBox(width: 22,
            child: Text('#${entry.rank ?? '?'}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                    color: (entry.rank ?? 99) <= 3
                        ? AppColors.gold : AppColors.muted),
                textAlign: TextAlign.center)),
        const SizedBox(width: 10),
        CircleAvatar(
          radius: 16,
          backgroundColor: isMe ? AppColors.red : AppColors.muted2,
          child: Text(entry.username[0].toUpperCase(),
              style: const TextStyle(color: Colors.white, fontSize: 12))),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(isMe ? 'You' : entry.username,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                  color: isMe ? AppColors.red : AppColors.ink)),
          Text('${entry.correctCount} correct · '
              '${(entry.timeTakenMs / 1000).toStringAsFixed(1)}s',
              style: const TextStyle(fontSize: 10, color: AppColors.muted)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${entry.score}',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                  color: isMe ? AppColors.red : AppColors.ink)),
          if (entry.coinsAwarded > 0)
            Text('+${entry.coinsAwarded} 🪙',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.gold,
                    fontWeight: FontWeight.w600)),
        ]),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Challenge quiz — always timed, submits on last question
// ─────────────────────────────────────────────────────────────────────────────
class ChallengeQuizScreen extends StatefulWidget {
  final ChallengeEvent event;
  const ChallengeQuizScreen({super.key, required this.event});
  @override State<ChallengeQuizScreen> createState() =>
      _ChallengeQuizScreenState();
}

class _ChallengeQuizScreenState extends State<ChallengeQuizScreen> {
  List<QuizQuestion> _questions = [];
  List<int?> _chosenIndices = [];
  int     _currentQ     = 0;
  int?    _selected;
  bool    _revealed     = false;
  int     _correctCount = 0;
  int     _secondsLeft  = 0;
  int     _totalMs      = 0;
  int     _qStartMs     = 0;
  Timer?  _timer;
  bool    _loading      = true;
  bool    _submitting   = false;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    final res = await ApiService.getQuestions(
      level: widget.event.level,
      category: widget.event.category,
      count: widget.event.questionCount,
    );
    if (!mounted) return;
    if (res.success) {
      setState(() {
        _questions   = res.data!;
        _chosenIndices = List<int?>.filled(_questions.length, null);
        _loading     = false;
        _secondsLeft = widget.event.secondsPerQ;
        _qStartMs    = DateTime.now().millisecondsSinceEpoch;
      });
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _secondsLeft = widget.event.secondsPerQ;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        t.cancel();
        if (!_revealed) _pickAnswer(null); // timeout
      }
    });
  }

  Future<void> _pickAnswer(int? chosen) async {
    if (_revealed) return;
    _timer?.cancel();

    final elapsed = DateTime.now().millisecondsSinceEpoch - _qStartMs;
    _totalMs     += elapsed;

    final q         = _questions[_currentQ];
    final isCorrect = chosen != null && chosen == q.correctIndex;
    if (isCorrect) _correctCount++;
    _chosenIndices[_currentQ] = chosen;

    setState(() { _selected = chosen; _revealed = true; });

    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;

    if (_currentQ + 1 >= _questions.length) {
      // All done — submit
      await _submit();
      return;
    }

    setState(() {
      _currentQ++;
      _selected    = null;
      _revealed    = false;
      _qStartMs    = DateTime.now().millisecondsSinceEpoch;
    });
    _startTimer();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final answers = [
      for (var i = 0; i < _questions.length; i++)
        {'question_id': _questions[i].id, 'chosen_index': _chosenIndices[i]},
    ];
    await SocialApiService.submitChallengeResult(
      eventId:     widget.event.id,
      answers:     answers,
      timeTakenMs: _totalMs,
    );
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (_) => ChallengeResultScreen(
        event:        widget.event,
        correctCount: _correctCount,
        totalCount:   _questions.length,
        timeTakenMs:  _totalMs,
      ),
    ));
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator(
              color: AppColors.red, strokeWidth: 2)));
    }

    final q        = _questions[_currentQ];
    final total    = _questions.length;
    final timeRatio = _secondsLeft / widget.event.secondsPerQ;
    final isUrgent  = _secondsLeft <= 5;

    return WillPopScope(
      onWillPop: () async => false, // prevent back during quiz
      child: Scaffold(
        body: SafeArea(
          child: Column(children: [
            // Header + timer
            Container(
              color: AppColors.red,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Column(children: [
                Row(children: [
                  Expanded(child: Text(widget.event.title,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis)),
                  // Timer pill
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: isUrgent
                          ? Colors.white
                          : Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.timer,
                          size: 15,
                          color: isUrgent ? AppColors.red : Colors.white),
                      const SizedBox(width: 4),
                      Text('$_secondsLeft',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isUrgent ? AppColors.red : Colors.white)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 8),
                // Timer bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: timeRatio.clamp(0.0, 1.0),
                    backgroundColor: Colors.white.withOpacity(0.25),
                    valueColor: AlwaysStoppedAnimation<Color>(
                        isUrgent ? Colors.yellow : Colors.white),
                    minHeight: 6,
                  ),
                ),
              ]),
            ),

            // Progress
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              color: AppColors.bg2,
              child: Row(children: [
                Text('Q${_currentQ + 1} of $total',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.muted)),
                const Spacer(),
                Text('$_correctCount correct',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: AppColors.green)),
              ]),
            ),
            LinearProgressIndicator(
              value: (_currentQ + 1) / total,
              backgroundColor: AppColors.bg3,
              color: AppColors.red,
              minHeight: 3,
            ),

            Expanded(
              child: ListView(
                  padding: const EdgeInsets.all(16), children: [
                // Question card
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
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
                  child: Column(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: AppColors.redLight,
                          borderRadius: BorderRadius.circular(3)),
                      child: Text(
                          q.questionType.toUpperCase(),
                          style: const TextStyle(
                              color: AppColors.red, fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5))),
                    const SizedBox(height: 16),
                    Text(q.questionText,
                        style: const TextStyle(
                            fontFamily: 'NotoSansJP', fontSize: 48,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 10),
                    const Text(
                        'Choose the correct answer',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.muted)),
                  ]),
                ),
                const SizedBox(height: 14),

                // Options 2×2 grid
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.6,
                  children: List.generate(q.options.length, (i) {
                    Color borderColor = AppColors.border;
                    Color bgColor     = AppColors.bg;
                    Color textColor   = AppColors.ink;

                    if (_revealed) {
                      if (i == q.correctIndex) {
                        borderColor = AppColors.green;
                        bgColor     = AppColors.greenLight;
                        textColor   = AppColors.green;
                      } else if (i == _selected) {
                        borderColor = AppColors.red;
                        bgColor     = AppColors.redLight;
                        textColor   = AppColors.red;
                      }
                    }

                    return GestureDetector(
                      onTap: _revealed ? null : () => _pickAnswer(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: bgColor,
                          border: Border.all(
                              color: borderColor, width: 1.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(q.options[i],
                              style: TextStyle(
                                  fontFamily: 'NotoSansJP',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: textColor),
                              textAlign: TextAlign.center),
                        ),
                      ),
                    );
                  }),
                ),

                // Memory tip
                if (q.memoryTip != null && _revealed) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: AppColors.blueLight,
                        border: const Border(
                            left: BorderSide(
                                color: AppColors.blue, width: 3)),
                        borderRadius: const BorderRadius.only(
                            topRight:    Radius.circular(6),
                            bottomRight: Radius.circular(6))),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Text('MEMORY TIP',
                          style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w700,
                              color: AppColors.blue, letterSpacing: 0.4)),
                      const SizedBox(height: 4),
                      Text(q.memoryTip!,
                          style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF1E3A6E),
                              height: 1.5)),
                    ]),
                  ),
                ],
              ]),
            ),

            if (_submitting)
              const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(
                    color: AppColors.red, strokeWidth: 2)),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Challenge result screen
// ─────────────────────────────────────────────────────────────────────────────
class ChallengeResultScreen extends StatelessWidget {
  final ChallengeEvent event;
  final int correctCount;
  final int totalCount;
  final int timeTakenMs;
  const ChallengeResultScreen({
    super.key,
    required this.event,
    required this.correctCount,
    required this.totalCount,
    required this.timeTakenMs,
  });

  @override
  Widget build(BuildContext context) {
    final pct      = (correctCount / totalCount * 100).round();
    final timeSec  = (timeTakenMs / 1000).toStringAsFixed(1);

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          // Hero
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
            color: AppColors.red,
            child: Column(children: [
              const Icon(Icons.star, size: 48, color: Colors.white),
              const SizedBox(height: 10),
              const Text('Submitted!',
                  style: TextStyle(fontSize: 22,
                      fontWeight: FontWeight.w700, color: Colors.white)),
              Text('${event.title}',
                  style: const TextStyle(
                      fontSize: 13, color: Colors.white70)),
            ]),
          ),

          Expanded(
            child: ListView(
                padding: const EdgeInsets.all(16), children: [
              // Score ring
              Center(
                child: Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: AppColors.red, width: 4),
                    color: Colors.white,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('$pct%',
                          style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink)),
                      const Text('Score',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.muted)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Info box
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: AppColors.bg2,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(8)),
                child: Column(children: [
                  _InfoLine('Correct', '$correctCount / $totalCount'),
                  _InfoLine('Time',    '${timeSec}s'),
                  _InfoLine('Prize',   '${event.prizeCoins} 🪙 (for winner)'),
                ]),
              ),
              const SizedBox(height: 16),

              // Awaiting result notice
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: AppColors.goldLight,
                    border: const Border(
                        left: BorderSide(
                            color: AppColors.gold, width: 3)),
                    borderRadius: const BorderRadius.only(
                        topRight:    Radius.circular(6),
                        bottomRight: Radius.circular(6))),
                child: const Text(
                  'The final winner is announced by the admin once the '
                  'challenge ends. Check the leaderboard tab to see your '
                  'position. The winner is featured on the home screen.',
                  style: TextStyle(
                      fontSize: 12, color: const Color(0xFFE88C00),
                      height: 1.6)),
              ),
              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: () => Navigator.pushNamedAndRemoveUntil(
                    context, '/home', (_) => false),
                child: const Text('Back to home'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.pushReplacement(context,
                    MaterialPageRoute(
                        builder: (_) => ChallengeDetailScreen(
                            event: event))),
                child: const Text('View leaderboard'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label, value;
  const _InfoLine(this.label, this.value);
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: [
      Text(label, style: const TextStyle(
          fontSize: 12, color: AppColors.muted)),
      const Spacer(),
      Text(value, style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w700,
          color: AppColors.ink)),
    ]),
  );
}

// ─── Shared widgets ───────────────────────────────────────────────────────────
class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  const _Tag({required this.label, required this.color});
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4)),
    child: Text(label,
        style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w600, color: color)),
  );
}

class _DetailRow extends StatelessWidget {
  final String label, value;
  const _DetailRow(this.label, this.value);
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      SizedBox(width: 100,
          child: Text(label, style: const TextStyle(
              fontSize: 12, color: AppColors.muted))),
      Text(value, style: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w600,
          color: AppColors.ink)),
    ]),
  );
}

class _SectionTag extends StatelessWidget {
  final String label;
  const _SectionTag({required this.label});
  @override Widget build(BuildContext context) => Row(children: [
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
