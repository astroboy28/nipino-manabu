// lib/models/social_models.dart
// ─── Models for duels, challenges, invitations, referrals ────────────────────

// ── Duel room ─────────────────────────────────────────────────────────────────
class DuelRoom {
  final int     id;
  final String  uuid;
  final String  hostUsername;
  final String  level;
  final String  category;
  final int     coinBet;
  final bool    timedMode;
  final int     secondsPerQ;
  final int     questionCount;
  final int     maxPlayers;
  final String  status;    // waiting|active|finished|cancelled|expired
  final int     prizeCoins;
  final String? expiresAt;
  final String? startedAt;
  final String? finishedAt;

  const DuelRoom({
    required this.id, required this.uuid, required this.hostUsername,
    required this.level, required this.category, required this.coinBet,
    required this.timedMode, required this.secondsPerQ,
    required this.questionCount, required this.maxPlayers,
    required this.status, required this.prizeCoins,
    this.expiresAt, this.startedAt, this.finishedAt,
  });

  factory DuelRoom.fromJson(Map<String, dynamic> j) => DuelRoom(
    id: j['id'], uuid: j['uuid'], hostUsername: j['host_username'] ?? '',
    level: j['level'], category: j['category'],
    coinBet: j['coin_bet'], timedMode: j['timed_mode'] ?? true,
    secondsPerQ: j['seconds_per_q'] ?? 15,
    questionCount: j['question_count'] ?? 10,
    maxPlayers: j['max_players'] ?? 2,
    status: j['status'], prizeCoins: j['prize_coins'] ?? 0,
    expiresAt: j['expires_at'], startedAt: j['started_at'],
    finishedAt: j['finished_at'],
  );
}

class DuelParticipant {
  final int    userId;
  final String username;
  final String status;
  final int    score;
  final int    correctCount;
  final int    timeTakenMs;
  final int    coinsWagered;

  const DuelParticipant({
    required this.userId, required this.username, required this.status,
    required this.score, required this.correctCount,
    required this.timeTakenMs, required this.coinsWagered,
  });

  factory DuelParticipant.fromJson(Map<String, dynamic> j) => DuelParticipant(
    userId: j['user_id'], username: j['username'], status: j['status'],
    score: j['score'] ?? 0, correctCount: j['correct_count'] ?? 0,
    timeTakenMs: j['time_taken_ms'] ?? 0, coinsWagered: j['coins_wagered'] ?? 0,
  );
}

class DuelRoomState {
  final DuelRoom               room;
  final List<DuelParticipant>  participants;
  final List<dynamic>          questions;  // QuizQuestion objects
  final Map<String, dynamic>?  winner;

  const DuelRoomState({
    required this.room, required this.participants,
    required this.questions, this.winner,
  });

  factory DuelRoomState.fromJson(Map<String, dynamic> j) => DuelRoomState(
    room:         DuelRoom.fromJson(j['room']),
    participants: (j['participants'] as List? ?? [])
        .map((e) => DuelParticipant.fromJson(e)).toList(),
    questions:    j['questions'] as List? ?? [],
    winner:       j['winner'] as Map<String, dynamic>?,
  );
}

// ── Challenge event ───────────────────────────────────────────────────────────
class ChallengeEvent {
  final int     id;
  final String  uuid;
  final String  title;
  final String  description;
  final String  level;
  final String  category;
  final int     prizeCoins;
  final String? prizeBadgeEmoji;
  final int     secondsPerQ;
  final int     questionCount;
  final String  status;   // upcoming|active|finished|cancelled
  final bool    featured;
  final String  startsAt;
  final String  endsAt;
  final int     joinedCount;
  final int     maxParticipants;
  final String? winnerUsername;
  final bool    userJoined;
  final bool    userCompleted;

  const ChallengeEvent({
    required this.id, required this.uuid, required this.title,
    required this.description, required this.level, required this.category,
    required this.prizeCoins, this.prizeBadgeEmoji,
    required this.secondsPerQ, required this.questionCount,
    required this.status, required this.featured,
    required this.startsAt, required this.endsAt,
    required this.joinedCount, required this.maxParticipants,
    this.winnerUsername,
    this.userJoined = false, this.userCompleted = false,
  });

