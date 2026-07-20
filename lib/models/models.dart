// lib/models/models.dart  –  UPDATED: imageUrl, audioUrl on QuizQuestion
// ─── Core data models ─────────────────────────────────────────────────────────

class User {
  final int    id;
  final String username;
  final String email;
  final int    coins;
  final int    streakDays;
  final String currentLevel;
  final int    totalScore;
  final bool   isVerified;
  final bool   isAdmin;
  final String createdAt;

  const User({
    required this.id, required this.username, required this.email,
    required this.coins, required this.streakDays, required this.currentLevel,
    required this.totalScore, required this.isVerified, required this.isAdmin,
    required this.createdAt,
  });

  factory User.fromJson(Map<String,dynamic> j) => User(
    id:           j['id'],
    username:     j['username'],
    email:        j['email'],
    coins:        j['coins']       ?? 0,
    streakDays:   j['streak_days'] ?? 0,
    currentLevel: j['current_level'] ?? 'N5',
    totalScore:   j['total_score'] ?? 0,
    isVerified:   j['is_verified'] == true,
    isAdmin:      j['is_admin']    == true,
    createdAt:    j['created_at']  ?? '',
  );
}

class QuizQuestion {
  final int     id;
  final String  level;
  final String  category;
  final String  questionText;
  final String  questionType;  // reading|meaning|grammar_fill|listening|image_reading|image_meaning
  final List<String> options;
  final int     correctIndex;
  final String  explanation;
  final String? memoryTip;
  final int     pointValue;
  final String? imageUrl;   // nullable — null means text-only question
  final String? audioUrl;   // nullable — null means no audio
  final String? mediaCredit;

  const QuizQuestion({
    required this.id, required this.level, required this.category,
    required this.questionText, required this.questionType,
    required this.options, required this.correctIndex,
    required this.explanation, this.memoryTip,
    required this.pointValue,
    this.imageUrl, this.audioUrl, this.mediaCredit,
  });

  factory QuizQuestion.fromJson(Map<String,dynamic> j) => QuizQuestion(
    id:           j['id'],
    level:        j['level'],
    category:     j['category'],
    questionText: j['question_text'],
    questionType: j['question_type'] ?? 'reading',
    options:      (j['options'] as List? ?? []).cast<String>(),
    correctIndex: j['correct_index'] ?? 0,
    explanation:  j['explanation']   ?? '',
    memoryTip:    j['memory_tip'],
    pointValue:   j['point_value']   ?? 10,
    imageUrl:     j['image_url'],
    audioUrl:     j['audio_url'],
    mediaCredit:  j['media_credit'],
  );

  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;
  bool get hasAudio => audioUrl != null && audioUrl!.isNotEmpty;
  bool get isListening  => questionType == 'listening';
  bool get isImageBased => questionType == 'image_reading' || questionType == 'image_meaning';
}

class QuizSession {
  String get level => questions.isEmpty ? "" : questions.first.level;
  String get category => questions.isEmpty ? "" : questions.first.category;
  double get scorePercent => questions.isEmpty ? 0 : correctCount / questions.length;
  int get timeTaken => totalMs ~/ 1000;
  int coinsEarned = 0;
  int coinsLost   = 0;
  final List<QuizQuestion> questions;
  // Chosen option index per question (null = skipped/timed out), same order
  // as `questions`. This is what actually gets submitted to the backend —
  // the server re-derives the score from these rather than trusting a count.
  final List<int?> chosenIndices;
  int currentIndex;
  int correctCount;
  int totalMs;

  QuizSession({required this.questions})
      : currentIndex = 0, correctCount = 0, totalMs = 0,
        chosenIndices = List<int?>.filled(questions.length, null);

  QuizQuestion get current => questions[currentIndex];
  bool get isLast         => currentIndex >= questions.length - 1;
  bool get isDone         => currentIndex >= questions.length;
  double get progress     => questions.isEmpty ? 0 : (currentIndex + 1) / questions.length;

  List<Map<String, dynamic>> get answersPayload => [
    for (var i = 0; i < questions.length; i++)
      {'question_id': questions[i].id, 'chosen_index': chosenIndices[i]},
  ];
}

class LevelProgress {
  final String level;
  final double percent;
  
  final int    completedTopics;
  final int    totalTopics;
  final bool   examUnlocked;

  const LevelProgress({
    required this.level, this.percent=0.0,required this.completedTopics,
    required this.totalTopics, required this.examUnlocked,
  });

  factory LevelProgress.fromJson(Map<String,dynamic> j) => LevelProgress(
    level:           j['level'],
    percent: (j['percent'] ?? 0.0).toDouble(),
    completedTopics: j['completed_topics'] ?? 0,
    totalTopics:     j['total_topics']     ?? 6,
    examUnlocked:    j['exam_unlocked']    == true,
  );
}

class LeaderboardEntry {
  int get totalScore => score;
  final int    rank;
  final int    userId;
  final String username;
  final int    score;
  final int    streakDays;
  final String level;
  final double accuracy;
  final bool   isCurrentUser;

  const LeaderboardEntry({
    required this.rank, required this.userId, required this.username,
    required this.score, required this.streakDays, required this.isCurrentUser,
    this.level = '', this.accuracy = 0.0,
  });

  // Backend (backend/api/leaderboard.php) returns 'rank' (not 'rank_pos')
  // and 'total_score' (not 'score') — this used to read the wrong keys, so
  // every entry silently showed rank 0 and score 0, and level/accuracy were
  // hardcoded stub getters that ignored the real fields entirely.
  factory LeaderboardEntry.fromJson(Map<String,dynamic> j, int currentUserId) =>
      LeaderboardEntry(
        rank:          j['rank']        ?? 0,
        userId:        j['user_id'],
        username:      j['username'],
        score:         j['total_score'] ?? 0,
        streakDays:    j['streak_days'] ?? 0,
        level:         j['level']       ?? '',
        accuracy:      ((j['accuracy'] ?? 0) as num).toDouble(),
        isCurrentUser: j['user_id']     == currentUserId,
      );
}

class AppBadge {
  final int    id;
  final String name;
  final String description;
  final String iconEmoji;
  final bool   earned;
  final String? earnedAt;

  const AppBadge({
    required this.id, required this.name, required this.description,
    required this.iconEmoji, required this.earned, this.earnedAt,
  });

  factory AppBadge.fromJson(Map<String,dynamic> j) => AppBadge(
    id:          j['id'],
    name:        j['name'],
    description: j['description'] ?? '',
    iconEmoji:   j['icon_emoji']  ?? '🏅',
    earned:      j['earned']      == true,
    earnedAt:    j['earned_at'],
  );
}

class ApiResponse<T> {
  final bool    success;
  final T?      data;
  final String? error;
  final int     statusCode;
  final Map<String,dynamic>? raw;

  const ApiResponse({
    required this.success, this.data, this.error,
    required this.statusCode, this.raw,
  });
}
