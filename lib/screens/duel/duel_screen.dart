// lib/screens/duel/duel_screen.dart
// ─── Full duel flow: create/join lobby → live timed quiz → results ───────────
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../models/social_models.dart';
import '../../models/models.dart';
import '../../services/social_api_service.dart';
import '../../services/api_service.dart';
import '../../services/auth_provider.dart';
import '../../services/sound_service.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Duel hub: create or browse rooms
// ─────────────────────────────────────────────────────────────────────────────
class DuelHubScreen extends StatefulWidget {
  const DuelHubScreen({super.key});
  @override State<DuelHubScreen> createState() => _DuelHubScreenState();
}

class _DuelHubScreenState extends State<DuelHubScreen> {
  List<OpenDuelRoom> _openRooms = [];
  bool _loading = true;

  @override void initState() { super.initState(); _loadRooms(); }

  Future<void> _loadRooms() async {
    setState(() => _loading = true);
    final res = await SocialApiService.listOpenDuels();
    if (mounted) setState(() { _openRooms = res.data ?? []; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Duels'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1), child: Divider(height: 1)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Create duel',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CreateDuelScreen()))
              .then((_) => _loadRooms()),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadRooms, color: AppColors.red,
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.red, strokeWidth: 2))
              : _openRooms.isEmpty
                  ? _EmptyState(
                      icon: Icons.sports_esports_outlined,
                      message: 'No open duels right now',
                      action: 'Create one',
                      onAction: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const CreateDuelScreen()))
                        .then((_) => _loadRooms()),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _openRooms.length,
                      itemBuilder: (_, i) => _OpenRoomCard(
                        room: _openRooms[i],
                        onJoin: () => _joinRoom(_openRooms[i]),
                      ),
                    ),
        ),
      ),
    );
  }

  Future<void> _joinRoom(OpenDuelRoom room) async {
    final sound = SoundService();
    await sound.init();
    HapticFeedback.mediumImpact();
    final res = await SocialApiService.joinDuel(room.uuid);
    if (!mounted) return;
    if (res.success && res.data != null) {
      sound.playTap();
      Navigator.push(context,
        MaterialPageRoute(builder: (_) => DuelLobbyScreen(roomUuid: room.uuid)));
    } else {
      sound.playWrong();
      _showError(res.error ?? 'Failed to join duel');
    }
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: AppColors.red,
        behavior: SnackBarBehavior.floating));
}

// ─────────────────────────────────────────────────────────────────────────────
// Create duel room form
// ─────────────────────────────────────────────────────────────────────────────
class CreateDuelScreen extends StatefulWidget {
  const CreateDuelScreen({super.key});
  @override State<CreateDuelScreen> createState() => _CreateDuelScreenState();
}

class _CreateDuelScreenState extends State<CreateDuelScreen> {
  String _level      = 'N3';
  String _category   = 'kanji';
  int    _coinBet    = 50;
  int    _maxPlayers = 2;
  bool   _timedMode  = true;
  int    _secondsPerQ= 15;
  int    _questionCnt= 10;
  bool   _loading    = false;
  String? _error;

