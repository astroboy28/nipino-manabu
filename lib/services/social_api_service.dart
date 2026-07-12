// lib/services/social_api_service.dart
// ─── API calls for duels, challenges, referrals, invitations ─────────────────
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import '../models/social_models.dart';
import '../models/models.dart';

class SocialApiService {
  static const _base = 'https://api.nipino-manabu.com/v1';

  static Future<Map<String,String>> _h() async {
    final t = await ApiService.getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (t != null) 'Authorization': 'Bearer $t',
    };
  }

  static Future<http.Response> _post(String p, Map<String, dynamic> b) async =>
      http.post(Uri.parse('$_base$p'), headers: await _h(), body: jsonEncode(b));

  static Future<http.Response> _get(String p) async =>
      http.get(Uri.parse('$_base$p'), headers: await _h());

  // ════════════════════════════════════════════════════════════════════════
  // DUEL
  // ════════════════════════════════════════════════════════════════════════

  static Future<ApiResponse<Map<String,dynamic>>> createDuel({
    required String level,
    required String category,
    required int    coinBet,
    required int    maxPlayers,
    required bool   timedMode,
    required int    secondsPerQ,
    int questionCount = 10,
  }) async {
    try {
      final res  = await _post('/duel/create', {
        'level': level, 'category': category, 'coin_bet': coinBet,
        'max_players': maxPlayers, 'timed_mode': timedMode,
        'seconds_per_q': secondsPerQ, 'question_count': questionCount,
      });
      final b = jsonDecode(res.body);
      if (res.statusCode == 201) return ApiResponse(success: true, data: b, statusCode: 201);
      return ApiResponse(success: false, error: b['message'], statusCode: res.statusCode);
    } catch (e) { return ApiResponse(success: false, error: 'Network error', statusCode: 0); }
  }

  static Future<ApiResponse<void>> inviteUserToDuel({
    required int roomId, required int inviteeId, String message = '',
  }) async {
    try {
      final res = await _post('/duel/invite',
          {'room_id': roomId, 'invitee_id': inviteeId, 'message': message});
      final b = jsonDecode(res.body);
      return ApiResponse(success: b['success'] ?? false,
          error: b['message'], statusCode: res.statusCode);
    } catch (e) { return ApiResponse(success: false, error: 'Network error', statusCode: 0); }
  }

  static Future<ApiResponse<Map<String,dynamic>>> joinDuel(String roomUuid) async {
    try {
      final res = await _post('/duel/join', {'room_uuid': roomUuid});
      final b = jsonDecode(res.body);
      if (res.statusCode == 200) return ApiResponse(success: true, data: b, statusCode: 200);
      return ApiResponse(success: false, error: b['message'], statusCode: res.statusCode);
    } catch (e) { return ApiResponse(success: false, error: 'Network error', statusCode: 0); }
  }

  static Future<ApiResponse<Map<String,dynamic>>> markReady(int roomId) async {
    try {
      final res = await _post('/duel/ready', {'room_id': roomId});
      final b = jsonDecode(res.body);
      return ApiResponse(success: b['success'] ?? false, data: b, statusCode: res.statusCode);
    } catch (e) { return ApiResponse(success: false, error: 'Network error', statusCode: 0); }
  }

  static Future<ApiResponse<Map<String,dynamic>>> submitDuelAnswer({
    required int roomId, required int questionOrder,
    int? chosenIndex, required int answerMs,
  }) async {
    try {
      final res = await _post('/duel/answer', {
        'room_id': roomId, 'question_order': questionOrder,
        'chosen_index': chosenIndex, 'answer_ms': answerMs,
      });
      final b = jsonDecode(res.body);
      return ApiResponse(success: b['success'] ?? false, data: b, statusCode: res.statusCode);
    } catch (e) { return ApiResponse(success: false, error: 'Network error', statusCode: 0); }
  }

  static Future<ApiResponse<DuelRoomState>> getDuelRoom(String uuid) async {
    try {
      final res = await _get('/duel/room?uuid=$uuid');
      final b   = jsonDecode(res.body);
      if (res.statusCode == 200)
        return ApiResponse(success: true,
            data: DuelRoomState.fromJson(b), statusCode: 200);
      return ApiResponse(success: false, error: b['message'], statusCode: res.statusCode);
    } catch (e) { return ApiResponse(success: false, error: 'Network error', statusCode: 0); }
  }

  static Future<ApiResponse<List<OpenDuelRoom>>> listOpenDuels() async {
    try {
      final res = await _get('/duel/list');
      final b   = jsonDecode(res.body);
      if (res.statusCode == 200) {
        return ApiResponse(success: true,
            data: (b['rooms'] as List).map((e) => OpenDuelRoom.fromJson(e)).toList(),
            statusCode: 200);
      }
      return ApiResponse(success: false, error: b['message'], statusCode: res.statusCode);
    } catch (e) { return ApiResponse(success: false, error: 'Network error', statusCode: 0); }
  }

  static Future<void> forfeitDuel(int roomId) async {
    try { await _post('/duel/forfeit', {'room_id': roomId}); } catch (_) {}
  }

  // ════════════════════════════════════════════════════════════════════════
  // CHALLENGE
  // ════════════════════════════════════════════════════════════════════════

  static Future<ApiResponse<ChallengeEvent?>> getFeaturedChallenge() async {
    try {
      final res = await _get('/challenge/featured');
      final b   = jsonDecode(res.body);
      if (res.statusCode == 200 && b['event'] != null) {
        return ApiResponse(success: true,
            data: ChallengeEvent.fromJson(b['event']), statusCode: 200);
      }
      return ApiResponse(success: true, data: null, statusCode: 200);
    } catch (e) { return ApiResponse(success: false, error: 'Network error', statusCode: 0); }
  }

  static Future<ApiResponse<List<ChallengeEvent>>> listChallenges(String status) async {
    try {
      final res = await _get('/challenge/list?status=$status');
      final b   = jsonDecode(res.body);
      if (res.statusCode == 200) {
        return ApiResponse(success: true,
            data: (b['events'] as List).map((e) => ChallengeEvent.fromJson(e)).toList(),
            statusCode: 200);
      }
      return ApiResponse(success: false, error: b['message'], statusCode: res.statusCode);
    } catch (e) { return ApiResponse(success: false, error: 'Network error', statusCode: 0); }
  }

  static Future<ApiResponse<ChallengeEvent>> getChallenge(int eventId) async {
    try {
      final res = await _get('/challenge/get?event_id=$eventId');
      final b   = jsonDecode(res.body);
      if (res.statusCode == 200)
        return ApiResponse(success: true,
            data: ChallengeEvent.fromJson(b['event']), statusCode: 200);
      return ApiResponse(success: false, error: b['message'], statusCode: res.statusCode);
    } catch (e) { return ApiResponse(success: false, error: 'Network error', statusCode: 0); }
  }

  static Future<ApiResponse<void>> joinChallenge(int eventId) async {
    try {
      final res = await _post('/challenge/join', {'event_id': eventId});
      final b   = jsonDecode(res.body);
      return ApiResponse(success: b['success'] ?? false,
          error: b['message'], statusCode: res.statusCode);
    } catch (e) { return ApiResponse(success: false, error: 'Network error', statusCode: 0); }
  }

  static Future<ApiResponse<void>> submitChallengeResult({
    required int eventId, required List<Map<String, dynamic>> answers,
    required int timeTakenMs,
  }) async {
    try {
      final res = await _post('/challenge/submit-result', {
        'event_id': eventId, 'answers': answers, 'time_taken_ms': timeTakenMs,
      });
      final b = jsonDecode(res.body);
      return ApiResponse(success: b['success'] ?? false,
          error: b['message'], statusCode: res.statusCode);
    } catch (e) { return ApiResponse(success: false, error: 'Network error', statusCode: 0); }
  }

  static Future<ApiResponse<List<ChallengeEntry>>> challengeLeaderboard(int eventId) async {
    try {
      final res = await _get('/challenge/leaderboard?event_id=$eventId');
      final b   = jsonDecode(res.body);
      if (res.statusCode == 200) {
        return ApiResponse(success: true,
            data: (b['entries'] as List).map((e) => ChallengeEntry.fromJson(e)).toList(),
            statusCode: 200);
      }
      return ApiResponse(success: false, error: b['message'], statusCode: res.statusCode);
    } catch (e) { return ApiResponse(success: false, error: 'Network error', statusCode: 0); }
  }

  // ════════════════════════════════════════════════════════════════════════
  // INVITATIONS
  // ════════════════════════════════════════════════════════════════════════

  static Future<ApiResponse<List<Invitation>>> getInvitations() async {
    try {
      final res = await _get('/duel/invitations');
      final b   = jsonDecode(res.body);
      if (res.statusCode == 200) {
        return ApiResponse(success: true,
            data: (b['invitations'] as List).map((e) => Invitation.fromJson(e)).toList(),
            statusCode: 200);
      }
      return ApiResponse(success: false, error: b['message'], statusCode: res.statusCode);
    } catch (e) { return ApiResponse(success: false, error: 'Network error', statusCode: 0); }
  }

  static Future<ApiResponse<Map<String,dynamic>>> respondInvitation({
    required String invUuid, required String action,
  }) async {
    try {
      final res = await _post('/duel/respond-invite',
          {'invitation_uuid': invUuid, 'action': action});
      final b = jsonDecode(res.body);
      return ApiResponse(success: b['success'] ?? false, data: b, statusCode: res.statusCode);
    } catch (e) { return ApiResponse(success: false, error: 'Network error', statusCode: 0); }
  }

  // ════════════════════════════════════════════════════════════════════════
  // REFERRAL
  // ════════════════════════════════════════════════════════════════════════

  static Future<ApiResponse<Map<String,dynamic>>> getMyReferralLink() async {
    try {
      final res = await _get('/referral/my-link');
      final b   = jsonDecode(res.body);
      if (res.statusCode == 200) return ApiResponse(success: true, data: b, statusCode: 200);
      return ApiResponse(success: false, error: b['message'], statusCode: res.statusCode);
    } catch (e) { return ApiResponse(success: false, error: 'Network error', statusCode: 0); }
  }

  static Future<ApiResponse<Map<String,dynamic>>> claimReferral(String code) async {
    try {
      final res = await _post('/referral/claim', {'referral_code': code});
      final b   = jsonDecode(res.body);
      return ApiResponse(success: b['success'] ?? false, data: b, statusCode: res.statusCode);
    } catch (e) { return ApiResponse(success: false, error: 'Network error', statusCode: 0); }
  }

  // ════════════════════════════════════════════════════════════════════════
  // QUIZ PREFERENCES (timer settings)
  // ════════════════════════════════════════════════════════════════════════

  static Future<ApiResponse<void>> updateQuizPreferences({
    required bool timedMode, required int secondsPerQ,
  }) async {
    try {
      final res = await http.put(
        Uri.parse('$_base/user/profile'),
        headers: await _h(),
        body: jsonEncode({
          'quiz_timed_mode': timedMode,
          'quiz_seconds_per_q': secondsPerQ,
        }),
      );
      final b = jsonDecode(res.body);
      return ApiResponse(success: b['success'] ?? false, statusCode: res.statusCode);
    } catch (e) { return ApiResponse(success: false, error: 'Network error', statusCode: 0); }
  }
}
