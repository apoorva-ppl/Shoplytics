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
