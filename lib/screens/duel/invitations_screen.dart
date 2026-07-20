// lib/screens/duel/invitations_screen.dart
// ─── Pending invitations (duels + challenges) + referral share ───────────────
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../../models/social_models.dart';
import '../../services/social_api_service.dart';
import '../duel/duel_screen.dart';
import '../challenge/challenge_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Invitations inbox
// ─────────────────────────────────────────────────────────────────────────────
class InvitationsScreen extends StatefulWidget {
  const InvitationsScreen({super.key});
  @override State<InvitationsScreen> createState() =>
      _InvitationsScreenState();
}

class _InvitationsScreenState extends State<InvitationsScreen> {
  List<Invitation> _invites = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await SocialApiService.getInvitations();
    if (mounted) {
      setState(() { _invites = res.data ?? []; _loading = false; });
    }
  }

  Future<void> _respond(Invitation inv, String action) async {
    final res = await SocialApiService.respondInvitation(
        invUuid: inv.uuid, action: action);
    if (!mounted) return;

    if (res.success) {
      if (action == 'accept') {
        final refId    = res.data?['reference_id'];
        final type     = res.data?['type'];
        final roomUuid = res.data?['room_uuid'] as String?;
        if (type == 'duel' && roomUuid != null) {
          // Accepting a duel invite only marked the invitation accepted —
          // the invitee still isn't a paying participant until /duel/join
          // is actually called (previously this navigated straight to the
          // lobby using the invitation's own uuid, which isn't the room's
          // uuid, and never joined the room at all).
          final joinRes = await SocialApiService.joinDuel(roomUuid);
          if (!mounted) return;
          if (joinRes.success) {
            Navigator.push(context, MaterialPageRoute(
                builder: (_) => DuelLobbyScreen(roomUuid: roomUuid)));
          } else {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(joinRes.error ?? 'Could not join duel room.'),
                behavior: SnackBarBehavior.floating));
          }
        } else if (type == 'challenge' && refId != null) {
          final evtRes = await SocialApiService.getChallenge(refId as int);
          if (mounted && evtRes.success) {
            Navigator.push(context, MaterialPageRoute(
                builder: (_) =>
                    ChallengeDetailScreen(event: evtRes.data!)));
          }
        }
      }
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.error ?? 'Action failed'),
            behavior: SnackBarBehavior.floating));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Invitations'),
        bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1), child: Divider(height: 1))),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(
                color: AppColors.red, strokeWidth: 2))
            : _invites.isEmpty
                ? const Center(
                    child: Text('No pending invitations.',
                        style: TextStyle(color: AppColors.muted)))
                : RefreshIndicator(
                    onRefresh: _load,
                    color: AppColors.red,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _invites.length,
                      itemBuilder: (_, i) => _InviteCard(
                        invite: _invites[i],
                        onAccept: () => _respond(_invites[i], 'accept'),
                        onDecline: () => _respond(_invites[i], 'decline'),
                      ),
                    ),
                  ),
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  final Invitation invite;
  final VoidCallback onAccept, onDecline;
  const _InviteCard({
    required this.invite,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final isDuel      = invite.type == 'duel';
    final details     = invite.details ?? {};
    final fromName    = invite.fromUsername ?? 'Admin';
    final coinBet     = details['coin_bet'];
    final prizeCoins  = details['prize_coins'];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(
          left: BorderSide(
              color: isDuel ? AppColors.red : AppColors.gold, width: 4),
          top:    const BorderSide(color: AppColors.border),
          right:  const BorderSide(color: AppColors.border),
          bottom: const BorderSide(color: AppColors.border),
        ),
        borderRadius: const BorderRadius.only(
            topRight: Radius.circular(8), bottomRight: Radius.circular(8)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(isDuel ? Icons.sports_esports : Icons.emoji_events,
                color: isDuel ? AppColors.red : AppColors.gold, size: 20),
            const SizedBox(width: 8),
            Text(isDuel ? 'Duel invitation' : 'Challenge invitation',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700,
                    color: isDuel ? AppColors.red : const Color(0xFFE88C00),
                    letterSpacing: 0.3)),
          ]),
          const SizedBox(height: 8),
          Text('From: $fromName',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600,
                  color: AppColors.ink)),
          if (invite.message != null && invite.message!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('"${invite.message}"',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.muted,
                    fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 8),
          // Details row
          Wrap(spacing: 8, children: [
            if (details['level'] != null)
              _Chip(label: details['level'].toString()),
            if (coinBet != null)
              _Chip(label: 'Bet: $coinBet 🪙', color: AppColors.red),
            if (prizeCoins != null)
              _Chip(label: 'Prize: $prizeCoins 🪙', color: AppColors.gold),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: onDecline,
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 10)),
              child: const Text('Decline'),
            )),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton(
              onPressed: onAccept,
              style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10)),
              child: const Text('Accept'),
            )),
          ]),
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, this.color = AppColors.muted});
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4)),
    child: Text(label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
            color: color)),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Referral / invite-a-friend screen
