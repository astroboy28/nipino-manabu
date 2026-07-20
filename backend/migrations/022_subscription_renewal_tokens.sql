-- backend/migrations/022_subscription_renewal_tokens.sql
-- ─── Store what's needed to re-check a subscription later ────────────────────
-- handleValidate() only ever stored a SHA-256 hash of the receipt/purchase
-- token (correct — it's a one-way replay-attack guard, not meant to be
-- reversible), which meant there was no way to ever ask Apple/Google "is
-- this subscription still active?" again after the initial purchase. The
-- only way entitlement ever got refreshed was the client re-submitting a
-- fresh receipt, which doesn't happen automatically on renewal. These two
-- columns hold the actual re-checkable identifiers (only for subscription
-- purchases, only what's needed to call the platform's own status API —
-- not the raw receipt itself for Apple, since App Store Server API polling
-- uses originalTransactionId, not the receipt blob).

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS subscription_apple_original_txn_id VARCHAR(64),
  ADD COLUMN IF NOT EXISTS subscription_google_purchase_token TEXT;

CREATE INDEX IF NOT EXISTS idx_users_sub_expiring
  ON users(subscription_expires_at)
  WHERE subscription_expires_at IS NOT NULL;
