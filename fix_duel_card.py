c = open('lib/screens/duel/duel_screen.dart', encoding='utf-8').read()

# Find and replace the entire _OpenRoomCard build method
old = """  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
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
      ]),
    );
  }
}"""

new = """  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.redLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(child: Text(room.level,
                    style: const TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w700, color: AppColors.red))),
                ),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${room.level} · ${room.category}',
                    style: const TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w700, color: AppColors.ink)),
                  Text('Host: ${room.host}',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ]),
              ]),
              ElevatedButton(
                onPressed: onJoin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Join',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.people_outline, size: 14, color: AppColors.muted),
            const SizedBox(width: 4),
            Text('${room.joined}/${room.maxPlayers} players',
              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            const SizedBox(width: 12),
            const Icon(Icons.monetization_on, size: 14, color: AppColors.gold),
            const SizedBox(width: 4),
            Text('${room.coinBet} coins bet',
              style: const TextStyle(fontSize: 12, color: AppColors.gold,
                fontWeight: FontWeight.w600)),
            if (room.timedMode) ...[
              const SizedBox(width: 12),
              const Icon(Icons.timer_outlined, size: 14, color: AppColors.muted),
              const SizedBox(width: 4),
              Text('${room.secondsPerQ}s/q',
                style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ]),
        ],
      ),
    );
  }
}"""

if old in c:
    c = c.replace(old, new)
    open('lib/screens/duel/duel_screen.dart', 'w', encoding='utf-8').write(c)
    print("Duel card rewritten!")
else:
    print("NOT FOUND")
    idx = c.find('class _OpenRoomCard')
    print(repr(c[idx:idx+200]))
