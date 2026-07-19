// lib/screens/quiz/result_screen.dart
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../models/models.dart';
import '../../widgets/app_bottom_nav.dart';

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, this.session});
  final dynamic session;

  @override
  Widget build(BuildContext context) {
    final session = ModalRoute.of(context)?.settings.arguments as QuizSession?;
    if (session == null) {
      return Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => Navigator.pushReplacementNamed(context, '/home'),
            child: const Text('Back to Home'),
          ),
        ),
      );
    }

    final pct     = (session.scorePercent * 100).round();
    final correct = session.correctCount;
    final total   = session.questions.length;
    final mins    = session.timeTaken ~/ 60;
    final secs    = session.timeTaken % 60;
    final timeStr = '${mins}m ${secs.toString().padLeft(2,'0')}s';

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Hero ──────────────────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 52),
              color: AppColors.red,
              child: Stack(
                children: [
                  Positioned(
                    bottom: -20, left: 0, right: 0,
                    child: Container(
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.red,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.elliptical(200, 56)),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 8),
                        Text(
                          '${session.level} · ${session.category} · $total questions',
                          style: const TextStyle(fontSize: 12, color: Colors.white70),
                        ),
                        const SizedBox(height: 12),
                        Icon(
                          pct >= 80
                              ? Icons.star_rounded
                              : pct >= 50
                                  ? Icons.thumb_up_outlined
                                  : Icons.refresh,
                          size: 56, color: pct >= 80
                              ? const Color(0xFFFFD700)
                              : pct >= 50
                                  ? const Color(0xFF27AE60)
                                  : AppColors.red,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          pct >= 80 ? 'Quiz complete!' : pct >= 50 ? 'Good effort!' : 'Keep practising!',
                          style: const TextStyle(fontSize: 22,
                            fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  // Score ring
                  Center(
                    child: Container(
                      width: 100, height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.red, width: 4),
                        color: Colors.white,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('$pct%',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 26,
                              fontWeight: FontWeight.w700, color: AppColors.ink)),
                          const Text('Score',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: AppColors.muted)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Coins reward strip
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.goldLight,
                      border: const Border(
                        left: BorderSide(color: AppColors.gold, width: 3),
                        top:    BorderSide(color: Color(0xFFE8C56A)),
                        right:  BorderSide(color: Color(0xFFE8C56A)),
                        bottom: BorderSide(color: Color(0xFFE8C56A)),
                      ),
                      borderRadius: const BorderRadius.only(
                        topRight:    Radius.circular(6),
                        bottomRight: Radius.circular(6),
                      ),
                    ),
                    child: Row(children: [
                      const Icon(Icons.monetization_on,
                        color: AppColors.gold, size: 28),
                      const SizedBox(width: 12),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('+${session.coinsEarned} coins earned!',
                          style: const TextStyle(fontSize: 14,
                            fontWeight: FontWeight.w700, color: Color(0xFF7A5200))),
                        Text('$correct correct · streak & bonus included',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF9A6600))),
                      ]),
                    ]),
                  ),
                  if (session.coinsLost > 0) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.redLight,
                        border: const Border(
                          left: BorderSide(color: AppColors.red, width: 3)),
                        borderRadius: const BorderRadius.only(
                          topRight:    Radius.circular(6),
                          bottomRight: Radius.circular(6),
                        ),
                      ),
                      child: Row(children: [
                        const Icon(Icons.remove_circle_outline,
                          color: AppColors.red, size: 24),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('-${session.coinsLost} coins for wrong answers',
                            style: const TextStyle(fontSize: 14,
                              fontWeight: FontWeight.w700, color: AppColors.red)),
                          Text('${total - correct} wrong answer${(total - correct) == 1 ? '' : 's'}',
                            style: const TextStyle(fontSize: 11, color: AppColors.red)),
                        ])),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 14),

                  // Breakdown card
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(children: [
                      _BkRow(label: 'Correct answers',
                        value: '$correct / $total',
                        valueColor: AppColors.green),
                      _BkRow(label: 'Wrong answers',
                        value: '${total - correct}',
                        valueColor: total - correct > 0 ? AppColors.red : AppColors.ink),
                      _BkRow(label: 'Time taken', value: timeStr),
                      _BkRow(label: 'Level', value: session.level),
                      _BkRow(label: 'Category',
                        value: session.category[0].toUpperCase()
                            + session.category.substring(1),
                        isLast: true),
                    ]),
                  ),
                  const SizedBox(height: 16),

                  // Action buttons
                  ElevatedButton(
                    onPressed: () => Navigator.pushReplacementNamed(
                      context, '/quiz',
                      arguments: {
                        'level':    session.level,
                        'category': session.category,
                      },
                    ),
                    child: const Text('Try next question set'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => Navigator.pushReplacementNamed(
                      context, '/lessons',
                      arguments: session.level,
                    ),
                    child: const Text('Back to lessons'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => Navigator.pushReplacementNamed(
                      context, '/leaderboard'),
                    child: const Text('View leaderboard'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => Navigator.pushReplacementNamed(
                      context, '/home'),
                    child: const Text('Back to Home'),
                  ),
                ],
              ),
            ),

            AppBottomNav(
              currentIndex: 2,
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
}

class _BkRow extends StatelessWidget {
  final String label, value;
  final Color? valueColor;
  final bool isLast;
  const _BkRow({required this.label, required this.value,
    this.valueColor, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        border: isLast ? null : const Border(
          bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(
            fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w500)),
          Text(value, style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700,
            color: valueColor ?? AppColors.ink)),
        ],
      ),
    );
  }
}
