-- ═══════════════════════════════════════════════════════════════════════════
-- Nipino-Manabu — PostgreSQL Schema
-- Run: psql -U postgres -f schema.sql
-- ═══════════════════════════════════════════════════════════════════════════

CREATE DATABASE nipino_manabu
  ENCODING    'UTF8'
  LC_COLLATE  'en_US.UTF-8'
  LC_CTYPE    'en_US.UTF-8'
  TEMPLATE    template0;

\c nipino_manabu;

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ── Users ────────────────────────────────────────────────────────────────────
CREATE TABLE users (
  id              SERIAL PRIMARY KEY,
  uuid            UUID DEFAULT uuid_generate_v4() UNIQUE NOT NULL,
  username        VARCHAR(50)  NOT NULL UNIQUE,
  email           VARCHAR(255) NOT NULL UNIQUE,
  password_hash   VARCHAR(255) NOT NULL,         -- bcrypt cost ≥12
  coins           INTEGER      DEFAULT 100 CHECK (coins >= 0),
  streak_days     INTEGER      DEFAULT 0,
  last_quiz_date  DATE,
  current_level   VARCHAR(2)   DEFAULT 'N5',
  total_score     INTEGER      DEFAULT 0,
  avatar_url      VARCHAR(500),
  is_verified     BOOLEAN      DEFAULT FALSE,
  is_active       BOOLEAN      DEFAULT TRUE,
  fcm_token       VARCHAR(500),                  -- Firebase push token
  created_at      TIMESTAMPTZ  DEFAULT NOW(),
  updated_at      TIMESTAMPTZ  DEFAULT NOW()
);

CREATE INDEX idx_users_email    ON users(email);
CREATE INDEX idx_users_username ON users(username);

-- ── Refresh tokens (JWT) ──────────────────────────────────────────────────────
CREATE TABLE refresh_tokens (
  id          SERIAL PRIMARY KEY,
  user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash  VARCHAR(255) NOT NULL UNIQUE,  -- SHA-256 hash of actual token
  expires_at  TIMESTAMPTZ  NOT NULL,
  created_at  TIMESTAMPTZ  DEFAULT NOW(),
  revoked_at  TIMESTAMPTZ
);

CREATE INDEX idx_rt_user   ON refresh_tokens(user_id);
CREATE INDEX idx_rt_token  ON refresh_tokens(token_hash);

-- ── Quiz questions ────────────────────────────────────────────────────────────
CREATE TABLE quiz_questions (
  id            SERIAL PRIMARY KEY,
  level         VARCHAR(2)   NOT NULL CHECK (level IN ('N1','N2','N3','N4','N5')),
  category      VARCHAR(20)  NOT NULL CHECK (category IN
                  ('kanji','vocabulary','grammar','listening')),
  question_text TEXT         NOT NULL,
  question_type VARCHAR(20)  NOT NULL CHECK (question_type IN
                  ('reading','meaning','grammar_fill','listening')),
  options       JSONB        NOT NULL,          -- ["opt1","opt2","opt3","opt4"]
  correct_index SMALLINT     NOT NULL CHECK (correct_index BETWEEN 0 AND 3),
  explanation   TEXT         NOT NULL,
  memory_tip    TEXT,
  point_value   SMALLINT     DEFAULT 10,
  is_active     BOOLEAN      DEFAULT TRUE,
  created_at    TIMESTAMPTZ  DEFAULT NOW()
);

CREATE INDEX idx_qq_level    ON quiz_questions(level);
CREATE INDEX idx_qq_category ON quiz_questions(level, category);

-- ── Original quiz content — 10 questions per level (N5→N1) ──────────────────
INSERT INTO quiz_questions
  (level, category, question_text, question_type, options, correct_index,
   explanation, memory_tip, point_value)
VALUES

-- ════ N5 ═════════════════════════════════════════════════════════════════════
('N5','kanji','山','reading',
 '["やま","かわ","うみ","そら"]', 0,
 '山 means "mountain". Reading: やま (yama). One of the most basic N5 kanji.',
 'Imagine a mountain shape: the three strokes look like three mountain peaks!', 10),

('N5','vocabulary','りんご','meaning',
 '["Apple","Orange","Banana","Grape"]', 0,
 'りんご means Apple in Japanese. It is written in hiragana at N5 level.',
 'りんご sounds like "ringo" — think of Ringo Starr holding an apple!', 10),

('N5','grammar','わたしは学生___。','grammar_fill',
 '["です","ます","でした","ません"]', 0,
 'です is the polite copula for statements (am/is/are). わたしは学生です = I am a student.',
 'です ends almost every simple N5 sentence — it''s the "is/am/are" of Japanese!', 10),

-- ════ N4 ═════════════════════════════════════════════════════════════════════
('N4','kanji','友達','reading',
 '["ともだち","ゆうじん","なかま","きょうだい"]', 0,
 '友達 (ともだち tomodachi) means "friend". A core N4 vocabulary word.',
 '友 = friend/companionship. 達 = plural suffix. Together: your group of companions!', 15),

