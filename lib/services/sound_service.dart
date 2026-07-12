// lib/services/sound_service.dart
// ─── Sound effects for quiz interactions (correct/wrong/tap/coin) ───────────
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal();

  final AudioPlayer _player = AudioPlayer();
  bool _enabled = true;
  bool _loaded = false;

  static const _prefKey = 'sound_effects_enabled';

  Future<void> init() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_prefKey) ?? true;
    _loaded = true;
  }

  bool get enabled => _enabled;

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
  }

  Future<void> _play(String asset) async {
    if (!_enabled) return;
    try {
      await _player.setAsset('assets/sounds/$asset');
      await _player.seek(Duration.zero);
      await _player.play();
    } catch (_) {
      // Ignore playback errors (e.g. device silent mode issues)
    }
  }

  Future<void> playCorrect() => _play('correct.wav');
  Future<void> playWrong() => _play('wrong.wav');
  Future<void> playTap() => _play('tap.wav');
  Future<void> playCoin() => _play('coin.wav');

  // No dispose() here on purpose: SoundService is an app-lifetime singleton
  // (every `SoundService()` call returns the same instance), not a
  // per-screen resource. It used to have a public dispose() that nothing
  // called — but it looked exactly like the per-widget "own it, dispose it"
  // pattern used everywhere else in this codebase, so a future
  // `_sound.dispose()` in some screen's dispose() would have silently
  // killed sound app-wide (every _play() call swallows its own errors).
}
