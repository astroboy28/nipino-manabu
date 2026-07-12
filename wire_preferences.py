c = open('lib/screens/settings/quiz_preferences_screen.dart', encoding='utf-8').read()

# 1. Add imports
old_imp = "import '../../services/social_api_service.dart';\nimport '../../services/auth_provider.dart';"
new_imp = "import '../../services/social_api_service.dart';\nimport '../../services/auth_provider.dart';\nimport '../../services/sound_service.dart';\nimport 'package:shared_preferences/shared_preferences.dart';"
if old_imp in c:
    c = c.replace(old_imp, new_imp)
    print("1. Imports added")
else:
    print("1. NOT FOUND")

# 2. Add sound toggle state + load existing prefs in initState
old_state = "  bool   _saved        = false;\n  String? _error;"
new_state = """  bool   _saved        = false;
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
  }"""
if old_state in c:
    c = c.replace(old_state, new_state)
    print("2. Sound toggle state + loader added")
else:
    print("2. NOT FOUND")

# 3. Update _save to persist to SharedPreferences too
old_save = """  Future<void> _save() async {
    setState(() { _saving = true; _saved = false; _error = null; });
    final res = await SocialApiService.updateQuizPreferences(
      timedMode: _timedMode, secondsPerQ: _secondsPerQ);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (res.success) {
        _saved = true;
      } else {
        _error = res.error ?? 'Failed to save preferences';
      }
    });
    if (_saved) {
      await context.read<AuthProvider>().refreshUser();
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _saved = false);
    }
  }"""

new_save = """  Future<void> _save() async {
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
  }"""

if old_save in c:
    c = c.replace(old_save, new_save)
    print("3. _save updated")
else:
    print("3. NOT FOUND")

# 4. Add sound toggle UI right before the Save button
old_ui = "          const SizedBox(height: 24),\n\n          // Error\n          if (_error != null) ..."
new_ui = """          const SizedBox(height: 24),
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
          if (_error != null) ..."""

if old_ui in c:
    c = c.replace(old_ui, new_ui)
    print("4. Sound toggle UI added")
else:
    print("4. NOT FOUND")

open('lib/screens/settings/quiz_preferences_screen.dart', 'w', encoding='utf-8').write(c)
print("\nquiz_preferences_screen.dart saved!")