('N4','vocabulary','電話','meaning',
 '["Telephone","Television","Radio","Computer"]', 0,
 '電話 (でんわ denwa) means telephone. 電 = electricity, 話 = talk/speak.',
 'DENwa = DENse communication WAve — electricity + talk = telephone!', 15),

('N4','grammar','雨が降る___、傘を持ってきた。','grammar_fill',
 '["から","ので","のに","けれど"]', 1,
 'ので is used for objective, polite causal reasoning. "Because it will rain, I brought an umbrella."',
 'ので = softer "because" — more polite than から, used when the reason is objective.', 15),

-- ════ N3 ═════════════════════════════════════════════════════════════════════
('N3','kanji','勉強','reading',
 '["べんきょう","べんりょう","がくしゅう","べんきん"]', 0,
 '勉強 (べんきょう benkyou) means "study/studying". Essential N3 compound.',
 '勉 = effort, 強 = strong. Studying = making the effort to become strong!', 20),

('N3','vocabulary','経験','meaning',
 '["Experience","Knowledge","Education","Memory"]', 0,
 '経験 (けいけん keiken) means experience. 経 = pass through, 験 = examine.',
 'Think: you KEIKEN (go through) experiences to build knowledge!', 20),

-- ════ N2 ═════════════════════════════════════════════════════════════════════
('N2','grammar','彼が来る___信じている。','grammar_fill',
 '["ことを","のを","はずを","わけを"]', 0,
 'ことを is used to nominalize a clause as the object of 信じる (to believe).',
 'こと turns a verb clause into a noun — "the fact that he will come"', 25),

-- ════ N1 ═════════════════════════════════════════════════════════════════════
('N1','vocabulary','逡巡','meaning',
 '["Hesitation","Determination","Regret","Anticipation"]', 0,
 '逡巡 (しゅんじゅん shunjun) means hesitation or vacillation. Rare N1 vocabulary.',
 'しゅんじゅん sounds like "shun-shun" — like someone shying away, hesitating!', 30);

-- ── User level progress ───────────────────────────────────────────────────────
CREATE TABLE user_level_progress (
  id               SERIAL PRIMARY KEY,
  user_id          INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  level            VARCHAR(2) NOT NULL,
  completed_topics INTEGER    DEFAULT 0,
  total_topics     INTEGER    DEFAULT 6,
  exam_unlocked    BOOLEAN    DEFAULT FALSE,
  updated_at       TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, level)
);

-- ── Quiz results (history) ────────────────────────────────────────────────────
CREATE TABLE quiz_results (
  id                  SERIAL PRIMARY KEY,
  user_id             INTEGER    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  level               VARCHAR(2) NOT NULL,
  category            VARCHAR(20) NOT NULL,
  correct_count       SMALLINT   NOT NULL,
  total_count         SMALLINT   NOT NULL,
  time_taken_seconds  INTEGER    NOT NULL,
  coins_earned        INTEGER    DEFAULT 0,
  score_percent       NUMERIC(5,2) GENERATED ALWAYS AS
                        (CASE WHEN total_count = 0 THEN 0
                         ELSE ROUND((correct_count::NUMERIC/total_count)*100, 2)
                         END) STORED,
  taken_at            TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_qr_user  ON quiz_results(user_id);
CREATE INDEX idx_qr_level ON quiz_results(level);
CREATE INDEX idx_qr_taken ON quiz_results(taken_at);

-- ── Leaderboard (materialized weekly view) ────────────────────────────────────
CREATE TABLE leaderboard_snapshots (
  id          SERIAL PRIMARY KEY,
  user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  period      VARCHAR(10) NOT NULL, -- 'weekly' | 'alltime'
  level       VARCHAR(2),           -- NULL = all levels
  total_score INTEGER  DEFAULT 0,
  accuracy    NUMERIC(5,2),
  rank_pos    INTEGER,
  snapshot_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, period, level)
);

CREATE INDEX idx_lb_period ON leaderboard_snapshots(period, rank_pos);

-- ── Badges ────────────────────────────────────────────────────────────────────
CREATE TABLE badges (
  id          SERIAL PRIMARY KEY,
  name        VARCHAR(100) NOT NULL,
  description TEXT         NOT NULL,
  icon_emoji  VARCHAR(10)  NOT NULL,
  condition   JSONB        NOT NULL  -- {"type":"streak","value":7}
);

INSERT INTO badges (name, description, icon_emoji, condition) VALUES
  ('First Step',      'Complete your first quiz',          '🌟', '{"type":"quizzes_completed","value":1}'),
  ('Streak Starter',  'Maintain a 7-day streak',           '🔥', '{"type":"streak","value":7}'),
  ('Coin Collector',  'Earn 500 coins',                    '🪙', '{"type":"coins","value":500}'),
  ('N5 Graduate',     'Complete all N5 topics',            '🎓', '{"type":"level_complete","value":"N5"}'),
  ('N4 Scholar',      'Complete all N4 topics',            '📚', '{"type":"level_complete","value":"N4"}'),
  ('Silver Scholar',  'Score 80%+ on any quiz',            '🥈', '{"type":"score_percent","value":80}'),
  ('Gold Scholar',    'Score 90%+ on any N2/N1 quiz',      '🥇', '{"type":"score_percent_n2n1","value":90}'),
  ('Speed Runner',    'Complete a 10-Q quiz in under 2min','⚡', '{"type":"speed","value":120}'),
  ('Perfect Score',   'Score 100% on any quiz',            '💯', '{"type":"score_percent","value":100}'),
  ('N1 Master',       'Complete all N1 topics',            '🏆', '{"type":"level_complete","value":"N1"}');

