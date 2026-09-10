-- =============================================================================
-- Indexes
-- =============================================================================
-- These indexes back the analytical queries in /analysis. Most are on FKs that
-- aren't auto-indexed in Postgres, plus a few on filter columns used in WHERE.
-- =============================================================================

SET search_path TO shop, public;

-- Order lookups by customer and by date are the hot path for almost every report
CREATE INDEX idx_orders_customer_id  ON orders (customer_id);
CREATE INDEX idx_orders_order_date   ON orders (order_date);
CREATE INDEX idx_orders_status       ON orders (status);

-- Order_items: support joins to orders and products, plus aggregation by product
CREATE INDEX idx_order_items_order_id   ON order_items (order_id);
CREATE INDEX idx_order_items_product_id ON order_items (product_id);

-- Products by category for category roll-ups
CREATE INDEX idx_products_category_id ON products (category_id);

-- Customers: signup_date is the cohort key
CREATE INDEX idx_customers_signup_date ON customers (signup_date);
CREATE INDEX idx_customers_country     ON customers (country);

-- Returns by date for return-rate trends
CREATE INDEX idx_returns_return_date ON returns (return_date);

-- Categories: self-referential lookups
CREATE INDEX idx_categories_parent ON categories (parent_category_id);
