// lib/widgets/app_bottom_nav.dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const AppBottomNav({super.key, required this.currentIndex, required this.onTap});

  static const _items = [
    {'icon': Icons.home_outlined,    'label': 'Home'},
    {'icon': Icons.menu_book,        'label': 'Learn'},
    {'icon': Icons.track_changes,    'label': 'Quiz'},
    {'icon': Icons.emoji_events,     'label': 'Rank'},
    {'icon': Icons.sports_esports,   'label': 'Duel'},
    {'icon': Icons.person_outline,   'label': 'Profile'},
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.border, width: 1.5)),
      ),
      child: Row(
        children: List.generate(_items.length, (i) {
          final active = i == currentIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => onTap(i),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: active ? AppColors.red : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _items[i]['icon'] as IconData,
                      size: 22,
                      color: active ? AppColors.red : AppColors.muted,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _items[i]['label'] as String,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: active ? AppColors.red : AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Level Progress Card ────────────────────────────────────────────────────────
// lib/widgets/level_progress_card.dart (inlined here for brevity)
class LevelProgressCard extends StatelessWidget {
  final dynamic progress; // LevelProgress
  final VoidCallback onTap;
  const LevelProgressCard({super.key, required this.progress, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final level   = progress.level as String;
    final pct     = progress.percent as double;
    final color   = AppTheme.levelColor(level);
    final isDone  = pct >= 1.0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.bg,
          border: Border(
            left: BorderSide(color: isDone ? AppColors.green : AppColors.red, width: 4),
            top:    const BorderSide(color: AppColors.border),
            right:  const BorderSide(color: AppColors.border),
            bottom: const BorderSide(color: AppColors.border),
          ),
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(6),
            bottomRight: Radius.circular(6),
          ),
        ),
        child: Row(
          children: [
            // Level badge
            SizedBox(
              width: 38,
              child: Text(level,
                style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w700, color: color),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_levelName(level),
                    style: const TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w700, color: AppColors.ink)),
                  Text(_levelDesc(level),
                    style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: pct,
                        backgroundColor: AppColors.bg3,
                        color: isDone ? AppColors.green : color,
                        minHeight: 4,
                      ),
                    )),
                    const SizedBox(width: 8),
                    Text(
                      isDone ? 'Done ✓' : '${(pct * 100).round()}%',
                      style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w600,
                        color: isDone ? AppColors.green : AppColors.muted2),
                    ),
                  ]),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isDone ? Icons.check_circle : Icons.chevron_right,
              color: isDone ? AppColors.green : AppColors.muted2,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  String _levelName(String l) => {
    'N5': 'N5 — Beginner',
    'N4': 'N4 — Elementary',
    'N3': 'N3 — Intermediate',
    'N2': 'N2 — Upper Intermediate',
    'N1': 'N1 — Advanced',
  }[l] ?? l;

  String _levelDesc(String l) => {
    'N5': 'Hiragana · Katakana · 800 vocab · basic grammar',
    'N4': '300 kanji · 1,500 vocab · grammar patterns',
    'N3': '650 kanji · 3,750 vocab · complex grammar',
    'N2': '1,000 kanji · 6,000 vocab · reading/listening',
    'N1': '2,000+ kanji · 10,000 vocab · advanced comprehension',
  }[l] ?? '';
}

// ── Section Header (nipino editorial style) ───────────────────────────────────
class SectionHeader extends StatelessWidget {
  final String tag;
  const SectionHeader({super.key, required this.tag});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(children: [
        const Expanded(child: Divider(color: AppColors.border)),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.red,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(tag,
            style: const TextStyle(
              color: Colors.white, fontSize: 10,
              fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        ),
        const SizedBox(width: 10),
        const Expanded(child: Divider(color: AppColors.border)),
      ]),
    );
  }
}