CREATE TABLE user_badges (
  id        SERIAL PRIMARY KEY,
  user_id   INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  badge_id  INTEGER NOT NULL REFERENCES badges(id),
  earned_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, badge_id)
);

-- ── IAP purchases ─────────────────────────────────────────────────────────────
CREATE TABLE iap_purchases (
  id            SERIAL PRIMARY KEY,
  user_id       INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  product_id    VARCHAR(100) NOT NULL,
  platform      VARCHAR(10)  NOT NULL CHECK (platform IN ('ios','android')),
  receipt_hash  VARCHAR(255) NOT NULL UNIQUE, -- SHA-256 of receipt, prevents replay
  coins_granted INTEGER      DEFAULT 0,
  verified_at   TIMESTAMPTZ  DEFAULT NOW()
);

-- ── Auto-update updated_at trigger ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ── Weekly leaderboard refresh function ──────────────────────────────────────
CREATE OR REPLACE FUNCTION refresh_leaderboard() RETURNS VOID AS $$
BEGIN
  -- All-time
  -- Accuracy must be averaged over the user's ENTIRE quiz_results history,
  -- not just the last 7 days — the 7-day cutoff belongs to the weekly
  -- bucket below. Reusing it here silently zeroed out accuracy for anyone
  -- whose most recent quiz was more than a week old, even though their
  -- total_score (read from the unfiltered users.total_score column) still
  -- showed correctly. Confirmed live: users with real all-time history but
  -- no activity in the last 7 days showed accuracy=0.00 despite nonzero score.
  DELETE FROM leaderboard_snapshots WHERE period = 'alltime' AND level IS NULL;
  INSERT INTO leaderboard_snapshots (user_id, period, level, total_score, accuracy, rank_pos)
  SELECT u.id, 'alltime', NULL, u.total_score,
    COALESCE(AVG(qr.score_percent), 0),
    ROW_NUMBER() OVER (ORDER BY u.total_score DESC)
  FROM users u
  LEFT JOIN quiz_results qr ON qr.user_id = u.id
  WHERE u.is_active = TRUE
  GROUP BY u.id
  ON CONFLICT (user_id, period, level) DO UPDATE
    SET total_score=EXCLUDED.total_score,
        accuracy=EXCLUDED.accuracy,
        rank_pos=EXCLUDED.rank_pos,
        snapshot_at=NOW();

  -- Weekly
  DELETE FROM leaderboard_snapshots WHERE period = 'weekly' AND level IS NULL;
  INSERT INTO leaderboard_snapshots (user_id, period, level, total_score, accuracy, rank_pos)
  SELECT u.id, 'weekly', NULL,
    COALESCE(SUM(qr.correct_count * 10), 0),
    COALESCE(AVG(qr.score_percent), 0),
    ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(qr.correct_count * 10), 0) DESC)
  FROM users u
  LEFT JOIN quiz_results qr ON qr.user_id = u.id
    AND qr.taken_at > NOW() - INTERVAL '7 days'
  WHERE u.is_active = TRUE
  GROUP BY u.id
  ON CONFLICT (user_id, period, level) DO UPDATE
    SET total_score=EXCLUDED.total_score,
        accuracy=EXCLUDED.accuracy,
        rank_pos=EXCLUDED.rank_pos,
        snapshot_at=NOW();

  -- Per-level, all-time — the app forces period=alltime and sets a level
  -- filter when the user taps an N5..N1 tab (see leaderboard_screen.dart),
  -- but no snapshot rows with a non-null level were ever generated, so
  -- backend/api/leaderboard.php's WHERE level=? always matched zero rows
  -- and every level tab showed empty/0% for every user.
  DELETE FROM leaderboard_snapshots WHERE period = 'alltime' AND level IS NOT NULL;
  INSERT INTO leaderboard_snapshots (user_id, period, level, total_score, accuracy, rank_pos)
  SELECT u.id, 'alltime', qr.level,
    SUM(qr.correct_count * 10),
    COALESCE(AVG(qr.score_percent), 0),
    ROW_NUMBER() OVER (PARTITION BY qr.level ORDER BY SUM(qr.correct_count * 10) DESC)
  FROM users u
  JOIN quiz_results qr ON qr.user_id = u.id
  WHERE u.is_active = TRUE
  GROUP BY u.id, qr.level
  ON CONFLICT (user_id, period, level) DO UPDATE
    SET total_score=EXCLUDED.total_score,
        accuracy=EXCLUDED.accuracy,
        rank_pos=EXCLUDED.rank_pos,
        snapshot_at=NOW();
END;
$$ LANGUAGE plpgsql;
