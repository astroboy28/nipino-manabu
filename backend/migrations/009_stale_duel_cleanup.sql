-- backend/migrations/009_stale_duel_cleanup.sql
-- ─── Auto-finalize duels that never got a chance to finish ───────────────────
-- expire_duel_rooms() only ever swept status='waiting' rooms. Once a duel went
-- 'active' there was no timeout at all: a player who abandons the app mid-duel
-- (killed process, dead connection) without hitting /duel/forfeit never
-- reaches finished/forfeit, finalize_duel() is never called, and the room —
-- plus both players' wagered coins — is stuck forever. The duel:questions
-- Redis cache backing /duel/answer also only lives 2 hours (see duel.php
-- handleCreate), so an active duel already can't function past that point
-- regardless; use the same 2-hour bound here.
\c nipino_manabu;

CREATE OR REPLACE FUNCTION expire_stale_active_duels() RETURNS INTEGER AS $$
DECLARE
  rec RECORD;
  finalized_count INTEGER := 0;
BEGIN
  FOR rec IN
    SELECT id FROM duel_rooms
    WHERE status = 'active' AND started_at < NOW() - INTERVAL '2 hours'
  LOOP
    -- Whoever never finished is treated as having forfeited (matches what
    -- happens if they'd tapped "forfeit" themselves); finalize_duel already
    -- handles the all-forfeited case by refunding everyone (migration 008).
    UPDATE duel_participants
    SET status = 'forfeit', finished_at = NOW()
    WHERE room_id = rec.id AND status NOT IN ('finished', 'forfeit');

    PERFORM finalize_duel(rec.id);
    finalized_count := finalized_count + 1;
  END LOOP;
  RETURN finalized_count;
END;
$$ LANGUAGE plpgsql;
