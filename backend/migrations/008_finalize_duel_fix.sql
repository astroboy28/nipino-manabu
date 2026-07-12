-- backend/migrations/008_finalize_duel_fix.sql
-- ─── Fix finalize_duel() crash when every participant forfeits ───────────────
-- winner_id was NULL whenever all duel_participants had status='forfeit',
-- and the unconditional INSERT INTO coin_transactions(user_id, ...) then
-- violated its NOT NULL constraint — an uncaught PDOException (500) from
-- duel.php's handleAnswer()/handleForfeit(), triggerable just by both
-- players in a 1v1 duel forfeiting. Mirrors the refund pattern already used
-- by expire_duel_rooms() instead of crediting nobody / crashing.
\c nipino_manabu;

CREATE OR REPLACE FUNCTION finalize_duel(p_room_id INTEGER) RETURNS VOID AS $$
DECLARE
  winner_id    INTEGER;
  total_pot    INTEGER;
  house_cut    INTEGER;
  winner_prize INTEGER;
BEGIN
  -- Determine winner: highest score, then lowest time as tiebreaker
  SELECT user_id INTO winner_id
  FROM duel_participants
  WHERE room_id = p_room_id AND status != 'forfeit'
  ORDER BY score DESC, time_taken_ms ASC
  LIMIT 1;

  IF winner_id IS NULL THEN
    -- Everyone forfeited — nobody to pay out. Refund each participant's
    -- wager instead of crashing or silently keeping the pot.
    UPDATE users u
    SET coins = u.coins + dp.coins_wagered
    FROM duel_participants dp
    WHERE dp.room_id = p_room_id AND dp.user_id = u.id AND dp.coins_wagered > 0;

    INSERT INTO coin_transactions
      (user_id, amount, balance_after, type, reference_id, description)
    SELECT dp.user_id, dp.coins_wagered,
           (SELECT coins FROM users WHERE id = dp.user_id),
           'duel_refund', p_room_id,
           'Duel cancelled — all players forfeited, wager refunded'
    FROM duel_participants dp
    WHERE dp.room_id = p_room_id AND dp.coins_wagered > 0;

    UPDATE duel_rooms
    SET status         = 'finished',
        winner_user_id = NULL,
        prize_coins    = 0,
        finished_at    = NOW()
    WHERE id = p_room_id;
    RETURN;
  END IF;

  -- Total pot = sum of all wagers
  SELECT SUM(coins_wagered) INTO total_pot
  FROM duel_participants WHERE room_id = p_room_id;

  -- 5% house cut (goes to coin reserve, not any user)
  house_cut    := FLOOR(total_pot * 0.05);
  winner_prize := total_pot - house_cut;

  -- Award coins to winner
  UPDATE users SET coins = coins + winner_prize WHERE id = winner_id;

  INSERT INTO coin_transactions
    (user_id, amount, balance_after, type, reference_id, description)
  VALUES (
    winner_id, winner_prize,
    (SELECT coins FROM users WHERE id = winner_id),
    'duel_win', p_room_id,
    'Duel victory — won ' || winner_prize || ' coins'
  );

  -- Update room
  UPDATE duel_rooms
  SET status         = 'finished',
      winner_user_id = winner_id,
      prize_coins    = winner_prize,
      finished_at    = NOW()
  WHERE id = p_room_id;
END;
$$ LANGUAGE plpgsql;
