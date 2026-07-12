-- backend/migrations/004_social_competition.sql
-- ─── Duel rooms, challenge events, invitations, bets, timers ────────────────
\c nipino_manabu;

-- ── App invite links ──────────────────────────────────────────────────────────
-- Each user gets a unique referral code they can share externally
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS referral_code   VARCHAR(12) UNIQUE,
  ADD COLUMN IF NOT EXISTS referred_by_id  INTEGER REFERENCES users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS referral_coins  INTEGER DEFAULT 0;

-- Auto-generate referral codes for existing users
UPDATE users
SET referral_code = UPPER(SUBSTRING(MD5(id::TEXT || uuid::TEXT) FROM 1 FOR 8))
WHERE referral_code IS NULL;

-- Make it NOT NULL after backfill
ALTER TABLE users ALTER COLUMN referral_code SET NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_referral_code ON users(referral_code);

-- ── Duel rooms (user-vs-user, max 3 players, coin bet) ───────────────────────
CREATE TABLE duel_rooms (
  id              SERIAL PRIMARY KEY,
  uuid            UUID DEFAULT uuid_generate_v4() UNIQUE NOT NULL,
  host_user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  level           VARCHAR(2)  NOT NULL CHECK (level IN ('N1','N2','N3','N4','N5')),
  category        VARCHAR(20) NOT NULL,
  question_count  SMALLINT    DEFAULT 10 CHECK (question_count BETWEEN 5 AND 20),
  coin_bet        INTEGER     NOT NULL CHECK (coin_bet BETWEEN 10 AND 1000),
  timed_mode      BOOLEAN     DEFAULT TRUE,   -- timer per question
  seconds_per_q   SMALLINT    DEFAULT 15 CHECK (seconds_per_q BETWEEN 5 AND 60),
  max_players     SMALLINT    DEFAULT 2 CHECK (max_players BETWEEN 2 AND 3),
  status          VARCHAR(20) DEFAULT 'waiting'
                    CHECK (status IN ('waiting','active','finished','cancelled','expired')),
  winner_user_id  INTEGER REFERENCES users(id) ON DELETE SET NULL,
  prize_coins     INTEGER DEFAULT 0,
  started_at      TIMESTAMPTZ,
  finished_at     TIMESTAMPTZ,
  expires_at      TIMESTAMPTZ DEFAULT NOW() + INTERVAL '30 minutes',
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_dr_host    ON duel_rooms(host_user_id);
CREATE INDEX IF NOT EXISTS idx_dr_status  ON duel_rooms(status);
CREATE INDEX IF NOT EXISTS idx_dr_expires ON duel_rooms(expires_at) WHERE status = 'waiting';

-- ── Duel room participants ────────────────────────────────────────────────────
CREATE TABLE duel_participants (
  id              SERIAL PRIMARY KEY,
  room_id         INTEGER NOT NULL REFERENCES duel_rooms(id) ON DELETE CASCADE,
  user_id         INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status          VARCHAR(20) DEFAULT 'joined'
                    CHECK (status IN ('invited','joined','ready','finished','forfeit')),
  score           SMALLINT    DEFAULT 0,
  correct_count   SMALLINT    DEFAULT 0,
  time_taken_ms   INTEGER     DEFAULT 0,  -- milliseconds — tiebreaker
  coins_wagered   INTEGER     DEFAULT 0,
  joined_at       TIMESTAMPTZ DEFAULT NOW(),
  finished_at     TIMESTAMPTZ,
  UNIQUE(room_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_dp_room ON duel_participants(room_id);
CREATE INDEX IF NOT EXISTS idx_dp_user ON duel_participants(user_id);

-- ── Duel answer log (per question, per participant) ───────────────────────────
CREATE TABLE duel_answers (
  id              SERIAL PRIMARY KEY,
  room_id         INTEGER NOT NULL REFERENCES duel_rooms(id) ON DELETE CASCADE,
  user_id         INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  question_id     INTEGER NOT NULL REFERENCES quiz_questions(id),
  question_order  SMALLINT NOT NULL,
  chosen_index    SMALLINT,           -- NULL = timed out
  is_correct      BOOLEAN  DEFAULT FALSE,
  answer_ms       INTEGER  DEFAULT 0, -- ms taken to answer
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(room_id, user_id, question_order)
);

CREATE INDEX IF NOT EXISTS idx_da_room ON duel_answers(room_id);

-- ── Invitations (duel rooms + challenge events) ───────────────────────────────
CREATE TABLE invitations (
  id              SERIAL PRIMARY KEY,
  uuid            UUID DEFAULT uuid_generate_v4() UNIQUE NOT NULL,
  type            VARCHAR(20) NOT NULL CHECK (type IN ('duel','challenge')),
  from_user_id    INTEGER     REFERENCES users(id) ON DELETE SET NULL,  -- NULL = admin
  to_user_id      INTEGER     NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reference_id    INTEGER     NOT NULL, -- duel_rooms.id or challenge_events.id
  status          VARCHAR(20) DEFAULT 'pending'
                    CHECK (status IN ('pending','accepted','declined','expired')),
  message         VARCHAR(200),
  expires_at      TIMESTAMPTZ DEFAULT NOW() + INTERVAL '24 hours',
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_inv_to     ON invitations(to_user_id, status);
CREATE INDEX IF NOT EXISTS idx_inv_from   ON invitations(from_user_id);
CREATE INDEX IF NOT EXISTS idx_inv_ref    ON invitations(type, reference_id);

-- ── Admin challenge events ────────────────────────────────────────────────────
CREATE TABLE challenge_events (
  id              SERIAL PRIMARY KEY,
  uuid            UUID DEFAULT uuid_generate_v4() UNIQUE NOT NULL,
  title           VARCHAR(200) NOT NULL,
  description     TEXT,
  created_by_id   INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  level           VARCHAR(2)  NOT NULL,
  category        VARCHAR(20) NOT NULL,
  question_count  SMALLINT    DEFAULT 15,
  seconds_per_q   SMALLINT    DEFAULT 20,  -- always timed
  prize_coins     INTEGER     NOT NULL CHECK (prize_coins > 0),
  prize_badge_name VARCHAR(100),           -- optional badge for winner
  prize_badge_emoji VARCHAR(10),
  featured        BOOLEAN     DEFAULT FALSE, -- shows on Home screen
  status          VARCHAR(20) DEFAULT 'upcoming'
                    CHECK (status IN ('upcoming','active','finished','cancelled')),
  max_participants INTEGER    DEFAULT 100,
  starts_at       TIMESTAMPTZ NOT NULL,
  ends_at         TIMESTAMPTZ NOT NULL,
  winner_user_id  INTEGER     REFERENCES users(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ce_status   ON challenge_events(status, starts_at);
CREATE INDEX IF NOT EXISTS idx_ce_featured ON challenge_events(featured) WHERE featured = TRUE;

-- ── Challenge event participants ──────────────────────────────────────────────
CREATE TABLE challenge_participants (
  id              SERIAL PRIMARY KEY,
  event_id        INTEGER NOT NULL REFERENCES challenge_events(id) ON DELETE CASCADE,
  user_id         INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  score           SMALLINT DEFAULT 0,
  correct_count   SMALLINT DEFAULT 0,
  time_taken_ms   INTEGER  DEFAULT 0,
  rank_pos        INTEGER,
  coins_awarded   INTEGER  DEFAULT 0,
  completed_at    TIMESTAMPTZ,
  joined_at       TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(event_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_cp_event ON challenge_participants(event_id, score DESC);
CREATE INDEX IF NOT EXISTS idx_cp_user  ON challenge_participants(user_id);

-- ── Quiz session preferences (timer opt-in/out for regular quizzes) ───────────
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS quiz_timed_mode BOOLEAN DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS quiz_seconds_per_q SMALLINT DEFAULT 15
    CHECK (quiz_seconds_per_q BETWEEN 5 AND 60);

-- ── Coin transaction ledger (full audit trail) ────────────────────────────────
CREATE TABLE coin_transactions (
  id              SERIAL PRIMARY KEY,
  user_id         INTEGER     NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  amount          INTEGER     NOT NULL,  -- positive = credit, negative = debit
  balance_after   INTEGER     NOT NULL,
  type            VARCHAR(30) NOT NULL
                    CHECK (type IN (
                      'quiz_reward','streak_bonus','iap_purchase',
                      'duel_bet_debit','duel_win','duel_refund',
                      'challenge_prize','referral_bonus','admin_grant'
                    )),
  reference_id    INTEGER,   -- duel_rooms.id / challenge_events.id / iap_purchases.id
  description     VARCHAR(200),
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ct_user ON coin_transactions(user_id, created_at DESC);

-- ── Function: expire old duel rooms (called by cron) ─────────────────────────
CREATE OR REPLACE FUNCTION expire_duel_rooms() RETURNS INTEGER AS $$
DECLARE
  expired_count INTEGER := 0;
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT id FROM duel_rooms
    WHERE status = 'waiting' AND expires_at < NOW()
  LOOP
    -- Refund coin bets to all participants
    UPDATE users u
    SET coins = coins + dp.coins_wagered
    FROM duel_participants dp
    WHERE dp.room_id = rec.id
      AND dp.user_id = u.id
      AND dp.coins_wagered > 0;

    -- Insert refund transactions
    INSERT INTO coin_transactions (user_id, amount, balance_after, type, reference_id, description)
    SELECT dp.user_id, dp.coins_wagered,
           (SELECT coins FROM users WHERE id = dp.user_id),
           'duel_refund', rec.id, 'Duel expired — bet refunded'
    FROM duel_participants dp
    WHERE dp.room_id = rec.id AND dp.coins_wagered > 0;

    UPDATE duel_rooms SET status = 'expired' WHERE id = rec.id;
    expired_count := expired_count + 1;
  END LOOP;
  RETURN expired_count;
END;
$$ LANGUAGE plpgsql;

-- ── Function: finalize duel (award winner, handle ties) ──────────────────────
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
