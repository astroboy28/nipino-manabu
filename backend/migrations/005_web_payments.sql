-- backend/migrations/005_web_payments.sql
-- ─── Stripe + PayPal web coin store ─────────────────────────────────────────
\c nipino_manabu;

CREATE TABLE web_payment_orders (
  id              SERIAL PRIMARY KEY,
  uuid            UUID DEFAULT uuid_generate_v4() UNIQUE NOT NULL,
  user_id         INTEGER     NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  gateway         VARCHAR(20) NOT NULL CHECK (gateway IN ('stripe','paypal')),
  gateway_order_id VARCHAR(255) UNIQUE, -- Stripe PaymentIntent ID or PayPal order ID
  product_id      VARCHAR(50) NOT NULL,
  coins_to_grant  INTEGER     NOT NULL CHECK (coins_to_grant > 0),
  amount_usd      NUMERIC(8,2) NOT NULL,
  currency        VARCHAR(3)  DEFAULT 'USD',
  status          VARCHAR(20) DEFAULT 'pending'
                    CHECK (status IN ('pending','completed','failed','refunded')),
  coins_granted_at TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_wpo_user   ON web_payment_orders(user_id);
CREATE INDEX IF NOT EXISTS idx_wpo_gw_id  ON web_payment_orders(gateway_order_id);
CREATE INDEX IF NOT EXISTS idx_wpo_status ON web_payment_orders(status);

-- Prevent double-crediting: only one completed order per gateway_order_id
CREATE UNIQUE INDEX IF NOT EXISTS idx_wpo_completed
  ON web_payment_orders(gateway_order_id)
  WHERE status = 'completed';
