// lib/screens/leaderboard/leaderboard_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_provider.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';
import '../../widgets/app_bottom_nav.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});
  @override State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  List<LeaderboardEntry> _entries = [];
  bool   _loading  = true;
  String _period   = 'weekly';
  String? _level;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final user = context.read<AuthProvider>().user;
    final res  = await ApiService.getLeaderboard(
      period: _period, level: _level,
      currentUserId: user?.id ?? 0,
    );
    if (mounted) {
      setState(() {
        _entries = res.success ? res.data! : [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // The podium needs exactly 3 entries (top[0..2]) or it would throw.
    // With fewer than 3 total entries, previously top3 still got 1-2 items
    // (so the podium was skipped) while rest = entries.skip(3) was also
    // empty — nothing rendered at all even though _entries wasn't empty.
    // Below 3 entries, just show everything in the plain list instead.
    final hasPodium = _entries.length >= 3;
    final top3 = hasPodium ? _entries.take(3).toList() : const <LeaderboardEntry>[];
    final rest = hasPodium ? _entries.skip(3).toList() : _entries;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Dark header ────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              color: AppColors.ink,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Leaderboard',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                      color: Colors.white)),
                  const SizedBox(height: 14),
                  // Period tabs
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      _Tab(label: 'Weekly',  active: _period == 'weekly',
                        onTap: () { _period = 'weekly';  _level = null; _load(); }),
                      const SizedBox(width: 6),
                      _Tab(label: 'All-time', active: _period == 'alltime',
                        onTap: () { _period = 'alltime'; _level = null; _load(); }),
                      const SizedBox(width: 6),
                      for (final l in ['N5','N4','N3','N2','N1']) ...[
                        _Tab(label: l, active: _level == l,
                          onTap: () { _level = l; _period = 'alltime'; _load(); }),
                        const SizedBox(width: 6),
                      ],
                    ]),
                  ),
                ],
              ),
            ),

            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(
                      color: AppColors.red, strokeWidth: 2))
                  : _entries.isEmpty
                      ? const Center(child: Text('No data yet. Complete a quiz!',
                          style: TextStyle(color: AppColors.muted)))
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: AppColors.red,
                          child: ListView(
                            padding: const EdgeInsets.all(14),
                            children: [
                              // Podium
                              if (top3.length >= 3) _buildPodium(top3),
                              const SizedBox(height: 12),
                              // Rest of list
                              ...rest.map((e) => _LeaderRow(entry: e)),
                            ],
                          ),
                        ),
            ),

            AppBottomNav(
              currentIndex: 3,
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

  Widget _buildPodium(List<LeaderboardEntry> top) {
    final order = [top[1], top[0], top[2]]; // 2nd, 1st, 3rd visual order
    final heights = [80.0, 108.0, 68.0];
    final sizes   = [46.0, 60.0, 40.0];
    final colors  = [AppColors.muted, AppColors.red, AppColors.blue];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(3, (vi) {
        final e   = order[vi];
        final ht  = heights[vi];
        final sz  = sizes[vi];
        final col = colors[vi];
        return Expanded(
          child: Column(
            children: [
              Icon(vi == 1 ? Icons.emoji_events : Icons.military_tech,
                color: col, size: vi == 1 ? 22 : 16),
              const SizedBox(height: 4),
              CircleAvatar(radius: sz / 2, backgroundColor: col,
                child: Text(e.username[0].toUpperCase(),
                  style: TextStyle(fontSize: sz / 2.5,
                    fontWeight: FontWeight.w700, color: Colors.white))),
              const SizedBox(height: 4),
              Text(e.username, style: const TextStyle(fontSize: 11,
                fontWeight: FontWeight.w600, color: AppColors.ink2),
                overflow: TextOverflow.ellipsis),
              Text('${e.totalScore} pts',
                style: const TextStyle(fontSize: 10, color: AppColors.muted)),
              const SizedBox(height: 4),
              Container(
                height: ht, width: double.infinity,
                decoration: BoxDecoration(
                  color: col.withOpacity(0.12),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                ),
                child: Center(child: Text('#${e.rank}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                    color: col))),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Tab({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: active ? AppColors.red : Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(label, style: TextStyle(
        fontSize: 11, fontWeight: FontWeight.w700,
        color: active ? Colors.white : Colors.white54,
        letterSpacing: 0.3,
      )),
    ),
  );
}

class _LeaderRow extends StatelessWidget {
  final LeaderboardEntry entry;
  const _LeaderRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: entry.isCurrentUser ? AppColors.redLight : AppColors.bg,
        border: Border(
          left: BorderSide(
            color: entry.isCurrentUser ? AppColors.red : Colors.transparent,
            width: 3),
          top:    BorderSide(color: AppColors.border),
          right:  BorderSide(color: AppColors.border),
          bottom: BorderSide(color: AppColors.border),
        ),
        borderRadius: const BorderRadius.only(
          topRight:    Radius.circular(6),
          bottomRight: Radius.circular(6),
        ),
      ),
      child: Row(children: [
        SizedBox(width: 22,
          child: Text('#${entry.rank}',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
              color: entry.isCurrentUser ? AppColors.red : AppColors.muted),
            textAlign: TextAlign.center)),
        const SizedBox(width: 10),
        CircleAvatar(
          radius: 17,
          backgroundColor: entry.isCurrentUser
              ? AppColors.red
              : AppTheme.levelColor(entry.level),
          child: Text(entry.username[0].toUpperCase(),
            style: const TextStyle(fontSize: 12,
              fontWeight: FontWeight.w700, color: Colors.white)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.isCurrentUser ? 'You' : entry.username,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                color: entry.isCurrentUser ? AppColors.red : AppColors.ink)),
            Text('${entry.level} · ${entry.accuracy.toStringAsFixed(0)}% accuracy'
                 ' · ${entry.streakDays}d streak',
              style: const TextStyle(fontSize: 10, color: AppColors.muted)),
          ],
        )),
        Text('${entry.totalScore}',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
            color: entry.isCurrentUser ? AppColors.red : AppColors.ink)),
        const SizedBox(width: 6),
        Icon(
          entry.isCurrentUser ? Icons.trending_up : Icons.remove,
          size: 14,
          color: entry.isCurrentUser ? AppColors.green : AppColors.muted2),
      ]),
    );
  }
}
