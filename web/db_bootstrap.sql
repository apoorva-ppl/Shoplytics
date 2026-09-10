-- =============================================================================
-- E-commerce Analytics: Schema
-- Database: PostgreSQL 14+
-- =============================================================================
-- Star-ish schema centered on order_items (the grain at which revenue is
-- recognized). Dimensions: customers, products, categories, campaigns.
-- =============================================================================

DROP SCHEMA IF EXISTS shop CASCADE;
CREATE SCHEMA shop;
SET search_path TO shop, public;

-- -----------------------------------------------------------------------------
-- Categories (self-referential hierarchy: Electronics > Computers > Laptops)
-- -----------------------------------------------------------------------------
CREATE TABLE categories (
    category_id        SERIAL PRIMARY KEY,
    name               TEXT        NOT NULL,
    parent_category_id INTEGER REFERENCES categories(category_id),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- Products
-- -----------------------------------------------------------------------------
CREATE TABLE products (
    product_id   SERIAL PRIMARY KEY,
    sku          TEXT        NOT NULL UNIQUE,
    name         TEXT        NOT NULL,
    category_id  INTEGER     NOT NULL REFERENCES categories(category_id),
    cost         NUMERIC(10,2) NOT NULL CHECK (cost  >= 0),
    list_price   NUMERIC(10,2) NOT NULL CHECK (list_price >= 0),
    launch_date  DATE        NOT NULL,
    is_active    BOOLEAN     NOT NULL DEFAULT TRUE
);

-- -----------------------------------------------------------------------------
-- Customers
-- -----------------------------------------------------------------------------
CREATE TABLE customers (
    customer_id  SERIAL PRIMARY KEY,
    email        TEXT        NOT NULL UNIQUE,
    first_name   TEXT        NOT NULL,
    last_name    TEXT        NOT NULL,
    signup_date  DATE        NOT NULL,
    country      TEXT        NOT NULL,
    city         TEXT        NOT NULL,
    birth_year   INTEGER     CHECK (birth_year BETWEEN 1920 AND 2015)
);

-- -----------------------------------------------------------------------------
-- Marketing campaigns (for attribution / cohort analysis)
-- -----------------------------------------------------------------------------
CREATE TABLE campaigns (
    campaign_id  SERIAL PRIMARY KEY,
    name         TEXT        NOT NULL,
    channel      TEXT        NOT NULL CHECK (channel IN ('email','paid_search','social','display','referral','organic')),
    start_date   DATE        NOT NULL,
    end_date     DATE        NOT NULL,
    spend_usd    NUMERIC(12,2) NOT NULL CHECK (spend_usd >= 0),
    CHECK (end_date >= start_date)
);

-- First-touch attribution: which campaign brought the customer in?
CREATE TABLE customer_acquisition (
    customer_id  INTEGER PRIMARY KEY REFERENCES customers(customer_id),
    campaign_id  INTEGER REFERENCES campaigns(campaign_id)
);

-- -----------------------------------------------------------------------------
-- Orders (header) and order_items (lines)
-- -----------------------------------------------------------------------------
CREATE TABLE orders (
    order_id        BIGSERIAL PRIMARY KEY,
    customer_id     INTEGER     NOT NULL REFERENCES customers(customer_id),
    order_date      TIMESTAMPTZ NOT NULL,
    status          TEXT        NOT NULL CHECK (status IN ('placed','shipped','delivered','cancelled')),
    payment_method  TEXT        NOT NULL CHECK (payment_method IN ('card','paypal','apple_pay','gift_card'))
);

CREATE TABLE order_items (
    order_item_id   BIGSERIAL PRIMARY KEY,
    order_id        BIGINT      NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
    product_id      INTEGER     NOT NULL REFERENCES products(product_id),
    quantity        INTEGER     NOT NULL CHECK (quantity > 0),
    unit_price      NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
    discount_pct    NUMERIC(4,2) NOT NULL DEFAULT 0 CHECK (discount_pct BETWEEN 0 AND 100)
);

-- -----------------------------------------------------------------------------
-- Returns (one row per returned order_item; partial returns aren't modeled)
-- -----------------------------------------------------------------------------
CREATE TABLE returns (
    return_id      BIGSERIAL PRIMARY KEY,
    order_item_id  BIGINT      NOT NULL UNIQUE REFERENCES order_items(order_item_id) ON DELETE CASCADE,
    return_date    TIMESTAMPTZ NOT NULL,
    reason         TEXT        NOT NULL CHECK (reason IN ('defective','wrong_item','no_longer_wanted','damaged_shipping','other'))
);


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


-- =============================================================================
-- Reference Data: categories, products, campaigns
-- =============================================================================
-- Loaded as literal INSERTs so the catalog is stable across re-runs. The big
-- fact tables (customers/orders/items/returns) are generated procedurally in
-- 02_seed_transactions.sql.
-- =============================================================================

SET search_path TO shop, public;

-- -----------------------------------------------------------------------------
-- Category hierarchy (3 levels: department > category > subcategory)
-- -----------------------------------------------------------------------------
INSERT INTO categories (category_id, name, parent_category_id) VALUES
    -- Departments
    (1,  'Electronics',          NULL),
    (2,  'Home & Kitchen',       NULL),
    (3,  'Apparel',              NULL),
    (4,  'Books',                NULL),
    -- Electronics > ...
    (10, 'Computers',            1),
    (11, 'Mobile',               1),
    (12, 'Audio',                1),
    -- Computers > ...
    (20, 'Laptops',              10),
    (21, 'Desktops',             10),
    (22, 'Accessories',          10),
    -- Mobile > ...
    (23, 'Smartphones',          11),
    (24, 'Smartwatches',         11),
    -- Audio > ...
    (25, 'Headphones',           12),
    (26, 'Speakers',             12),
    -- Home & Kitchen > ...
    (30, 'Cookware',             2),
    (31, 'Small Appliances',     2),
    (32, 'Furniture',            2),
    -- Apparel > ...
    (40, 'Mens',                 3),
    (41, 'Womens',               3),
    (42, 'Kids',                 3),
    -- Books > ...
    (50, 'Fiction',              4),
    (51, 'Non-fiction',          4),
    (52, 'Technical',            4);

-- Reset the sequence so future inserts pick up after the manual IDs
SELECT setval('categories_category_id_seq', (SELECT MAX(category_id) FROM categories));

-- -----------------------------------------------------------------------------
-- Products: ~25 per leaf-category, 17 leaf categories = ~425 products
-- -----------------------------------------------------------------------------
-- Pricing model: cost ~ uniform(10, 800); list_price = cost * margin(1.2..2.5)
-- launch_date spread across 2020-2024.
-- -----------------------------------------------------------------------------
SELECT setseed(0.42);  -- reproducible randomness

WITH leaf_categories AS (
    SELECT category_id FROM categories
    WHERE category_id IN (20,21,22,23,24,25,26,30,31,32,40,41,42,50,51,52)
),
gen AS (
    SELECT
        lc.category_id,
        n AS product_seq,
        ROUND( (10 + random() * 790)::numeric, 2) AS cost,
        ROUND( (1.2 + random() * 1.3)::numeric, 2) AS margin
    FROM leaf_categories lc
    CROSS JOIN generate_series(1, 25) n
)
INSERT INTO products (sku, name, category_id, cost, list_price, launch_date)
SELECT
    'SKU-' || LPAD(category_id::text, 3, '0') || '-' || LPAD(product_seq::text, 3, '0'),
    'Product '   || category_id || '-' || product_seq,
    category_id,
    cost,
    ROUND(cost * margin, 2),
    DATE '2020-01-01' + (random() * 1825)::int    -- 5-year window
FROM gen;

-- -----------------------------------------------------------------------------
-- Campaigns
-- -----------------------------------------------------------------------------
INSERT INTO campaigns (name, channel, start_date, end_date, spend_usd) VALUES
    ('Spring Launch 2022',       'paid_search', '2022-03-01', '2022-04-30',  45000),
    ('Summer Sale 2022',         'email',       '2022-06-15', '2022-07-15',  12000),
    ('Back to School 2022',      'social',      '2022-08-01', '2022-09-15',  38000),
    ('Holiday Blitz 2022',       'display',     '2022-11-01', '2022-12-26',  85000),
    ('New Year 2023',            'email',       '2023-01-01', '2023-01-31',   8000),
    ('Spring Refresh 2023',      'paid_search', '2023-03-01', '2023-04-30',  52000),
    ('Summer Sale 2023',         'social',      '2023-06-15', '2023-07-31',  40000),
    ('Holiday Blitz 2023',       'display',     '2023-11-01', '2023-12-26',  98000),
    ('Influencer Push 2024',     'social',      '2024-04-01', '2024-05-31',  61000),
    ('Holiday Blitz 2024',       'display',     '2024-11-01', '2024-12-26', 110000),
    ('Referral Program (always-on)', 'referral','2022-01-01', '2024-12-31',  25000);


-- =============================================================================
-- Transactional data: customers, orders, order_items, returns
-- =============================================================================
-- Procedurally generated for realism + reproducibility. Output volumes (~):
--   customers:    5,000
--   orders:      50,000   (over 2022-01-01..2024-12-31, with seasonality)
--   order_items:160,000   (1-5 items per order)
--   returns:     ~12,000  (~7.5% line-level return rate)
--
-- Notes on patterns baked in:
--   * Order volume grows ~25% YoY (so YoY analyses produce something).
--   * Nov/Dec get a 2.2x multiplier (holiday spike).
--   * 60% of customers churn after their first month (typical e-commerce).
--   * VIP segment (~5%) places 10x more orders than average.
--   * Return rate is higher for Electronics and Apparel.
-- =============================================================================

SET search_path TO shop, public;
SELECT setseed(0.17);

-- -----------------------------------------------------------------------------
-- Customers (5,000)
-- -----------------------------------------------------------------------------
WITH first_names(fn) AS (VALUES
    ('Aanya'),('Liam'),('Noah'),('Olivia'),('Emma'),('Sophia'),('Mason'),('Ava'),
    ('James'),('Ethan'),('Mia'),('Lucas'),('Isabella'),('Logan'),('Amelia'),('Aiden'),
    ('Charlotte'),('Elijah'),('Harper'),('Jackson'),('Evelyn'),('Sebastian'),('Abigail'),
    ('Mateo'),('Emily'),('Henry'),('Elizabeth'),('Owen'),('Sofia'),('Daniel'),('Avery'),
    ('Jacob'),('Ella'),('Michael'),('Madison'),('Alexander'),('Scarlett'),('William'),
    ('Victoria'),('Benjamin'),('Aria'),('David'),('Grace'),('Joseph'),('Chloe'),
    ('Samuel'),('Camila'),('Carter'),('Penelope'),('John'),('Riley'),('Wyatt'),('Layla'),
    ('Luke'),('Lillian'),('Jayden'),('Nora'),('Dylan'),('Zoey'),('Grayson'),('Mila'),
    ('Levi'),('Aubrey'),('Isaac'),('Hannah'),('Gabriel'),('Lily'),('Julian'),('Addison')
),
last_names(ln) AS (VALUES
    ('Smith'),('Johnson'),('Williams'),('Brown'),('Jones'),('Garcia'),('Miller'),
    ('Davis'),('Rodriguez'),('Martinez'),('Hernandez'),('Lopez'),('Gonzalez'),('Wilson'),
    ('Anderson'),('Thomas'),('Taylor'),('Moore'),('Jackson'),('Martin'),('Lee'),
    ('Perez'),('Thompson'),('White'),('Harris'),('Sanchez'),('Clark'),('Ramirez'),
    ('Lewis'),('Robinson'),('Walker'),('Young'),('Allen'),('King'),('Wright'),('Scott'),
    ('Torres'),('Nguyen'),('Hill'),('Flores'),('Green'),('Adams'),('Nelson'),('Baker'),
    ('Hall'),('Rivera'),('Campbell'),('Mitchell'),('Carter'),('Roberts'),('Patel'),
    ('Kim'),('Chen'),('Singh'),('Khan'),('Sharma'),('Cohen'),('Ali')
),
cities(country, city) AS (VALUES
    ('USA','New York'), ('USA','Los Angeles'), ('USA','Chicago'), ('USA','Houston'),
    ('USA','Austin'),   ('USA','Seattle'),     ('USA','Boston'),  ('USA','Miami'),
    ('Canada','Toronto'), ('Canada','Vancouver'), ('Canada','Montreal'),
    ('UK','London'), ('UK','Manchester'),
    ('Germany','Berlin'), ('Germany','Munich'),
    ('France','Paris'),
    ('India','Mumbai'), ('India','Bangalore'), ('India','Delhi'),
    ('Australia','Sydney'), ('Australia','Melbourne')
),
fn_arr AS (SELECT ARRAY(SELECT fn FROM first_names) AS a),
ln_arr AS (SELECT ARRAY(SELECT ln FROM last_names)  AS a),
country_arr AS (SELECT ARRAY(SELECT country FROM cities) AS a),
city_arr    AS (SELECT ARRAY(SELECT city    FROM cities) AS a)
INSERT INTO customers (email, first_name, last_name, signup_date, country, city, birth_year)
SELECT
    'cust' || n || '@example.com',
    fn_arr.a[1 + (random() * (array_length(fn_arr.a, 1) - 1))::int],
    ln_arr.a[1 + (random() * (array_length(ln_arr.a, 1) - 1))::int],
    -- Signups skew toward later dates (random()^0.7 pushes a uniform draw
    -- toward 1.0, i.e. more-recent dates), so the customer base grows roughly
    -- year over year. This is what drives realistic top-line growth instead of
    -- artificially weighting the order dates themselves.
    DATE '2022-01-01' + (POWER(random(), 0.7) * 1095)::int,
    country_arr.a[idx],
    city_arr.a[idx],
    1950 + (random() * 60)::int
FROM generate_series(1, 5000) n,
     fn_arr, ln_arr, country_arr, city_arr,
     LATERAL (SELECT 1 + (random() * (array_length(country_arr.a, 1) - 1))::int AS idx) ix;

-- -----------------------------------------------------------------------------
-- Customer acquisition (link customers to campaigns by signup date)
-- -----------------------------------------------------------------------------
INSERT INTO customer_acquisition (customer_id, campaign_id)
SELECT c.customer_id,
       (SELECT cmp.campaign_id
          FROM campaigns cmp
         WHERE c.signup_date BETWEEN cmp.start_date AND cmp.end_date
         ORDER BY random()
         LIMIT 1)
FROM customers c;

-- -----------------------------------------------------------------------------
-- Orders: ~50,000 rows
-- -----------------------------------------------------------------------------
-- Each customer is assigned a "tier" determining how many orders they'll place:
--   tier 0 (60%): 1 order then churn
--   tier 1 (25%): 2-5 orders
--   tier 2 (10%): 6-15 orders
--   tier 3  (5%): 20-50 orders (VIPs)
--
-- Order dates are weighted toward Q4 and later years (growth).
-- -----------------------------------------------------------------------------
CREATE TEMP TABLE _customer_tier AS
SELECT
    customer_id,
    signup_date,
    CASE
        WHEN random() < 0.60 THEN 0
        WHEN random() < 0.85 THEN 1
        WHEN random() < 0.95 THEN 2
        ELSE 3
    END AS tier
FROM customers;

-- Each customer also gets an "active lifespan": how long after signup they
-- keep buying. VIPs stay around for years; one-and-done buyers have a lifespan
-- of ~0. Spreading a customer's orders across this window (rather than dumping
-- them all at signup) is what makes the cohort-retention analysis meaningful.
CREATE TEMP TABLE _order_counts AS
SELECT
    customer_id,
    signup_date,
    tier,
    CASE tier
        WHEN 0 THEN 1
        WHEN 1 THEN 2 + (random() * 4)::int
        WHEN 2 THEN 6 + (random() * 10)::int
        WHEN 3 THEN 20 + (random() * 31)::int
    END AS n_orders,
    CASE tier
        WHEN 0 THEN 0
        WHEN 1 THEN (120 + random() * 240)::int     -- ~4-12 months
        WHEN 2 THEN (300 + random() * 430)::int     -- ~10-24 months
        WHEN 3 THEN (450 + random() * 550)::int     -- ~15-33 months
    END AS lifespan_days
FROM _customer_tier;

-- Build one row per order. Order N of M is placed at:
--   signup + lifespan * (N-1)/(M-1)  + a few days of jitter
-- so the first order is at signup and the rest fan out across the lifespan.
-- Orders past the dataset horizon (2024-12-31) are dropped (right-censored).
WITH expanded AS (
    SELECT
        oc.customer_id,
        oc.signup_date,
        oc.n_orders,
        oc.lifespan_days,
        generate_series(1, oc.n_orders) AS order_seq
    FROM _order_counts oc
),
dated AS (
    SELECT
        e.customer_id,
        e.signup_date,
        -- Repeat orders are FRONT-LOADED: raising the normalized position to
        -- the power 2 compresses early orders close to signup and lets later
        -- ones trail off, which yields a monotonically decaying retention curve
        -- (the realistic shape) instead of an even spread.
        e.signup_date
            + (e.lifespan_days
                 * POWER((e.order_seq - 1)::numeric / GREATEST(e.n_orders - 1, 1), 2))::int
            + (random() * 20 - 10)::int                AS raw_date,   -- +/-10d jitter
        e.order_seq
    FROM expanded e
),
clamped AS (
    SELECT
        customer_id,
        GREATEST(raw_date, signup_date) AS base_date   -- never before signup
    FROM dated
),
holiday_boost AS (
    -- Orders that landed in Nov/Dec get a second copy => ~2x holiday volume
    SELECT customer_id, base_date FROM clamped
    UNION ALL
    SELECT customer_id, base_date FROM clamped
    WHERE EXTRACT(MONTH FROM base_date) IN (11, 12)
)
INSERT INTO orders (customer_id, order_date, status, payment_method)
SELECT
    customer_id,
    base_date + (random() * INTERVAL '1 day'),
    (ARRAY['placed','shipped','delivered','delivered','delivered','delivered','cancelled'])
        [1 + (random()*6)::int],
    (ARRAY['card','card','card','paypal','apple_pay','gift_card'])
        [1 + (random()*5)::int]
FROM holiday_boost
WHERE base_date <= DATE '2024-12-31';

-- -----------------------------------------------------------------------------
-- Order items: 1-5 lines per order
-- -----------------------------------------------------------------------------
-- NOTE: we pick a product per line via a *per-row* random index into a
-- ROW_NUMBER()-ed product list. A tempting alternative --
--   CROSS JOIN LATERAL (SELECT ... FROM products ORDER BY random() LIMIT 1)
-- -- is a trap: that subquery has no correlation to the outer row, so Postgres
-- evaluates it ONCE and assigns the same product to every line. The index
-- approach forces random() to be evaluated once per line.
-- -----------------------------------------------------------------------------
WITH lines AS (
    SELECT o.order_id
    FROM orders o
    CROSS JOIN LATERAL generate_series(1, 1 + (random() * 4)::int) AS line_seq
),
lines_picked AS (
    -- POWER(random(), 1.7) biases the index toward low row-numbers, so a subset
    -- of products become "bestsellers" and revenue concentrates -- giving a
    -- realistic Pareto/ABC curve rather than a flat uniform distribution.
    SELECT
        order_id,
        1 + FLOOR(POWER(random(), 1.7) * (SELECT COUNT(*) FROM products))::int AS prod_rn
    FROM lines
),
products_indexed AS (
    SELECT
        product_id,
        list_price,
        ROW_NUMBER() OVER (ORDER BY product_id) AS rn
    FROM products
)
INSERT INTO order_items (order_id, product_id, quantity, unit_price, discount_pct)
SELECT
    lp.order_id,
    pi.product_id,
    1 + (random() * 2)::int,
    pi.list_price,
    CASE
        WHEN random() < 0.15 THEN ROUND( (5 + random()*25)::numeric, 2 )   -- 15% of lines get 5-30% off
        ELSE 0
    END
FROM lines_picked lp
JOIN products_indexed pi ON pi.rn = lp.prod_rn;

-- -----------------------------------------------------------------------------
-- Returns: ~7.5% of order_items, higher for Electronics & Apparel,
-- only for delivered orders, returned within 30 days
-- -----------------------------------------------------------------------------
INSERT INTO returns (order_item_id, return_date, reason)
SELECT
    oi.order_item_id,
    o.order_date + (1 + (random() * 29)::int) * INTERVAL '1 day',
    (ARRAY['defective','wrong_item','no_longer_wanted','damaged_shipping','other'])
        [1 + (random()*4)::int]
FROM order_items oi
JOIN orders   o  ON o.order_id = oi.order_id
JOIN products p  ON p.product_id = oi.product_id
JOIN categories c ON c.category_id = p.category_id
LEFT JOIN categories parent ON parent.category_id = c.parent_category_id
LEFT JOIN categories grandparent ON grandparent.category_id = parent.parent_category_id
WHERE o.status = 'delivered'
  AND random() < CASE
                   WHEN COALESCE(grandparent.name, parent.name, c.name) IN ('Electronics','Apparel') THEN 0.12
                   ELSE 0.05
                 END;

-- -----------------------------------------------------------------------------
-- Refresh table statistics so the planner has accurate counts for the
-- analytical queries.
-- -----------------------------------------------------------------------------
ANALYZE;

-- -----------------------------------------------------------------------------
-- Row count sanity check
-- -----------------------------------------------------------------------------
SELECT 'customers'   AS table_name, COUNT(*) FROM customers   UNION ALL
SELECT 'orders',         COUNT(*) FROM orders                  UNION ALL
SELECT 'order_items',    COUNT(*) FROM order_items             UNION ALL
SELECT 'products',       COUNT(*) FROM products                UNION ALL
SELECT 'returns',        COUNT(*) FROM returns                 UNION ALL
SELECT 'campaigns',      COUNT(*) FROM campaigns;


-- =============================================================================
-- Reusable Views
-- =============================================================================
-- These encapsulate the "revenue at the line-item grain" logic that almost
-- every analysis re-derives, so downstream queries stay DRY.
-- =============================================================================

SET search_path TO shop, public;

-- -----------------------------------------------------------------------------
-- v_order_item_revenue : one row per order_item, with revenue/cost/return flags
-- already computed. The single source of truth for "what is a sale worth?"
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_order_item_revenue AS
SELECT
    oi.order_item_id,
    oi.order_id,
    o.customer_id,
    o.order_date,
    o.status,
    oi.product_id,
    p.category_id,
    oi.quantity,
    oi.unit_price,
    oi.discount_pct,
    oi.quantity * oi.unit_price                                   AS gross_revenue,
    oi.quantity * oi.unit_price * (1 - oi.discount_pct/100.0)     AS net_revenue,
    oi.quantity * p.cost                                          AS cogs,
    oi.quantity * (oi.unit_price * (1 - oi.discount_pct/100.0) - p.cost) AS gross_profit,
    (r.return_id IS NOT NULL)                                     AS is_returned
FROM order_items oi
JOIN orders   o ON o.order_id   = oi.order_id
JOIN products p ON p.product_id = oi.product_id
LEFT JOIN returns r ON r.order_item_id = oi.order_item_id
WHERE o.status <> 'cancelled';

-- -----------------------------------------------------------------------------
-- v_monthly_revenue : pre-aggregated monthly KPIs (good candidate for a
-- materialized view in production; kept as a plain view here for portability).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_monthly_revenue AS
SELECT
    DATE_TRUNC('month', order_date)::DATE        AS month,
    SUM(net_revenue)                             AS net_revenue,
    SUM(net_revenue) FILTER (WHERE is_returned)  AS returned_revenue,
    SUM(gross_profit)                            AS gross_profit,
    COUNT(DISTINCT order_id)                     AS orders,
    COUNT(DISTINCT customer_id)                  AS active_customers
FROM v_order_item_revenue
GROUP BY 1;

-- -----------------------------------------------------------------------------
-- v_customer_orders : per-customer order-level rollup used by RFM / LTV
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_customer_orders AS
SELECT
    customer_id,
    COUNT(DISTINCT order_id)                          AS orders,
    SUM(net_revenue)                                  AS net_revenue,
    SUM(net_revenue) FILTER (WHERE NOT is_returned)   AS realized_revenue,
    MIN(order_date)::DATE                             AS first_order_date,
    MAX(order_date)::DATE                             AS last_order_date
FROM v_order_item_revenue
GROUP BY customer_id;


-- =============================================================================
-- PL/pgSQL function: shop.rfm_segment(r, f, m) -> text
-- =============================================================================
-- Encapsulates the RFM segment-naming rules so they live in ONE place and can
-- be reused across queries, dashboards, and the materialized view below.
--
-- Demonstrates: CREATE FUNCTION, IMMUTABLE marking, parameter handling.
-- =============================================================================

SET search_path TO shop, public;

CREATE OR REPLACE FUNCTION rfm_segment(
    r_score INT,
    f_score INT,
    m_score INT
) RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN
        RETURN 'Champion';
    ELSIF r_score >= 3 AND f_score >= 4 THEN
        RETURN 'Loyal';
    ELSIF r_score >= 4 AND f_score <= 2 THEN
        RETURN 'New / Promising';
    ELSIF r_score <= 2 AND f_score >= 3 THEN
        RETURN 'At Risk';
    ELSIF r_score <= 2 AND f_score <= 2 THEN
        RETURN 'Lost';
    ELSE
        RETURN 'Regular';
    END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- Materialized view that pre-computes RFM for every customer using the
-- function above. Refresh nightly in production: REFRESH MATERIALIZED VIEW ...
-- -----------------------------------------------------------------------------
DROP MATERIALIZED VIEW IF EXISTS mv_customer_rfm;
CREATE MATERIALIZED VIEW mv_customer_rfm AS
WITH analysis_date AS (
    SELECT MAX(order_date)::DATE + 1 AS today FROM orders
),
facts AS (
    SELECT
        co.customer_id,
        (SELECT today FROM analysis_date) - co.last_order_date AS recency_days,
        co.orders                                              AS frequency,
        co.realized_revenue                                    AS monetary
    FROM v_customer_orders co
),
scored AS (
    SELECT
        customer_id, recency_days, frequency, monetary,
        6 - NTILE(5) OVER (ORDER BY recency_days) AS r_score,
        NTILE(5) OVER (ORDER BY frequency)        AS f_score,
        NTILE(5) OVER (ORDER BY monetary)         AS m_score
    FROM facts
)
SELECT
    customer_id,
    recency_days,
    frequency,
    ROUND(monetary, 2) AS monetary,
    r_score, f_score, m_score,
    rfm_segment(r_score, f_score, m_score) AS segment
FROM scored;

CREATE UNIQUE INDEX idx_mv_customer_rfm_pk ON mv_customer_rfm (customer_id);

-- Quick rollup you can run after building it:
--   SELECT segment, COUNT(*), ROUND(SUM(monetary),0) AS revenue
--   FROM mv_customer_rfm GROUP BY segment ORDER BY revenue DESC;
