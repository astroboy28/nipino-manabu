import os 
# Fix models.dart 
c = open('lib/models/models.dart', encoding='utf-8').read() 
c = c.replace('String get level = ? "" : questions.first.level;', 'String get level => questions.isEmpty ? "" : questions.first.level;') 
c = c.replace('String get category = ? "" : questions.first.category;', 'String get category => questions.isEmpty ? "" : questions.first.category;') 
c = c.replace('double get scorePercent = ? 0 : correctCount / questions.length;', 'double get scorePercent => questions.isEmpty ? 0 : correctCount / questions.length;') 
c = c.replace('int get timeTaken = ~/ 1000;', 'int get timeTaken => totalMs ~/ 1000;') 
c = c.replace('String get level =;', 'String get level => "N5";') 
c = c.replace('double get accuracy =;', 'double get accuracy => 0.0;') 
c = c.replace('int get totalScore =;', 'int get totalScore => score;') 
open('lib/models/models.dart', 'w', encoding='utf-8').write(c) 
