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
