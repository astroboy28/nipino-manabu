// lib/screens/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_provider.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';
import '../../widgets/app_bottom_nav.dart';



class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<LevelProgress> _progress = [];
  bool _loadingProgress = true;
  int  _navIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  bool _isLevelUnlocked(List<LevelProgress> progress, int index) {
  if (index <= 0) return true;
  if (index >= progress.length) return false;
  return progress[index - 1].percent >= 0.5;
}
  Future<void> _loadProgress() async {
    final res = await ApiService.getProgress();
    if (mounted && res.success) {
      setState(() { _progress = res.data!; _loadingProgress = false; });
    } else {
      setState(() => _loadingProgress = false);
    }
  }

  // Default progress if API not yet connected
  List<LevelProgress> get _displayProgress => _progress.isNotEmpty
      ? _progress
      : const [
          LevelProgress(level:'N5', percent:1.0,  completedTopics:6, totalTopics:6,  examUnlocked:true),
          LevelProgress(level:'N4', percent:0.85, completedTopics:5, totalTopics:6,  examUnlocked:false),
          LevelProgress(level:'N3', percent:0.68, completedTopics:4, totalTopics:6,  examUnlocked:false),
          LevelProgress(level:'N2', percent:0.40, completedTopics:2, totalTopics:6,  examUnlocked:false),
          LevelProgress(level:'N1', percent:0.12, completedTopics:1, totalTopics:6,  examUnlocked:false),
        ];

  static const _categories = [
    {'icon': Icons.edit_note, 'label': 'Kanji',      'sub': '2,136 characters', 'cat': 'kanji'},
    {'icon': Icons.menu_book, 'label': 'Vocabulary',  'sub': '10,000 words',    'cat': 'vocabulary'},
    {'icon': Icons.spellcheck,'label': 'Grammar',     'sub': '842 patterns',    'cat': 'grammar'},
    {'icon': Icons.hearing,   'label': 'Listening',   'sub': '320 tracks',      'cat': 'listening'},
  ];

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ─────────────────────────────────────────────────────
            _buildTopBar(user),
            const Divider(height: 1),

            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadProgress,
                color: AppColors.red,
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    // Hero band
                    _buildHero(user),

                    // Levels
                    const SectionHeader(tag: 'JLPT LEVELS'),
                    _loadingProgress
                        ? const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator(
                              color: AppColors.red, strokeWidth: 2)),
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              children: _displayProgress.asMap().entries.map((e) =>
                                  LevelProgressCard(
                                    progress: e.value,
                                    onTap: _isLevelUnlocked(_displayProgress, e.key) ? () => Navigator.pushNamed(
                                      context, '/lessons',
                                      arguments: e.value.level,
                                    ) : () => ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('🔒 Complete the previous level first!'),
                                      behavior: SnackBarBehavior.floating)),
                                  )
                              ).toList(),
                            ),
                          ),

                    // Quick practice
                    const SectionHeader(tag: 'QUICK PRACTICE'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 2.6,
                        children: _categories.map((c) => _CategoryChip(
                          icon: c['icon'] as IconData,
                          label: c['label'] as String,
                          sub:   c['sub']   as String,
                          onTap: () => Navigator.pushNamed(
                            context, '/quiz',
                            arguments: {'level': user?.currentLevel ?? 'N5', 'category': c['cat']},
                          ),
                        )).toList(),
                      ),
                    ),

                    // Stats
                    const SectionHeader(tag: 'YOUR PROGRESS'),
                    _buildStats(user),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            AppBottomNav(
              currentIndex: _navIndex,
              onTap: (i) {
                setState(() => _navIndex = i);
                switch (i) {
                  case 1: Navigator.pushNamed(context, '/lessons'); break;
                  case 2: Navigator.pushNamed(context, '/quiz',
                      arguments: {'level': context.read<AuthProvider>().user?.currentLevel ?? 'N5','category':'kanji'}); break;
                  case 3: Navigator.pushNamed(context, '/leaderboard'); break;
                  case 4: Navigator.pushNamed(context, '/duels'); break;
                  case 5: Navigator.pushNamed(context, '/profile'); break;
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(User? user) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Logo
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: AppColors.red, borderRadius: BorderRadius.circular(6)),
            child: const Center(child: Text('日',
              style: TextStyle(fontFamily:'NotoSansJP', fontSize:16,
                fontWeight:FontWeight.w700, color:Colors.white))),
          ),
          const SizedBox(width: 8),
          RichText(text: const TextSpan(
            style: TextStyle(fontSize:14, fontWeight:FontWeight.w700, color:AppColors.ink),
            children: [
              TextSpan(text: 'Nipino-'),
              TextSpan(text: 'Manabu', style: TextStyle(color: AppColors.red)),
            ],
          )),
          const Spacer(),
          // Streak pill
          _Pill(
            color: const Color(0xFFFFF3E0),
            border: const Color(0xFFFFCC80),
            child: Row(children: [
              const Icon(Icons.local_fire_department,
                size: 14, color: Color(0xFFE65100)),
              const SizedBox(width: 3),
              Text('${user?.streakDays ?? 0}',
                style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: Color(0xFFE65100))),
            ]),
          ),
          const SizedBox(width: 6),
          // Coins pill
          _Pill(
            color: AppColors.goldLight,
            border: const Color(0xFFE8C56A),
            child: Row(children: [
              const Icon(Icons.monetization_on,
                size: 14, color: AppColors.gold),
              const SizedBox(width: 3),
              Text('${user?.coins ?? 0}',
                style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: AppColors.gold)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildHero(User? user) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      color: AppColors.red,
      child: Stack(
        children: [
          Positioned(
            right: -8, top: -12,
            child: Text('学',
              style: TextStyle(
                fontFamily: 'NotoSansJP', fontSize: 100,
                fontWeight: FontWeight.w700,
                color: Colors.white.withOpacity(0.08)),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user != null ? 'こんにちは, ${user.username}!' : 'こんにちは!',
                style: const TextStyle(
                  fontSize: 12, color: Colors.white70,
                  fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              const Text('Learn Japanese.\nPass your exam.',
                style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w700,
                  color: Colors.white, height: 1.2)),
              const SizedBox(height: 14),
              Wrap(
                spacing: 6, runSpacing: 6,
                children: ['All Levels','N5 Beginner','N4 Elementary','N3→N1']
                    .map((l) => _LevelPill(label: l))
                    .toList(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStats(User? user) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        _StatBox(num: '${user?.totalScore ?? 0}', label: 'Total Score'),
        const SizedBox(width: 8),
        _StatBox(num: '${user?.currentLevel ?? 'N5'}', label: 'Current Level'),
        const SizedBox(width: 8),
        _StatBox(num: '${user?.coins ?? 0}', label: 'Coins',
          numColor: AppColors.gold),
      ]),
    );
  }
}

class _Pill extends StatelessWidget {
  final Color color, border;
  final Widget child;
  const _Pill({required this.color, required this.border, required this.child});
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color,
      border: Border.all(color: border),
      borderRadius: BorderRadius.circular(20),
    ),
    child: child,
  );
}

class _LevelPill extends StatelessWidget {
  final String label;
  const _LevelPill({required this.label});
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.18),
      border: Border.all(color: Colors.white.withOpacity(0.25)),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(label, style: const TextStyle(
      color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
  );
}

class _CategoryChip extends StatelessWidget {
  final IconData icon;
  final String label, sub;
  final VoidCallback onTap;
  const _CategoryChip({required this.icon, required this.label,
    required this.sub, required this.onTap});

  @override Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(children: [
        Container(
          width: 30, height: 30,
          decoration: BoxDecoration(
            color: AppColors.redLight,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 16, color: AppColors.red),
        ),
        const SizedBox(width: 8),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: const TextStyle(fontSize: 12,
              fontWeight: FontWeight.w700, color: AppColors.ink2)),
            Text(sub, style: const TextStyle(fontSize: 10,
              color: AppColors.muted2)),
          ],
        )),
      ]),
    ),
  );
}

class _StatBox extends StatelessWidget {
  final String num, label;
  final Color numColor;
  const _StatBox({required this.num, required this.label,
    this.numColor = AppColors.ink});
  @override Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(children: [
        Text(num, style: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w700, color: numColor)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(
          fontSize: 10, color: AppColors.muted), textAlign: TextAlign.center),
      ]),
    ),
  );
}
