-- =============================================================================
-- Indexes (This file answers:-How do I make my SQL queries faster?)
-- =============================================================================
--Primary keys automatically get indexes in PostgreSQL, but FOREIGN KEY doesnt, hence project explicitly creates indexes.
-- =============================================================================

SET search_path TO shop, public; --Look for tables first inside the shop schema.

-- Order lookups by customer and by date are the hot path for almost every report
CREATE INDEX idx_orders_customer_id  ON orders (customer_id);--Find orders of a customer / customer-order joins
CREATE INDEX idx_orders_order_date   ON orders (order_date);--Date filtering, revenue trends, YoY
CREATE INDEX idx_orders_status       ON orders (status); --Filter cancelled/non-cancelled orders

-- Order_items: support joins to orders and products, plus aggregation by product
CREATE INDEX idx_order_items_order_id   ON order_items (order_id); --Order → line-item joins
CREATE INDEX idx_order_items_product_id ON order_items (product_id); --Product → line-item joins

-- Products by category for category roll-ups
CREATE INDEX idx_products_category_id ON products (category_id); --Product → category analysis

-- Customers: signup_date is the cohort key
CREATE INDEX idx_customers_signup_date ON customers (signup_date); --Cohort analysis
CREATE INDEX idx_customers_country     ON customers (country); --Geographic analysis

-- Returns by date for return-rate trends
CREATE INDEX idx_returns_return_date ON returns (return_date); --Return trends over time

-- Categories: self-referential lookups
CREATE INDEX idx_categories_parent ON categories (parent_category_id); --Category hierarchy / recursive queries
