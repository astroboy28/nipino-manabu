-- backend/migrations/009_subscriptions.sql
-- ─── Real subscription entitlement tracking ───────────────────────────────────
-- premium_monthly was previously just a one-time 500-coin IAP grant with no
-- expiry/entitlement tracking at all, despite terms.php promising an
-- auto-renewing "Monthly Pass". This adds the columns needed to know whether
-- a user's subscription is currently active. Renewal/cancellation are
-- reflected passively via expiry (no Play/App Store server notifications
-- webhook yet — see MASTER_PROMPT/README for that follow-up).
\c nipino_manabu;

ALTER TABLE users ADD COLUMN IF NOT EXISTS subscription_product_id  VARCHAR(50);
ALTER TABLE users ADD COLUMN IF NOT EXISTS subscription_platform    VARCHAR(10);
ALTER TABLE users ADD COLUMN IF NOT EXISTS subscription_expires_at  TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_users_sub_expires ON users(subscription_expires_at);
