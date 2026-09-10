-- =============================================================================
-- 05. Top-N Per Group: best-selling product per category per year
-- =============================================================================
-- Business question:
--   For each (year, category), what is the #1 product by revenue?
--   This is the canonical "top-N per group" problem.
--
-- Techniques: ROW_NUMBER() partitioning, multi-CTE composition.
-- =============================================================================

SET search_path TO shop, public;

WITH product_year_revenue AS (
    SELECT
        EXTRACT(YEAR FROM o.order_date)::INT      AS year,
        p.category_id,
        c.name                                     AS category_name,
        p.product_id,
        p.name                                     AS product_name,
        SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct/100.0)) AS revenue
    FROM order_items oi
    JOIN orders o      ON o.order_id = oi.order_id AND o.status <> 'cancelled'
    JOIN products p    ON p.product_id = oi.product_id
    JOIN categories c  ON c.category_id = p.category_id
    GROUP BY 1, 2, 3, 4, 5
),
ranked AS (
    SELECT
        pyr.*,
        ROW_NUMBER() OVER (PARTITION BY year, category_id ORDER BY revenue DESC) AS rn
    FROM product_year_revenue pyr
)
SELECT
    year,
    category_name,
    product_name,
    ROUND(revenue, 2) AS revenue
FROM ranked
WHERE rn = 1
ORDER BY year, category_name;
