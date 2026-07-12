// lib/screens/lessons/lesson_screen.dart
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';
import '../../widgets/app_bottom_nav.dart';

class LessonScreen extends StatefulWidget {
  const LessonScreen({super.key});
  @override State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  List<Map<String,dynamic>> _topics = [];
  bool _loading = true;
  String _level = 'N5';

  static const _topicDefs = [
    {'title': 'Kanji',       'sub': 'Kanji reading and meaning',        'category': 'kanji'},
    {'title': 'Vocabulary',  'sub': 'Essential vocabulary words',       'category': 'vocabulary'},
    {'title': 'Grammar',     'sub': 'Grammar patterns and usage',       'category': 'grammar'},
    {'title': 'Listening',   'sub': 'Listening comprehension practice', 'category': 'listening'},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final level = ModalRoute.of(context)?.settings.arguments as String? ?? 'N5';
    setState(() { _level = level; _loading = true; });
    final res = await ApiService.getProgress();
    if (!mounted) return;
    LevelProgress? prog;
    if (res.success && res.data != null) {
      prog = res.data!.firstWhere((p) => p.level == level,
          orElse: () => LevelProgress(level: level, completedTopics: 0, totalTopics: 4, examUnlocked: false));
    }
    final completed = prog?.completedTopics ?? 0;
    final topics = _topicDefs.asMap().entries.map((e) {
      final i = e.key;
      return {
        ...e.value,
        'done': i < completed,
        'current': i == completed,
        'locked': i > completed,
      };
    }).toList();
    setState(() { _topics = topics; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border))),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.bg2,
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(6)),
                    child: const Icon(Icons.arrow_back, size: 18, color: AppColors.ink2),
                  ),
                ),
                const SizedBox(width: 10),
                Text('$_level — ${_levelName(_level)}',
                  style: const TextStyle(fontSize: 14,
                    fontWeight: FontWeight.w700, color: AppColors.ink)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.red, borderRadius: BorderRadius.circular(3)),
                  child: Text(_level, style: const TextStyle(
                    color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),

            // Info banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: AppColors.goldLight,
              child: const Row(children: [
                Icon(Icons.info_outline, size: 16, color: AppColors.gold),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Complete quizzes in each category to track your progress.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF7A5200),
                      fontWeight: FontWeight.w500),
                  ),
                ),
              ]),
            ),

            _loading
              ? const Expanded(child: Center(child: CircularProgressIndicator(color: AppColors.red, strokeWidth: 2)))
              : Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                color: AppColors.red,
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _topics.length,
                  itemBuilder: (context, i) {
                    final t       = _topics[i];
                    final done    = t['done']    == true;
                    final current = t['current'] == true;
                    final locked  = t['locked']  == true;

                    return GestureDetector(
                      onTap: locked ? null : () => Navigator.pushNamed(
                        context, '/quiz',
                        arguments: {'level': _level, 'category': t['category']},
                      ).then((_) => _load()),
                      child: Opacity(
                        opacity: locked ? 0.5 : 1,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.bg,
                            border: Border(
                              left: BorderSide(
                                color: done ? AppColors.green
                                    : current ? AppColors.red
                                    : AppColors.border,
                                width: done || current ? 3 : 1),
                              top:    const BorderSide(color: AppColors.border),
                              right:  const BorderSide(color: AppColors.border),
                              bottom: const BorderSide(color: AppColors.border),
                            ),
                            borderRadius: const BorderRadius.only(
                              topRight:    Radius.circular(6),
                              bottomRight: Radius.circular(6)),
                          ),
                          child: Row(children: [
                            Container(
                              width: 28, height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: done ? AppColors.green
                                    : current ? AppColors.red
                                    : AppColors.muted2),
                              child: Center(child: done
                                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                                  : Text('${i + 1}', style: const TextStyle(
                                      fontSize: 12, fontWeight: FontWeight.w700,
                                      color: Colors.white))),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t['title'] as String, style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w700,
                                  color: AppColors.ink)),
                                Text(t['sub'] as String, style: const TextStyle(
                                  fontSize: 11, color: AppColors.muted)),
                              ],
                            )),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: done ? AppColors.greenLight
                                    : current ? AppColors.redLight
                                    : AppColors.bg3,
                                borderRadius: BorderRadius.circular(3)),
                              child: Text(
                                done ? 'Done' : current ? 'Current' : 'Locked',
                                style: TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.w700,
                                  color: done ? AppColors.green
                                      : current ? AppColors.red
                                      : AppColors.muted2),
                              ),
                            ),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            AppBottomNav(
              currentIndex: 1,
              onTap: (i) {
                switch (i) {
                  case 0: Navigator.pushReplacementNamed(context, '/home'); break;
                  case 1: Navigator.pushReplacementNamed(context, '/lessons'); break;
                  case 2: Navigator.pushReplacementNamed(context, '/quiz', arguments: {'level': 'N5', 'category': 'kanji'}); break;
                  case 3: Navigator.pushReplacementNamed(context, '/leaderboard'); break;
                  case 4: Navigator.pushReplacementNamed(context, '/duels'); break;
                  case 5: Navigator.pushReplacementNamed(context, '/profile'); break;
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  String _levelName(String l) => {
    'N5': 'Beginner', 'N4': 'Elementary', 'N3': 'Intermediate',
    'N2': 'Upper Intermediate', 'N1': 'Advanced',
  }[l] ?? l;
}