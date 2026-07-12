-- backend/migrations/002_auth_and_monitoring.sql
-- ─── Run after 001_schema.sql ────────────────────────────────────────────────

\c nipino_manabu;

-- ── Email verification columns on users ──────────────────────────────────────
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS is_verified          BOOLEAN     DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS email_verify_token   VARCHAR(255),
  ADD COLUMN IF NOT EXISTS email_verify_expires TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_users_verify_token
  ON users(email_verify_token) WHERE email_verify_token IS NOT NULL;

-- ── Password reset tokens ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS password_reset_tokens (
  id         SERIAL PRIMARY KEY,
  user_id    INTEGER      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash VARCHAR(255) NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ  NOT NULL,
  used       BOOLEAN      DEFAULT FALSE,
  created_at TIMESTAMPTZ  DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_prt_token  ON password_reset_tokens(token_hash);
CREATE INDEX IF NOT EXISTS idx_prt_user   ON password_reset_tokens(user_id);

-- ── Error log (server-side structured logging) ────────────────────────────────
CREATE TABLE IF NOT EXISTS error_log (
  id         SERIAL PRIMARY KEY,
  level      VARCHAR(10)  NOT NULL DEFAULT 'error', -- error|warn|info
  context    VARCHAR(100),
  message    TEXT         NOT NULL,
  meta       JSONB,
  user_id    INTEGER      REFERENCES users(id) ON DELETE SET NULL,
  ip_address INET,
  created_at TIMESTAMPTZ  DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_errlog_level   ON error_log(level, created_at);
CREATE INDEX IF NOT EXISTS idx_errlog_context ON error_log(context, created_at);

-- Auto-delete logs older than 90 days (run via cron)
CREATE OR REPLACE FUNCTION purge_old_logs() RETURNS VOID AS $$
BEGIN
  DELETE FROM error_log WHERE created_at < NOW() - INTERVAL '90 days';
END;
$$ LANGUAGE plpgsql;

-- ── FCM notification log ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS notification_log (
  id         SERIAL PRIMARY KEY,
  user_id    INTEGER      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type       VARCHAR(50)  NOT NULL, -- streak_reminder|badge|level_complete
  title      VARCHAR(200) NOT NULL,
  body       TEXT         NOT NULL,
  sent_at    TIMESTAMPTZ  DEFAULT NOW(),
  delivered  BOOLEAN      DEFAULT NULL -- NULL = unknown, TRUE = delivered
);

CREATE INDEX IF NOT EXISTS idx_notif_user ON notification_log(user_id, sent_at);

-- ── Cleanup expired tokens (run via cron daily) ───────────────────────────────
CREATE OR REPLACE FUNCTION cleanup_expired_tokens() RETURNS VOID AS $$
BEGIN
  -- Remove expired password reset tokens
  DELETE FROM password_reset_tokens
  WHERE expires_at < NOW() - INTERVAL '7 days';

  -- Remove expired/revoked refresh tokens
  DELETE FROM refresh_tokens
  WHERE expires_at < NOW() OR revoked_at < NOW() - INTERVAL '7 days';

  -- Clear expired email verify tokens from users
  UPDATE users
  SET email_verify_token=NULL, email_verify_expires=NULL
  WHERE email_verify_expires < NOW() AND is_verified=FALSE;
END;
$$ LANGUAGE plpgsql;
