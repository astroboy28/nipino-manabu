import re

# ── Fix 1: Result screen icon color ──────────────────────────────────────────
r = open('lib/screens/quiz/result_screen.dart', encoding='utf-8').read()

old_icon = """                        Icon(
                          pct >= 80
                              ? Icons.star_rounded
                              : pct >= 50
                                  ? Icons.thumb_up_outlined
                                  : Icons.refresh,
                          size: 48, color: Colors.white,
                        ),"""
new_icon = """                        Icon(
                          pct >= 80
                              ? Icons.star_rounded
                              : pct >= 50
                                  ? Icons.thumb_up_outlined
                                  : Icons.refresh,
                          size: 48, color: pct >= 80
                              ? const Color(0xFFFFD700)
                              : pct >= 50
                                  ? Colors.white
                                  : AppColors.red,
                        ),"""
if old_icon in r:
    r = r.replace(old_icon, new_icon)
    print("1. Result icon color fixed!")
else:
    print("1. NOT FOUND")

open('lib/screens/quiz/result_screen.dart', 'w', encoding='utf-8').write(r)

# ── Fix 2: Duel card - fix vertical text by adding crossAxisAlignment ─────────
d = open('lib/screens/duel/duel_screen.dart', encoding='utf-8').read()

old_row = """      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: AppColors.redLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(child: Text(
            room.level,
            style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.red),
          )),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${room.level} · ${room.category}',
              style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 2),
            Text('Host: ${room.host} · ${room.joined}/${room.maxPlayers} players',
              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.monetization_on, size: 12, color: AppColors.gold),
              const SizedBox(width: 3),
              Text('${room.coinBet} coins',
                style: const TextStyle(fontSize: 11, color: AppColors.gold,
                  fontWeight: FontWeight.w600)),
              if (room.timedMode) ...[
                const SizedBox(width: 8),
                const Icon(Icons.timer_outlined, size: 12, color: AppColors.muted),
                const SizedBox(width: 2),
                Text('${room.secondsPerQ}s/question',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted)),
              ],
            ]),
          ],
        )),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: onJoin,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.red,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('Join',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ),
      ]),"""

new_row = """      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: AppColors.redLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(child: Text(
            room.level,
            style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.red),
          )),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${room.level} · ${room.category}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 2),
            Text(
              'Host: ${room.host} · ${room.joined}/${room.maxPlayers} players',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            const SizedBox(height: 4),
            Wrap(children: [
              const Icon(Icons.monetization_on, size: 12, color: AppColors.gold),
              const SizedBox(width: 3),
              Text('${room.coinBet} coins',
                style: const TextStyle(fontSize: 11, color: AppColors.gold,
                  fontWeight: FontWeight.w600)),
              if (room.timedMode) ...[
                const SizedBox(width: 8),
                const Icon(Icons.timer_outlined, size: 12, color: AppColors.muted),
                const SizedBox(width: 2),
                Text('${room.secondsPerQ}s/q',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted)),
              ],
            ]),
          ],
        )),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: onJoin,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.red,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('Join',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ),
      ]),"""

if old_row in d:
    d = d.replace(old_row, new_row)
    print("2. Duel card layout fixed!")
else:
    print("2. NOT FOUND")

open('lib/screens/duel/duel_screen.dart', 'w', encoding='utf-8').write(d)

# ── Fix 3: Coins - fetch coins from submit result response ────────────────────
q = open('lib/screens/quiz/quiz_screen.dart', encoding='utf-8').read()

old_submit = """    final res = await ApiService.submitQuizResult(
        level: session.level,
        category: session.category,
        correctCount: session.correctCount,
        totalCount: session.questions.length,
        timeTakenSeconds: session.totalMs ~/ 1000,
        coinsEarned: 0, // backend calculates"""
new_submit = """    final res = await ApiService.submitQuizResult(
        level: session.level,
        category: session.category,
        correctCount: session.correctCount,
        totalCount: session.questions.length,
        timeTakenSeconds: session.totalMs ~/ 1000,
        coinsEarned: 0, // backend calculates"""

# Check if coins are being set from response
idx = q.find('coinsEarned: 0')
print("3. Coins submit found:", idx > -1)
if idx > -1:
    # Find what happens after submit
    end_idx = q.find('Navigator.pushReplacementNamed', idx)
    print("After submit:")
    print(repr(q[idx:end_idx+50]))

open('lib/screens/quiz/quiz_screen.dart', 'w', encoding='utf-8').write(q)
print("\nAll fixes saved!")