  Future<void> _create() async {
    final user = context.read<AuthProvider>().user;
    if ((user?.coins ?? 0) < _coinBet) {
      setState(() => _error = 'Not enough coins. You have ${user?.coins ?? 0}.'); return;
    }
    setState(() { _loading = true; _error = null; });
    final res = await SocialApiService.createDuel(
      level: _level, category: _category, coinBet: _coinBet,
      maxPlayers: _maxPlayers, timedMode: _timedMode,
      secondsPerQ: _secondsPerQ, questionCount: _questionCnt,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (res.success) {
      final uuid = res.data!['room_uuid'] as String;
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => DuelLobbyScreen(roomUuid: uuid)));
    } else {
      setState(() => _error = res.error ?? 'Failed to create room');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return Scaffold(
      appBar: AppBar(title: const Text('Create duel'),
          bottom: const PreferredSize(
              preferredSize: Size.fromHeight(1), child: Divider(height: 1))),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          // Coins info
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.goldLight,
                border: Border.all(color: const Color(0xFFE8C56A)),
                borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              const Icon(Icons.monetization_on, color: AppColors.gold, size: 20),
              const SizedBox(width: 10),
              Text('Your balance: ${user?.coins ?? 0} coins',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                      color: const Color(0xFFE88C00))),
            ]),
          ),
          const SizedBox(height: 20),

          if (_error != null) ...[
            Container(padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.redLight,
                    border: const Border(left: BorderSide(color: AppColors.red, width: 3)),
                    borderRadius: BorderRadius.circular(4)),
                child: Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 13))),
            const SizedBox(height: 16),
          ],

          _SectionLabel('Quiz settings'),
          _PickRow(label: 'Level', value: _level,
              options: ['N5','N4','N3','N2','N1'],
              onChanged: (v) => setState(() => _level = v)),
          _PickRow(label: 'Category', value: _category,
              options: ['kanji','vocabulary','grammar','listening'],
              onChanged: (v) => setState(() => _category = v)),
          _SliderRow(label: 'Questions', value: _questionCnt.toDouble(),
              min: 5, max: 20, divisions: 15,
              onChanged: (v) => setState(() => _questionCnt = v.round())),

          _SectionLabel('Duel settings'),
          _PickRow(label: 'Max players', value: '$_maxPlayers',
              options: ['2','3'],
              onChanged: (v) => setState(() => _maxPlayers = int.parse(v))),
          _SliderRow(label: 'Coin bet', value: _coinBet.toDouble(),
              min: 10, max: 500, divisions: 49,
              suffix: ' 🪙',
              onChanged: (v) => setState(() => _coinBet = v.round())),

          _SectionLabel('Timer'),
          SwitchListTile.adaptive(
            value: _timedMode,
            activeColor: AppColors.red,
            title: const Text('Timed mode', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            subtitle: Text(_timedMode ? 'Each question has a countdown' : 'Take your time',
                style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            onChanged: (v) => setState(() => _timedMode = v),
            contentPadding: EdgeInsets.zero,
          ),
          if (_timedMode) _SliderRow(
              label: 'Seconds per question', value: _secondsPerQ.toDouble(),
              min: 5, max: 60, divisions: 11,
              suffix: 's',
              onChanged: (v) => setState(() => _secondsPerQ = v.round())),

          const SizedBox(height: 8),
          Container(padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.redLight,
                  border: const Border(left: BorderSide(color: AppColors.red, width: 3)),
                  borderRadius: BorderRadius.circular(4)),
              child: Text(
                'Entry fee: $_coinBet coins × $_maxPlayers players = '
                '${(_coinBet * _maxPlayers * 0.95).round()} coins pot (5% house cut)',
                style: const TextStyle(fontSize: 12, color: AppColors.red))),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _loading ? null : _create,
            child: _loading
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text('Create & bet $_coinBet coins'),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Duel lobby — waiting room
// ─────────────────────────────────────────────────────────────────────────────
class DuelLobbyScreen extends StatefulWidget {
  final String roomUuid;
  const DuelLobbyScreen({super.key, required this.roomUuid});
  @override State<DuelLobbyScreen> createState() => _DuelLobbyScreenState();
}

class _DuelLobbyScreenState extends State<DuelLobbyScreen> {
  DuelRoomState? _state;
  bool _loading  = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _poll();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  Future<void> _poll() async {
    final res = await SocialApiService.getDuelRoom(widget.roomUuid);
    if (!mounted) return;
    if (res.success) {
      setState(() { _state = res.data; _loading = false; });
      if (_state!.room.status == 'active') {
        _pollTimer?.cancel();
        _navigateToQuiz();
      }
    }
  }

  void _navigateToQuiz() {
    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (_) => DuelQuizScreen(roomState: _state!),
    ));
  }

  Future<void> _markReady() async {
    await SocialApiService.markReady(_state!.room.id);
    _poll();
  }

  Future<void> _inviteUser() async {
    // Show user search dialog
    final result = await showDialog<int>(
      context: context,
      builder: (_) => const _UserSearchDialog(),
    );
    if (result != null && mounted) {
      await SocialApiService.inviteUserToDuel(
        roomId: _state!.room.id, inviteeId: result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invitation sent!'),
              behavior: SnackBarBehavior.floating));
      }
    }
  }

  @override
  void dispose() { _pollTimer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final room = _state?.room;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Duel lobby'),
        bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1), child: Divider(height: 1)),
        actions: [
          if (room != null)
            IconButton(
              icon: const Icon(Icons.person_add_outlined),
              tooltip: 'Invite player',
              onPressed: _inviteUser,
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.red, strokeWidth: 2))
            : _state == null ? const Center(child: Text('Room not found'))
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Room info card
                    _InfoCard(room: _state!.room),
                    const SizedBox(height: 20),

                    // Invite link
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: AppColors.bg2,
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(8)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Share this link',
                            style: TextStyle(fontSize: 12, color: AppColors.muted)),
                        const SizedBox(height: 4),
                        SelectableText(
                          'nipinomanabu://duel/${_state!.room.uuid}',
                          style: const TextStyle(
                              fontSize: 13, fontFamily: 'monospace', color: AppColors.ink)),
                      ]),
                    ),
                    const SizedBox(height: 20),

                    // Players
                    const Text('Players', style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink)),
                    const SizedBox(height: 8),
                    ...(_state!.participants.map((p) => _ParticipantRow(participant: p))),

                    // Waiting indicator
                    if (room!.status == 'waiting') ...[
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(
                          color: AppColors.red, backgroundColor: AppColors.bg3),
                      const SizedBox(height: 6),
                      Text(
                        '${_state!.participants.length}/${room.maxPlayers} players joined — '
                        'waiting for all to be ready',
                        style: const TextStyle(fontSize: 12, color: AppColors.muted),
                        textAlign: TextAlign.center,
                      ),
                    ],

                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: _markReady,
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('Ready — start duel!'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () async {
                        // This used to just pop the screen — the label promises
                        // a refund, but SocialApiService.forfeitDuel() (which
                        // exists for exactly this) was never actually called.
                        final roomId = _state?.room.id;
                        if (roomId != null) {
                          await SocialApiService.forfeitDuel(roomId);
                        }
                        if (mounted) Navigator.pop(context);
                      },
                      child: const Text('Leave lobby (coins refunded if not started)'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live duel quiz with countdown timer
// ─────────────────────────────────────────────────────────────────────────────
class DuelQuizScreen extends StatefulWidget {
  final DuelRoomState roomState;
  const DuelQuizScreen({super.key, required this.roomState});
  @override State<DuelQuizScreen> createState() => _DuelQuizScreenState();
}

class _DuelQuizScreenState extends State<DuelQuizScreen>
    with SingleTickerProviderStateMixin {
  int     _currentQ    = 0;
  int?    _selected;
  bool    _revealed    = false;
  int     _secondsLeft = 0;
  Timer?  _timer;
  Timer?  _pollTimer;
  int     _answerStartMs = 0;
  bool    _duelFinished  = false;
  bool?   _lastAnswerCorrect;
  DuelRoomState? _latestState;

  @override
  void initState() {
    super.initState();
    _latestState = widget.roomState;
    _secondsLeft = widget.roomState.room.secondsPerQ;
    _answerStartMs = DateTime.now().millisecondsSinceEpoch;
    if (widget.roomState.room.timedMode) _startTimer();
    // Poll for opponent progress every 2s
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollState());
  }

  void _startTimer() {
    _timer?.cancel();
    _secondsLeft = widget.roomState.room.secondsPerQ;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        t.cancel();
        if (!_revealed) _submitAnswer(null); // timeout = wrong
      }
    });
  }

  Future<void> _pollState() async {
    final res = await SocialApiService.getDuelRoom(widget.roomState.room.uuid);
    if (!mounted) return;
    if (res.success) setState(() => _latestState = res.data);
    if (res.data?.room.status == 'finished') _finishDuel();
  }

  // Both the 2s poller and a just-completed answer submission can decide
  // the duel is finished around the same tick (the poller isn't paused
  // while a submission is in flight, and the submission path didn't used
  // to check _duelFinished at all) — each could call _showResults() and
  // double-navigate. Route both through here: the check-then-set is
  // synchronous, so only the first caller ever proceeds.
  void _finishDuel() {
    if (_duelFinished) return;
    _duelFinished = true;
    _timer?.cancel();
    _pollTimer?.cancel();
    setState(() {});
    _showResults();
  }

  Future<void> _submitAnswer(int? chosen) async {
    if (_revealed) return;
    _timer?.cancel();
    setState(() { _selected = chosen; _revealed = true; });

    final elapsed = DateTime.now().millisecondsSinceEpoch - _answerStartMs;
    var res = await SocialApiService.submitDuelAnswer(
      roomId: widget.roomState.room.id,
      questionOrder: _currentQ,
      chosenIndex: chosen,
      answerMs: elapsed,
    );
    if (!res.success) {
      // res.success was never checked here before — on a network failure
      // the client just silently advanced as if the server had recorded
      // the answer, when it never did. One quick retry for transient
      // blips, then surface it if it still fails.
      res = await SocialApiService.submitDuelAnswer(
        roomId: widget.roomState.room.id,
        questionOrder: _currentQ,
        chosenIndex: chosen,
        answerMs: elapsed,
      );
    }

    if (!res.success) {
      // Both attempts failed. duel_answers is keyed by (room, user,
      // question_order) and used to just keep advancing _currentQ locally
      // regardless — that permanently skips this order server-side, and
      // since /duel/answer's "am I finished?" check is a plain answered
      // count, this user could then never reach question_count answers,
      // which meant the room could never finalize and both players' coins
      // stayed locked. Forfeit explicitly instead so the duel ends now.
      await SocialApiService.forfeitDuel(widget.roomState.room.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Connection lost — you forfeited this duel.'),
          backgroundColor: AppColors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
      await _pollState();
      if (mounted) _finishDuel();
      return;
    }

    // correct_index is withheld by the server while the room is 'active'
    // (see duel.php handleGetRoom) so an opponent can't read ahead via
    // /duel/room — is_correct from the answer response is the only
    // correctness signal available during live play.
    _lastAnswerCorrect = res.data?['is_correct'] as bool?;

    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;

    if (res.data?['duel_finished'] == true) {
      _finishDuel();
      return;
    }

    if (_currentQ + 1 < widget.roomState.questions.length) {
      setState(() {
        _currentQ++;
        _selected = null;
        _revealed = false;
        _lastAnswerCorrect = null;
        _answerStartMs = DateTime.now().millisecondsSinceEpoch;
      });
      if (widget.roomState.room.timedMode) _startTimer();
    }
  }

  void _showResults() {
    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (_) => DuelResultScreen(
        roomState: _latestState ?? widget.roomState),
    ));
  }

  @override
  void dispose() { _timer?.cancel(); _pollTimer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final questions = widget.roomState.questions;
    if (questions.isEmpty) return const Scaffold(
        body: Center(child: Text('No questions loaded')));

    final q         = questions[_currentQ] as Map<String, dynamic>;
    final options   = (q['options'] as List).cast<String>();
    final total     = questions.length;
    final room      = widget.roomState.room;
    final timedMode = room.timedMode;
    final timeRatio = timedMode ? _secondsLeft / room.secondsPerQ : 1.0;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Timer bar + header
            Container(
              color: AppColors.red,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(children: [
                Row(children: [
                  const Icon(Icons.sports_esports, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text('${room.level} · ${room.category}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  const Spacer(),
                  if (timedMode) Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                        color: _secondsLeft <= 5
                            ? Colors.white.withOpacity(0.3)
                            : Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.timer, color: Colors.white, size: 14),
                      const SizedBox(width: 4),
                      Text('$_secondsLeft s',
                          style: TextStyle(
                              color: _secondsLeft <= 5 ? Colors.yellow : Colors.white,
                              fontSize: 13, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 8),
                if (timedMode) ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: timeRatio,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    color: _secondsLeft <= 5 ? Colors.yellow : Colors.white,
                    minHeight: 5,
                  ),
                ),
              ]),
            ),

            // Question counter
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppColors.bg2,
              child: Row(children: [
                Text('Q${_currentQ + 1} / $total',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                const Spacer(),
                // Opponent progress
                if (_latestState != null)
                  ..._latestState!.participants
                      .where((p) => p.userId != context.read<AuthProvider>().user?.id)
                      .map((p) => Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          CircleAvatar(radius: 10,
                              backgroundColor: AppColors.red,
                              child: Text(p.username[0],
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.white))),
                          const SizedBox(width: 4),
                          Text('${p.score}pts',
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.muted)),
                        ]),
                      )),
              ]),
            ),

            Expanded(
              child: ListView(padding: const EdgeInsets.all(16), children: [
                // Question card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(
                    color: AppColors.bg,
                    border: Border(
                        top: BorderSide(color: AppColors.red, width: 3),
                        left: BorderSide(color: AppColors.border),
                        right: BorderSide(color: AppColors.border),
                        bottom: BorderSide(color: AppColors.border)),
                    borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(8),
                        bottomRight: Radius.circular(8)),
                  ),
                  child: Column(children: [
                    Text(q['question_text'] as String,
                        style: const TextStyle(
                            fontFamily: 'NotoSansJP', fontSize: 48,
                            fontWeight: FontWeight.w700, color: AppColors.ink),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    const Text('What is the correct reading?',
                        style: TextStyle(fontSize: 13, color: AppColors.muted)),
                  ]),
                ),
                const SizedBox(height: 14),

                // Options
                GridView.count(
                  crossAxisCount: 2, shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8, crossAxisSpacing: 8,
                  childAspectRatio: 1.7,
                  children: List.generate(options.length, (i) {
                    // correct_index is only populated once the room is
                    // 'finished' (anti-cheat — see handleGetRoom) so during
                    // live play it's always null and this fell back to
                    // is_correct from the /duel/answer response, which only
                    // tells us whether the tapped option was right, not
                    // which one was — so only the tapped option gets
                    // colored, never a "here's the right answer" reveal.
                    final correctIdx = q['correct_index'] as int?;
                    Color borderColor = AppColors.border;
                    Color bgColor     = AppColors.bg;
                    Color textColor   = AppColors.ink;
                    if (_revealed && correctIdx != null) {
                      if (i == correctIdx) {
                        borderColor = AppColors.green; bgColor = AppColors.greenLight;
                        textColor = AppColors.green;
                      } else if (i == _selected) {
                        borderColor = AppColors.red; bgColor = AppColors.redLight;
                        textColor = AppColors.red;
                      }
                    } else if (_revealed && correctIdx == null && i == _selected) {
                      final wasCorrect = _lastAnswerCorrect ?? false;
                      borderColor = wasCorrect ? AppColors.green : AppColors.red;
                      bgColor     = wasCorrect ? AppColors.greenLight : AppColors.redLight;
                      textColor   = wasCorrect ? AppColors.green : AppColors.red;
                    }
                    return GestureDetector(
                      onTap: () => _submitAnswer(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: bgColor,
                          border: Border.all(color: borderColor, width: 1.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(child: Text(options[i],
                          style: TextStyle(
                              fontFamily: 'NotoSansJP', fontSize: 16,
                              fontWeight: FontWeight.w700, color: textColor),
                          textAlign: TextAlign.center)),
                      ),
                    );
                  }),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Duel result screen
// ─────────────────────────────────────────────────────────────────────────────
class DuelResultScreen extends StatelessWidget {
  final DuelRoomState roomState;
  const DuelResultScreen({super.key, required this.roomState});

  @override
  Widget build(BuildContext context) {
    final myId    = context.read<AuthProvider>().user?.id;
    final winner  = roomState.winner;
    final iWon    = winner != null && winner['id'] == myId;
    final room    = roomState.room;
    final sorted  = [...roomState.participants]
      ..sort((a, b) {
        final sc = b.score.compareTo(a.score);
        return sc != 0 ? sc : a.timeTakenMs.compareTo(b.timeTakenMs);
      });

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          // Hero
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
            color: iWon ? AppColors.red : AppColors.ink2,
            child: Column(children: [
              Icon(iWon ? Icons.emoji_events : Icons.sports_esports_outlined,
                  size: 52, color: Colors.white),
              const SizedBox(height: 12),
              Text(iWon ? 'You won!' : winner != null ? '${winner['username']} won' : 'Draw!',
                  style: const TextStyle(fontSize: 24,
                      fontWeight: FontWeight.w700, color: Colors.white)),
              if (iWon) Text('+${room.prizeCoins} coins',
                  style: const TextStyle(fontSize: 16, color: Colors.white70)),
            ]),
          ),

          Expanded(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              // Scoreboard
              ...sorted.asMap().entries.map((e) {
                final rank = e.key + 1;
                final p    = e.value;
                final isMe = p.userId == myId;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isMe ? AppColors.redLight : AppColors.bg,
                    border: Border.all(
                        color: isMe ? AppColors.red : AppColors.border,
                        width: isMe ? 1.5 : 1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    Text('#$rank',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700,
                            color: rank == 1 ? AppColors.gold : AppColors.muted)),
                    const SizedBox(width: 12),
                    CircleAvatar(radius: 16,
                        backgroundColor: isMe ? AppColors.red : AppColors.muted2,
                        child: Text(p.username[0].toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontSize: 13))),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(isMe ? 'You' : p.username,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                              color: isMe ? AppColors.red : AppColors.ink)),
                      Text('${p.correctCount} correct · ${(p.timeTakenMs/1000).toStringAsFixed(1)}s',
                          style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                    ])),
                    Text('${p.score}',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                            color: isMe ? AppColors.red : AppColors.ink)),
                  ]),
                );
              }),

              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pushNamedAndRemoveUntil(
                    context, '/home', (_) => false),
                child: const Text('Back to home'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ─── Shared helpers ─────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
// Open Room Card
// ─────────────────────────────────────────────────────────────────────────────
class _OpenRoomCard extends StatelessWidget {
  final OpenDuelRoom room;
  final VoidCallback onJoin;
  const _OpenRoomCard({required this.room, required this.onJoin});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.redLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(child: Text(room.level,
                    style: const TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w700, color: AppColors.red))),
                ),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${room.level} · ${room.category}',
                    style: const TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w700, color: AppColors.ink)),
                  Text('Host: ${room.host}',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ]),
              ]),
              ElevatedButton(
                onPressed: onJoin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Join',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.people_outline, size: 14, color: AppColors.muted),
            const SizedBox(width: 4),
            Text('${room.joined}/${room.maxPlayers} players',
              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            const SizedBox(width: 12),
            const Icon(Icons.monetization_on, size: 14, color: AppColors.gold),
            const SizedBox(width: 4),
            Text('${room.coinBet} coins bet',
              style: const TextStyle(fontSize: 12, color: AppColors.gold,
                fontWeight: FontWeight.w600)),
            if (room.timedMode) ...[
              const SizedBox(width: 12),
              const Icon(Icons.timer_outlined, size: 14, color: AppColors.muted),
              const SizedBox(width: 4),
              Text('${room.secondsPerQ}s/q',
                style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ]),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon; final String message, action;
  final VoidCallback onAction;
  const _EmptyState({required this.icon, required this.message,
      required this.action, required this.onAction});
  @override Widget build(BuildContext context) => Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(icon, size: 56, color: AppColors.muted2),
    const SizedBox(height: 16),
    Text(message, style: const TextStyle(color: AppColors.muted)),
    const SizedBox(height: 16),
    ElevatedButton(onPressed: onAction, child: Text(action)),
  ]));
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Row(children: [
      const Expanded(child: Divider(color: AppColors.border)),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(3)),
          child: Text(text.toUpperCase(), style: const TextStyle(
              color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)))),
      const Expanded(child: Divider(color: AppColors.border)),
    ]),
  );
}