// ─────────────────────────────────────────────────────────────────────────────
class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});
  @override State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _copied  = false;
  final _codeCtrl = TextEditingController();
  bool _claiming = false;
  String? _claimMsg;
  bool _claimOk = false;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _codeCtrl.dispose(); super.dispose(); }

  Future<void> _claimCode() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() { _claiming = true; _claimMsg = null; });
    final res = await SocialApiService.claimReferral(code);
    if (!mounted) return;
    setState(() {
      _claiming = false;
      _claimOk  = res.success;
      _claimMsg = res.success
          ? '🎉 Code redeemed! Coins added to your balance.'
          : (res.data?['message'] ?? res.error ?? 'Could not redeem that code.');
    });
    if (res.success) {
      _codeCtrl.clear();
      _load(); // refresh coins-earned stat
    }
  }

  Future<void> _load() async {
    final res = await SocialApiService.getMyReferralLink();
    if (mounted) {
      setState(() {
        _data    = res.data;
        _loading = false;
      });
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  int _friendsInvited() {
    final coinsEarned  = (_data?['coins_earned']   as num?) ?? 0;
    final rewardPerRef = (_data?['reward_per_ref'] as num?) ?? 50;
    if (rewardPerRef <= 0) return 0;
    return coinsEarned ~/ rewardPerRef;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Invite friends'),
        bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1), child: Divider(height: 1))),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(
                color: AppColors.red, strokeWidth: 2))
            : ListView(padding: const EdgeInsets.all(20), children: [

                // Hero card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(children: [
                    const Icon(Icons.card_giftcard,
                        color: Colors.white, size: 40),
                    const SizedBox(height: 12),
                    const Text('Invite friends — earn coins!',
                        style: TextStyle(fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text(
                      'You earn ${_data?['reward_per_ref'] ?? 50} coins for '
                      'each friend who joins.\nThey get '
                      '${_data?['new_user_bonus'] ?? 50} bonus coins too!',
                      style: const TextStyle(
                          fontSize: 13, color: Colors.white70,
                          height: 1.5),
                      textAlign: TextAlign.center),
                  ]),
                ),
                const SizedBox(height: 20),

                // Stats
                Row(children: [
                  _StatBox(
                    label: 'Friends invited',
                    // Hard `as int` casts here threw a TypeError if the
                    // backend ever serialized either field as a double
                    // (e.g. from a NUMERIC column) — read as num and guard
                    // divide-by-zero instead.
                    value: '${_friendsInvited()}',
                    color: AppColors.red,
                  ),
                  const SizedBox(width: 12),
                  _StatBox(
                    label: 'Coins earned',
                    value: '${_data?['coins_earned'] ?? 0}',
                    color: AppColors.gold,
                  ),
                ]),
                const SizedBox(height: 20),

                // Referral link
                const Text('Your invite link',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: AppColors.ink)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: AppColors.bg2,
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(8)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    SelectableText(
                      _data?['web_link'] ?? '',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.red,
                          fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: ElevatedButton.icon(
                        onPressed: () => _copy(_data?['web_link'] ?? ''),
                        icon: Icon(
                            _copied ? Icons.check : Icons.copy, size: 16),
                        label: Text(_copied ? 'Copied!' : 'Copy link'),
                        style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                vertical: 10)),
                      )),
                    ]),
                  ]),
                ),
                const SizedBox(height: 14),

                // Share message
                const Text('Or share this message',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: AppColors.ink)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: AppColors.bg2,
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(8)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(_data?['share_text'] ?? '',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.ink,
                            height: 1.5)),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () =>
                          _copy(_data?['share_text'] ?? ''),
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy message'),
                    ),
                  ]),
                ),
                const SizedBox(height: 20),

                // How it works
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: AppColors.bg2,
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(8)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('How it works',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700,
                            color: AppColors.ink)),
                    const SizedBox(height: 10),
                    _Step(n: '1', text: 'Share your invite link with friends'),
                    _Step(n: '2',
                        text: 'They download and register using your link'),
                    _Step(n: '3',
                        text:
                            'Both of you receive ${_data?['reward_per_ref'] ?? 50} bonus coins instantly'),
                    _Step(n: '4',
                        text: 'No limit — invite as many friends as you like!',
                        isLast: true),
                  ]),
                ),
                const SizedBox(height: 20),

                // Manual redemption — for a code received any way other than
                // tapping a link directly (read aloud, texted as plain text,
                // or a link tapped before the app was installed).
                const Text('Have a friend\'s code?',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: AppColors.ink)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(
                    controller: _codeCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'Enter code',
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  )),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _claiming ? null : _claimCode,
                    child: _claiming
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Redeem'),
                  ),
                ]),
                if (_claimMsg != null) ...[
                  const SizedBox(height: 8),
                  Text(_claimMsg!,
                      style: TextStyle(fontSize: 12,
                          color: _claimOk ? AppColors.green : AppColors.red)),
                ],
              ]),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatBox(
      {required this.label, required this.value, required this.color});
  @override Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppColors.bg2,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8)),
      child: Column(children: [
        Text(value,
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppColors.muted),
            textAlign: TextAlign.center),
      ]),
    ),
  );
}

class _Step extends StatelessWidget {
  final String n, text;
  final bool isLast;
  const _Step({required this.n, required this.text, this.isLast = false});
  @override Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 22, height: 22,
        margin: const EdgeInsets.only(right: 10, top: 1),
        decoration: BoxDecoration(
            color: AppColors.red, shape: BoxShape.circle),
        child: Center(child: Text(n,
            style: const TextStyle(
                color: Colors.white, fontSize: 11,
                fontWeight: FontWeight.w700))),
      ),
      Expanded(child: Text(text,
          style: const TextStyle(fontSize: 13, color: AppColors.muted,
              height: 1.4))),
    ]),
  );
}