  factory ChallengeEvent.fromJson(Map<String, dynamic> j) => ChallengeEvent(
    id: j['id'], uuid: j['uuid'] ?? '',
    title: j['title'], description: j['description'] ?? '',
    level: j['level'], category: j['category'] ?? '',
    prizeCoins: j['prize_coins'],
    prizeBadgeEmoji: j['prize_badge_emoji'],
    secondsPerQ: j['seconds_per_q'] ?? 20,
    questionCount: j['question_count'] ?? 15,
    status: j['status'], featured: j['featured'] ?? false,
    startsAt: j['starts_at'] ?? '', endsAt: j['ends_at'] ?? '',
    joinedCount: j['joined_count'] ?? 0,
    maxParticipants: j['max_participants'] ?? 100,
    winnerUsername: j['winner_username'],
    userJoined: j['user_joined'] != null,
    userCompleted: j['user_completed'] == true,
  );

  bool get isLive {
    final now = DateTime.now();
    final start = DateTime.tryParse(startsAt);
    final end   = DateTime.tryParse(endsAt);
    if (start == null || end == null) return false;
    return now.isAfter(start) && now.isBefore(end);
  }

  bool get isUpcoming {
    final start = DateTime.tryParse(startsAt);
    if (start == null) return false;
    return DateTime.now().isBefore(start);
  }
}

// ── Invitation ────────────────────────────────────────────────────────────────
class Invitation {
  final int     id;
  final String  uuid;
  final String  type;   // duel | challenge
  final String? fromUsername;
  final int     referenceId;
  final String  status;
  final String? message;
  final String  expiresAt;
  final Map<String, dynamic>? details;

  const Invitation({
    required this.id, required this.uuid, required this.type,
    this.fromUsername, required this.referenceId, required this.status,
    this.message, required this.expiresAt, this.details,
  });

  factory Invitation.fromJson(Map<String, dynamic> j) => Invitation(
    id: j['id'], uuid: j['uuid'], type: j['type'],
    fromUsername: j['from_username'],
    referenceId: j['reference_id'], status: j['status'],
    message: j['message'], expiresAt: j['expires_at'] ?? '',
    details: j['details'] as Map<String, dynamic>?,
  );
}

// ── Challenge leaderboard entry ───────────────────────────────────────────────
class ChallengeEntry {
  final int?   rank;
  final int    userId;
  final String username;
  final int    score;
  final int    correctCount;
  final int    timeTakenMs;
  final int    coinsAwarded;
  final bool   isCurrentUser;

  const ChallengeEntry({
    this.rank, required this.userId, required this.username,
    required this.score, required this.correctCount,
    required this.timeTakenMs, required this.coinsAwarded,
    required this.isCurrentUser,
  });

  factory ChallengeEntry.fromJson(Map<String, dynamic> j) => ChallengeEntry(
    rank: j['rank_pos'],
    userId: j['user_id'], username: j['username'],
    score: j['score'] ?? 0, correctCount: j['correct_count'] ?? 0,
    timeTakenMs: j['time_taken_ms'] ?? 0, coinsAwarded: j['coins_awarded'] ?? 0,
    isCurrentUser: j['is_current_user'] == true,
  );
}

// ── User search result (duel invite picker) ───────────────────────────────────
class UserSearchResult {
  final int     id;
  final String  username;
  final String? avatarUrl;

  const UserSearchResult({required this.id, required this.username, this.avatarUrl});

  factory UserSearchResult.fromJson(Map<String, dynamic> j) => UserSearchResult(
    id: j['id'], username: j['username'], avatarUrl: j['avatar_url'],
  );
}

// ── Open duel room listing ────────────────────────────────────────────────────
class OpenDuelRoom {
  final String uuid;
  final String level;
  final String category;
  final int    coinBet;
  final bool   timedMode;
  final int    secondsPerQ;
  final int    maxPlayers;
  final int    joined;
  final String host;
  final String expiresAt;

  const OpenDuelRoom({
    required this.uuid, required this.level, required this.category,
    required this.coinBet, required this.timedMode,
    required this.secondsPerQ, required this.maxPlayers,
    required this.joined, required this.host, required this.expiresAt,
  });

  factory OpenDuelRoom.fromJson(Map<String, dynamic> j) => OpenDuelRoom(
    uuid: j['uuid'], level: j['level'], category: j['category'],
    coinBet: j['coin_bet'], timedMode: j['timed_mode'] ?? true,
    secondsPerQ: j['seconds_per_q'] ?? 15,
    maxPlayers: j['max_players'] ?? 2,
    joined: j['joined'] ?? 1, host: j['host'] ?? '',
    expiresAt: j['expires_at'] ?? '',
  );
}
