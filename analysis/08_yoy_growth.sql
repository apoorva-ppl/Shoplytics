-- =============================================================================
-- 08. Year-over-Year Growth by Category
-- =============================================================================
-- Business question:
--   Which category grew the most YoY, and which shrank? Walk through both
--   2023 vs 2022 and 2024 vs 2023.
--
-- Techniques: conditional aggregation with FILTER (cleaner than CASE inside
-- SUM), self-references via window or via wide-format pivot, NULLIF guards.
-- =============================================================================

SET search_path TO shop, public;

WITH cat_year AS (
    SELECT
        c.category_id,
        c.name                                  AS category_name,
        EXTRACT(YEAR FROM o.order_date)::INT    AS year,
        SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct/100.0)) AS revenue,
        COUNT(DISTINCT o.order_id)              AS orders
    FROM order_items oi
    JOIN orders o      ON o.order_id = oi.order_id AND o.status <> 'cancelled'
    JOIN products p    ON p.product_id = oi.product_id
    JOIN categories c  ON c.category_id = p.category_id
    GROUP BY 1, 2, 3
),
wide AS (
    SELECT
        category_id,
        category_name,
        SUM(revenue) FILTER (WHERE year = 2022) AS rev_2022,
        SUM(revenue) FILTER (WHERE year = 2023) AS rev_2023,
        SUM(revenue) FILTER (WHERE year = 2024) AS rev_2024
    FROM cat_year
    GROUP BY category_id, category_name
)
SELECT
    category_name,
    ROUND(rev_2022, 2)                                                            AS rev_2022,
    ROUND(rev_2023, 2)                                                            AS rev_2023,
    ROUND(rev_2024, 2)                                                            AS rev_2024,
    ROUND(100.0 * (rev_2023 - rev_2022) / NULLIF(rev_2022, 0), 1)                 AS yoy_23_vs_22_pct,
    ROUND(100.0 * (rev_2024 - rev_2023) / NULLIF(rev_2023, 0), 1)                 AS yoy_24_vs_23_pct,
    ROUND(100.0 * (rev_2024 - rev_2022) / NULLIF(rev_2022, 0), 1)                 AS total_growth_pct
FROM wide
ORDER BY total_growth_pct DESC NULLS LAST;
