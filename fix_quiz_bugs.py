c = open('lib/screens/quiz/quiz_screen.dart', encoding='utf-8').read()

# Fix 1: Initialize sound service in initState
old = """  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadQuestions());
  }"""
new = """  @override
  void initState() {
    super.initState();
    _sound.init();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadQuestions());
  }"""
if old in c:
    c = c.replace(old, new)
    print("1. Sound init fixed!")
else:
    print("1. NOT FOUND")

# Fix 2: Default level to N5 not N3
old2 = "    final level    = args['level']    as String? ?? 'N3';"
new2 = "    final level    = args['level']    as String? ?? 'N5';"
if old2 in c:
    c = c.replace(old2, new2)
    print("2. Default level fixed to N5!")
else:
    print("2. NOT FOUND")

# Fix 3: Don't play wrong sound on timeout (null answer)
old3 = """    if (isCorrect) {
      _session!.correctCount++;
      _sound.playCorrect();
    } else {
      _sound.playWrong();
    }"""
new3 = """    if (isCorrect) {
      _session!.correctCount++;
      _sound.playCorrect();
    } else if (chosen != null) {
      // Only play wrong sound if user actually selected an answer (not timeout)
      _sound.playWrong();
    }"""
if old3 in c:
    c = c.replace(old3, new3)
    print("3. Timeout sound fixed!")
else:
    print("3. NOT FOUND")

# Fix 4: Don't show memory tip on timeout
old4 = "              if (_revealed && q.memoryTip != null) ...["
new4 = "              if (_revealed && _selected != null && q.memoryTip != null) ...["
if old4 in c:
    c = c.replace(old4, new4)
    print("4. Memory tip on timeout fixed!")
else:
    print("4. NOT FOUND")

# Fix 5: Remove unused user variable
old5 = """    // Load user timer preference
    final user = context.read<AuthProvider>().user;
    // In production read quiz_timed_mode / quiz_seconds_per_q from user profile

    final res = await ApiService.getQuestions("""
new5 = """    final res = await ApiService.getQuestions("""
if old5 in c:
    c = c.replace(old5, new5)
    print("5. Unused user variable removed!")
else:
    print("5. NOT FOUND")

open('lib/screens/quiz/quiz_screen.dart', 'w', encoding='utf-8').write(c)
print("\nquiz_screen.dart saved!")
