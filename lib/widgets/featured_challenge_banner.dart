// lib/widgets/featured_challenge_banner.dart
// ─── Featured challenge widget for Home screen + social nav row ──────────────
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/social_models.dart';
import '../services/social_api_service.dart';

// ─── Featured Challenge Banner (shown on Home screen) ────────────────────────
class FeaturedChallengeBanner extends StatefulWidget {
  const FeaturedChallengeBanner({super.key});
  @override State<FeaturedChallengeBanner> createState() =>
      _FeaturedChallengeBannerState();
}

class _FeaturedChallengeBannerState
    extends State<FeaturedChallengeBanner> {
  ChallengeEvent? _event;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final res = await SocialApiService.getFeaturedChallenge();
    if (mounted) {
      setState(() { _event = res.data; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    if (_event == null) return const SizedBox.shrink();

    final e        = _event!;
    final isLive   = e.status == 'active';
    final finished = e.status == 'finished';

    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/challenges'),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.bg,
          border: Border(
            left: BorderSide(
                color: finished ? AppColors.green : AppColors.gold,
                width: 4),
            top:    const BorderSide(color: AppColors.border),
            right:  const BorderSide(color: AppColors.border),
            bottom: const BorderSide(color: AppColors.border),
          ),
          borderRadius: const BorderRadius.only(
              topRight:    Radius.circular(8),
              bottomRight: Radius.circular(8)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Text(e.prizeBadgeEmoji ?? '🏆',
                style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Live / Winner badge
              if (isLive) Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 2),
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                    color: AppColors.red,
                    borderRadius: BorderRadius.circular(3)),
                child: const Text('LIVE CHALLENGE',
                    style: TextStyle(color: Colors.white, fontSize: 9,
                        fontWeight: FontWeight.w700, letterSpacing: 0.5))),
              if (finished && e.winnerUsername != null) Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 2),
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                    color: AppColors.greenLight,
                    borderRadius: BorderRadius.circular(3)),
                child: Text('🏆 Winner: ${e.winnerUsername}',
                    style: const TextStyle(
                        color: AppColors.green, fontSize: 9,
                        fontWeight: FontWeight.w700))),
              Text(e.title,
                  style: const TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w700, color: AppColors.ink)),
              Text('Prize: ${e.prizeCoins} 🪙 · ${e.level}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.muted)),
            ])),
            const Icon(Icons.chevron_right,
                color: AppColors.muted2, size: 18),
          ]),
        ),
      ),
    );
  }
}

// ─── Social action row (Duel | Invite | Challenges) ──────────────────────────
class SocialActionRow extends StatelessWidget {
  const SocialActionRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        _ActionBtn(
          icon:  Icons.sports_esports_outlined,
          label: 'Duel',
          color: AppColors.red,
          onTap: () => Navigator.pushNamed(context, '/duels'),
        ),
        const SizedBox(width: 8),
        _ActionBtn(
          icon:  Icons.emoji_events_outlined,
          label: 'Challenges',
          color: AppColors.gold,
          onTap: () => Navigator.pushNamed(context, '/challenges'),
        ),
        const SizedBox(width: 8),
        _ActionBtn(
          icon:  Icons.person_add_outlined,
          label: 'Invite',
          color: AppColors.green,
          onTap: () => Navigator.pushNamed(context, '/referral'),
        ),
      ]),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon; final String label;
  final Color color; final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.label,
      required this.color, required this.onTap});
  @override Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          border: Border.all(color: color.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 11,
              fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    ),
  );
}
