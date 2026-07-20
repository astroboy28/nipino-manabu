import 'package:flutter_test/flutter_test.dart';
import 'package:nipino_manabu/models/models.dart';

void main() {
  group('User.fromJson', () {
    test('parses is_admin and is_verified from /user/profile-shaped JSON', () {
      // Regression: GET /user/profile previously omitted both fields, so
      // every app restart (checkAuth) silently showed a verified user as
      // unverified and could never surface an admin-only menu entry.
      final u = User.fromJson({
        'id': 1, 'username': 'a', 'email': 'a@example.com',
        'coins': 250, 'streak_days': 0, 'current_level': 'N5',
        'total_score': 0, 'is_verified': true, 'is_admin': true,
        'created_at': '2026-01-01',
      });
      expect(u.isVerified, isTrue);
      expect(u.isAdmin, isTrue);
    });

    test('defaults is_admin/is_verified to false when absent', () {
      final u = User.fromJson({
        'id': 1, 'username': 'a', 'email': 'a@example.com',
      });
      expect(u.isVerified, isFalse);
      expect(u.isAdmin, isFalse);
      expect(u.coins, 0);
      expect(u.currentLevel, 'N5');
    });
  });

  group('QuizQuestion.fromJson', () {
    test('hasImage/hasAudio are false for null or empty URLs', () {
      final q = QuizQuestion.fromJson({
        'id': 1, 'level': 'N5', 'category': 'vocab',
        'question_text': 'x', 'options': ['a', 'b'], 'correct_index': 0,
        'image_url': '', 'audio_url': null,
      });
      expect(q.hasImage, isFalse);
      expect(q.hasAudio, isFalse);
    });

    test('isListening reflects question_type', () {
      final q = QuizQuestion.fromJson({
        'id': 1, 'level': 'N5', 'category': 'listening',
        'question_text': 'x', 'question_type': 'listening',
        'options': ['a', 'b'], 'correct_index': 0,
      });
      expect(q.isListening, isTrue);
      expect(q.isImageBased, isFalse);
    });
  });

  group('QuizSession', () {
    test('scorePercent is 0 for an empty question set (no divide-by-zero)', () {
      final s = QuizSession(questions: const []);
      expect(s.scorePercent, 0);
      expect(s.level, '');
    });

    test('scorePercent reflects correctCount over question count', () {
      final s = QuizSession(questions: [
        QuizQuestion.fromJson({
          'id': 1, 'level': 'N5', 'category': 'vocab',
          'question_text': 'x', 'options': ['a', 'b'], 'correct_index': 0,
        }),
        QuizQuestion.fromJson({
          'id': 2, 'level': 'N5', 'category': 'vocab',
          'question_text': 'y', 'options': ['a', 'b'], 'correct_index': 0,
        }),
      ]);
      s.correctCount = 1;
      expect(s.scorePercent, 0.5);
    });
  });

  group('LevelProgress.fromJson', () {
    test('applies defaults for missing numeric fields', () {
      final p = LevelProgress.fromJson({'level': 'N5'});
      expect(p.percent, 0.0);
      expect(p.completedTopics, 0);
      expect(p.totalTopics, 6);
      expect(p.examUnlocked, isFalse);
    });
  });
}