class _PickRow extends StatelessWidget {
  final String label, value; final List<String> options;
  final ValueChanged<String> onChanged;
  const _PickRow({required this.label, required this.value,
      required this.options, required this.onChanged});
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(children: [
      SizedBox(width: 130, child: Text(label,
          style: const TextStyle(fontSize: 13, color: AppColors.muted))),
      Expanded(child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(color: AppColors.bg2,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(6)),
        child: DropdownButtonHideUnderline(child: DropdownButton<String>(
          value: value, isExpanded: true, isDense: true,
          items: options.map((o) => DropdownMenuItem(value: o,
              child: Text(o, style: const TextStyle(fontSize: 13)))).toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        )),
      )),
    ]),
  );
}

class _SliderRow extends StatelessWidget {
  final String label; final double value, min, max;
  final int divisions; final String suffix;
  final ValueChanged<double> onChanged;
  const _SliderRow({required this.label, required this.value,
      required this.min, required this.max, required this.divisions,
      this.suffix = '', required this.onChanged});
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
        const Spacer(),
        Text('${value.round()}$suffix',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
      ]),
      Slider.adaptive(value: value, min: min, max: max, divisions: divisions,
          activeColor: AppColors.red,
          onChanged: onChanged),
    ]),
  );
}

class _InfoCard extends StatelessWidget {
  final DuelRoom room;
  const _InfoCard({required this.room});
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: AppColors.bg,
        border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(8)),
    child: Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _Stat(label: 'Level',    value: room.level),
        _Stat(label: 'Bet',      value: '${room.coinBet} 🪙'),
        _Stat(label: 'Timer',    value: room.timedMode ? '${room.secondsPerQ}s' : 'Off'),
        _Stat(label: 'Questions', value: '${room.questionCount}'),
      ]),
    ]),
  );
}

