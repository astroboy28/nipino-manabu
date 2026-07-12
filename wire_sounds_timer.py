c = open('lib/screens/quiz/quiz_screen.dart', encoding='utf-8').read()

# 1. Add imports
old_imports = "import '../../widgets/quiz_media_widget.dart';\nimport 'result_screen.dart';"
new_imports = "import '../../widgets/quiz_media_widget.dart';\nimport '../../services/sound_service.dart';\nimport 'result_screen.dart';"
if old_imports in c:
    c = c.replace(old_imports, new_imports)
    print("1. Imports added")
else:
    print("1. NOT FOUND")

# 2. Add sound service instance
old_state = "  String? _error;\n\n  @override\n  void initState() {"
new_state = "  String? _error;\n  final _sound = SoundService();\n\n  @override\n  void initState() {"
if old_state in c:
    c = c.replace(old_state, new_state)
    print("2. Sound instance added")
else:
    print("2. NOT FOUND")

# 3. Load timer preference from user instead of hardcoded true
old_load = """    final res = await ApiService.getQuestions(
        level: level, category: category, count: 10);
    if (!mounted) return;

    if (res.success && res.data != null && res.data!.isNotEmpty) {
      setState(() {
        _session   = QuizSession(questions: res.data!);
        _loading   = false;
        _timedMode = true;           // default; replace with user preference
        _secondsLeft = 15;
        _qStartMs  = DateTime.now().millisecondsSinceEpoch;
      });
      if (_timedMode) _startTimer();
    } else {
      setState(() { _loading = false; _error = res.error ?? 'No questions found.'; });
    }
  }"""

new_load = """    final res = await ApiService.getQuestions(
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
      setState(() { _loading = false; _error = res.error ?? 'No questions found.'; });
    }
  }"""

if old_load in c:
    c = c.replace(old_load, new_load)
    print("3. Timer preference loading added")
else:
    print("3. NOT FOUND")

# 4. Add _secondsPerQ field
old_field = "  bool    _timedMode   = true;"
new_field = "  bool    _timedMode   = true;\n  int     _secondsPerQ = 15;"
if old_field in c:
    c = c.replace(old_field, new_field)
    print("4. _secondsPerQ field added")
else:
    print("4. NOT FOUND")

# 5. Update _startTimer to use _secondsPerQ instead of hardcoded 15
old_timer = """  void _startTimer() {
    _timer?.cancel();
    _secondsLeft = 15;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) { t.cancel(); if (!_revealed) _pickAnswer(null); }
    });
  }"""

new_timer = """  void _startTimer() {
    _timer?.cancel();
    _secondsLeft = _secondsPerQ;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) { t.cancel(); if (!_revealed) _pickAnswer(null); }
    });
  }"""

if old_timer in c:
    c = c.replace(old_timer, new_timer)
    print("5. _startTimer updated")
else:
    print("5. NOT FOUND")

# 6. Play sound on answer pick (correct/wrong)
old_pick = """    final q         = _session!.current;
    final isCorrect = chosen != null && chosen == q.correctIndex;
    if (isCorrect) _session!.correctCount++;

    setState(() { _selected = chosen; _revealed = true; });"""

new_pick = """    final q         = _session!.current;
    final isCorrect = chosen != null && chosen == q.correctIndex;
    if (isCorrect) {
      _session!.correctCount++;
      _sound.playCorrect();
    } else {
      _sound.playWrong();
    }

    setState(() { _selected = chosen; _revealed = true; });"""

if old_pick in c:
    c = c.replace(old_pick, new_pick)
    print("6. Sound on answer added")
else:
    print("6. NOT FOUND")

# 7. Reset secondsLeft to _secondsPerQ (not hardcoded 15) in two places
old_reset1 = """    _session!.currentIndex++;
    setState(() {
      _selected    = null;
      _revealed    = false;
      _qStartMs    = DateTime.now().millisecondsSinceEpoch;
      _secondsLeft = 15;
    });
    if (_timedMode) _startTimer();
  }

  Future<void> _nextQuestion() async {"""

new_reset1 = """    _session!.currentIndex++;
    setState(() {
      _selected    = null;
      _revealed    = false;
      _qStartMs    = DateTime.now().millisecondsSinceEpoch;
      _secondsLeft = _secondsPerQ;
    });
    if (_timedMode) _startTimer();
  }

  Future<void> _nextQuestion() async {"""

if old_reset1 in c:
    c = c.replace(old_reset1, new_reset1)
    print("7. First reset fixed")
else:
    print("7. NOT FOUND")

old_reset2 = """  _session!.currentIndex++;
  setState(() {
    _selected = null;
    _revealed = false;
    _qStartMs = DateTime.now().millisecondsSinceEpoch;
    _secondsLeft = 15;
  });
  if (_timedMode) _startTimer();
}"""

new_reset2 = """  _session!.currentIndex++;
  setState(() {
    _selected = null;
    _revealed = false;
    _qStartMs = DateTime.now().millisecondsSinceEpoch;
    _secondsLeft = _secondsPerQ;
  });
  if (_timedMode) _startTimer();
}"""

if old_reset2 in c:
    c = c.replace(old_reset2, new_reset2)
    print("8. Second reset fixed")
else:
    print("8. NOT FOUND")

# 9. Fix tRatio to use _secondsPerQ instead of hardcoded 15.0
old_ratio = "final tRatio  = _timedMode ? _secondsLeft / 15.0 : 1.0;"
new_ratio = "final tRatio  = _timedMode ? _secondsLeft / _secondsPerQ : 1.0;"
if old_ratio in c:
    c = c.replace(old_ratio, new_ratio)
    print("9. tRatio fixed")
else:
    print("9. NOT FOUND")

# 10. Add shared_preferences import
old_imp2 = "import 'package:provider/provider.dart';"
new_imp2 = "import 'package:provider/provider.dart';\nimport 'package:shared_preferences/shared_preferences.dart';"
if old_imp2 in c:
    c = c.replace(old_imp2, new_imp2)
    print("10. shared_preferences import added")
else:
    print("10. NOT FOUND")

open('lib/screens/quiz/quiz_screen.dart', 'w', encoding='utf-8').write(c)
print("\nquiz_screen.dart saved!")
