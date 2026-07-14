-- backend/migrations/012_deletion_cancel_tokens.sql
-- ─── Unauthenticated token for the "Cancel Deletion" email link ──────────────
-- handleRequestDeletion sets is_active=FALSE immediately and revokes every
-- refresh token, so the only way back in is the already-live access token —
-- which expires in JWT_ACCESS_TTL (15 min by default). Auth::requireAuth()
-- never re-checks the DB, so an expired-but-unverified token would still pass
-- it, but login/refresh both correctly re-check is_active=TRUE and block —
-- meaning the promised 30-day undo window was only actually usable for the
-- ~15 minutes until that access token expired. The emailed "Cancel Deletion"
-- link was also just a dead URL (wrong path prefix, no way to carry a Bearer
-- token from a browser click) — it never worked at all.
--
-- Fix: mirror password_reset_tokens — a random token, emailed, redeemable via
-- an unauthenticated endpoint for the full 30-day grace period.
\c nipino_manabu;

CREATE TABLE IF NOT EXISTS deletion_cancel_tokens (
  id         SERIAL PRIMARY KEY,
  user_id    INTEGER      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash VARCHAR(255) NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ  NOT NULL,
  used       BOOLEAN      DEFAULT FALSE,
  created_at TIMESTAMPTZ  DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_dct_token ON deletion_cancel_tokens(token_hash);
CREATE INDEX IF NOT EXISTS idx_dct_user  ON deletion_cancel_tokens(user_id);
