c = open('lib/screens/duel/duel_screen.dart', encoding='utf-8').read()

# Fix 1: Add sound service import
old_imports = "import '../../services/auth_provider.dart';"
new_imports = "import '../../services/auth_provider.dart';\nimport '../../services/sound_service.dart';\nimport 'package:flutter/services.dart';"
if old_imports in c:
    c = c.replace(old_imports, new_imports)
    print("1. Sound import added!")
else:
    print("1. NOT FOUND")

# Fix 2: Fix the empty room card builder
old_builder = "                      itemBuilder: (_, i) => const SizedBox(),"
new_builder = """                      itemBuilder: (_, i) => _OpenRoomCard(
                        room: _openRooms[i],
                        onJoin: () => _joinRoom(_openRooms[i]),
                      ),"""
if old_builder in c:
    c = c.replace(old_builder, new_builder)
    print("2. Room card builder fixed!")
else:
    print("2. NOT FOUND")

# Fix 3: Add _joinRoom method before _showError
old_show_error = "  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar("
new_show_error = """  Future<void> _joinRoom(OpenDuelRoom room) async {
    final sound = SoundService();
    await sound.init();
    HapticFeedback.mediumImpact();
    final res = await SocialApiService.joinDuel(room.uuid);
    if (!mounted) return;
    if (res.success && res.data != null) {
      sound.playTap();
      Navigator.push(context,
        MaterialPageRoute(builder: (_) => DuelLobbyScreen(roomUuid: room.uuid)));
    } else {
      sound.playWrong();
      _showError(res.error ?? 'Failed to join duel');
    }
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar("""
if old_show_error in c:
    c = c.replace(old_show_error, new_show_error)
    print("3. _joinRoom method added!")
else:
    print("3. NOT FOUND")

# Fix 4: Add _OpenRoomCard widget before _EmptyState
old_empty_state = "class _EmptyState extends StatelessWidget {"
new_room_card = """// ─────────────────────────────────────────────────────────────────────────────
// Open Room Card
// ─────────────────────────────────────────────────────────────────────────────
class _OpenRoomCard extends StatelessWidget {
  final OpenDuelRoom room;
  final VoidCallback onJoin;
  const _OpenRoomCard({required this.room, required this.onJoin});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
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
      ]),
    );
  }
}

class _EmptyState extends StatelessWidget {"""

if old_empty_state in c:
    c = c.replace(old_empty_state, new_room_card)
    print("4. _OpenRoomCard widget added!")
else:
    print("4. NOT FOUND")

# Fix 5: Add sound effects to duel result
old_result_build = "    final won = result.winnerId == currentUserId;"
new_result_build = """    final won = result.winnerId == currentUserId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final sound = SoundService();
      await sound.init();
      if (won) { await sound.playCoin(); }
      else { await sound.playWrong(); }
    });"""
if old_result_build in c:
    c = c.replace(old_result_build, new_result_build)
    print("5. Win/lose sounds added!")
else:
    print("5. NOT FOUND")

# Fix 6: Check DuelLobbyScreen constructor
idx6 = c.find('class DuelLobbyScreen')
if idx6 > -1:
    print("6. DuelLobbyScreen found:")
    print(repr(c[idx6:idx6+200]))
else:
    print("6. DuelLobbyScreen NOT FOUND")

open('lib/screens/duel/duel_screen.dart', 'w', encoding='utf-8').write(c)
print("\nduel_screen.dart saved!")