class _Stat extends StatelessWidget {
  final String label, value;
  const _Stat({required this.label, required this.value});
  @override Widget build(BuildContext context) => Column(children: [
    Text(label, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
    Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
  ]);
}

class _ParticipantRow extends StatelessWidget {
  final DuelParticipant participant;
  const _ParticipantRow({required this.participant});
  @override Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: AppColors.bg,
        border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(6)),
    child: Row(children: [
      CircleAvatar(radius: 16, backgroundColor: AppColors.red,
          child: Text(participant.username[0].toUpperCase(),
              style: const TextStyle(color: Colors.white, fontSize: 12))),
      const SizedBox(width: 10),
      Expanded(child: Text(participant.username,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink))),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: participant.status == 'ready' ? AppColors.greenLight : AppColors.bg2,
            border: Border.all(
                color: participant.status == 'ready' ? AppColors.green : AppColors.border),
            borderRadius: BorderRadius.circular(4)),
        child: Text(participant.status,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                color: participant.status == 'ready' ? AppColors.green : AppColors.muted)),
      ),
    ]),
  );
}

// User search dialog — debounced live search against /user/search,
// returns the selected user's real id (this used to be a stub that always
// returned 1 regardless of what was typed, so "invite" silently invited
// whatever user happened to have id 1 every time).
class _UserSearchDialog extends StatefulWidget {
  const _UserSearchDialog();
  @override State<_UserSearchDialog> createState() => _UserSearchDialogState();
}

