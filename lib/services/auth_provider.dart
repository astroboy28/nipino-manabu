// lib/services/auth_provider.dart
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import 'api_service.dart';
import 'social_api_service.dart';

class AuthProvider extends ChangeNotifier {
  User?  _user;
  bool   _loading = false;
  String? _error;

  User?   get user    => _user;
  bool    get loading => _loading;
  String? get error   => _error;
  bool    get isLoggedIn => _user != null;

  void _setLoading(bool v) { _loading = v; notifyListeners(); }
  void _setError(String? e) { _error = e; notifyListeners(); }

  // ── Validate input before hitting API ─────────────────────────────────────
  String? _validateEmail(String email) {
    final re = RegExp(r'^[\w.+-]+@[\w-]+\.[a-zA-Z]{2,}$');
    if (!re.hasMatch(email)) return 'Invalid email address';
    return null;
  }

  String? _validatePassword(String pw) {
    if (pw.length < 8) return 'Password must be at least 8 characters';
    if (!pw.contains(RegExp(r'[A-Z]'))) return 'Must contain an uppercase letter';
    if (!pw.contains(RegExp(r'[0-9]'))) return 'Must contain a number';
    return null;
  }

  // ── Register ───────────────────────────────────────────────────────────────
  Future<bool> register(String username, String email, String password) async {
    _setError(null);
    final emailErr = _validateEmail(email);
    if (emailErr != null) { _setError(emailErr); return false; }
    final pwErr = _validatePassword(password);
    if (pwErr != null) { _setError(pwErr); return false; }
    if (username.trim().length < 3) {
      _setError('Username must be at least 3 characters'); return false;
    }

    _setLoading(true);
    final res = await ApiService.register(
      username: username.trim(),
      email:    email.trim().toLowerCase(),
      password: password,
    );
    _setLoading(false);

    if (res.success) {
      _user = res.data;
      notifyListeners();
      _tryClaimPendingReferral();
      return true;
    }
    _setError(res.error);
    return false;
  }

  // ── Login ──────────────────────────────────────────────────────────────────
  Future<bool> login(String email, String password) async {
    _setError(null);
    _setLoading(true);
    final res = await ApiService.login(
      email: email.trim().toLowerCase(),
      password: password,
    );
    _setLoading(false);
    if (res.success) {
      _user = res.data;
      notifyListeners();
      _tryClaimPendingReferral();
      return true;
    }
    _setError(res.error ?? 'Login failed');
    return false;
  }

  // A referral code picked up from a deep link before the user had a
  // session (the common case — a fresh install) is stashed by ApiService;
  // redeem it now that we actually have auth. Only clear it on a definitive
  // server response so a network hiccup doesn't lose the code — it'll just
  // retry on the next login.
  Future<void> _tryClaimPendingReferral() async {
    final code = await ApiService.getPendingReferralCode();
    if (code == null) return;
    final res = await SocialApiService.claimReferral(code);
    if (res.statusCode != 0) {
      await ApiService.clearPendingReferralCode();
      if (res.success) await refreshUser(); // coins were just credited
    }
  }

  // ── Logout ─────────────────────────────────────────────────────────────────
  Future<void> logout() async {
    _setLoading(true);
    await ApiService.logout();
    _user = null;
    _setLoading(false);
  }

  // ── Refresh user from API ──────────────────────────────────────────────────
  Future<void> refreshUser() async {
    final res = await ApiService.getProfile();
    if (res.success) { _user = res.data; notifyListeners(); }
  }

  // ── Check stored token on app start ───────────────────────────────────────
  Future<void> checkAuth() async {
    _setLoading(true);
    final token = await ApiService.getToken();
    if (token != null) {
      final res = await ApiService.getProfile();
      if (res.success) _user = res.data;
      _tryClaimPendingReferral();
    }
    _setLoading(false);
  }
}
