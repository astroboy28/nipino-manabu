content = open('lib/models/models.dart', encoding='utf-8').read() 
old = 'class QuizSession {' 
new_cls = 'class QuizSession {\n  String get level = ? "" : questions.first.level;\n  String get category = ? "" : questions.first.category;\n  double get scorePercent = ? 0 : correctCount / questions.length;\n  int get timeTaken = ~/ 1000;\n  int coinsEarned = 0;' 
content = content.replace(old, new_cls) 
old2 = 'class LeaderboardEntry {' 
new_cls2 = 'class LeaderboardEntry {\n  String get level =;\n  double get accuracy =;\n  int get totalScore =;' 
content = content.replace(old2, new_cls2) 
open('lib/models/models.dart', 'w', encoding='utf-8').write(content) 