class _UserSearchDialogState extends State<_UserSearchDialog> {
  final _controller = TextEditingController();
  Timer?  _debounce;
  List<UserSearchResult> _results = [];
  bool    _loading = false;
  bool    _searched = false;

  @override
  void dispose() { _debounce?.cancel(); _controller.dispose(); super.dispose(); }

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() { _results = []; _loading = false; _searched = false; });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q.trim()));
  }

  Future<void> _search(String q) async {
    final res = await ApiService.searchUsers(q);
    if (!mounted) return;
    setState(() {
      _results  = res.data ?? [];
      _loading  = false;
      _searched = true;
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Invite player'),
    content: SizedBox(
      width: double.maxFinite,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Search by username',
            suffixIcon: _loading
                ? const Padding(padding: EdgeInsets.all(12),
                    child: SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)))
                : null,
          ),
          onChanged: _onChanged,
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: _results.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    !_searched ? 'Type at least 2 characters'
                        : _loading ? '' : 'No users found',
                    style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  itemBuilder: (_, i) {
                    final u = _results[i];
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(radius: 14, backgroundColor: AppColors.red,
                          child: Text(u.username[0].toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontSize: 12))),
                      title: Text(u.username, style: const TextStyle(fontSize: 14)),
                      onTap: () => Navigator.pop(context, u.id),
                    );
                  },
                ),
        ),
      ]),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
    ],
  );
}
