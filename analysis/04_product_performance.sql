-- =============================================================================
-- 04. Product Performance
-- =============================================================================
-- Business question:
--   Which products drive the most revenue, and which underperform relative
--   to their category peers? Surface the top + bottom 10% of each category.
--
-- Techniques: aggregation, PERCENT_RANK window function per category,
-- LEFT JOIN to detect zero-sales products, and category-level normalisation.
-- =============================================================================

SET search_path TO shop, public;

WITH product_sales AS (
    SELECT
        p.product_id,
        p.sku,
        p.name                                                  AS product_name,
        p.category_id,
        p.list_price,
        p.cost,
        COALESCE(SUM(oi.quantity), 0)                           AS units_sold,
        COALESCE(SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct/100.0)), 0)
                                                                AS gross_revenue,
        COALESCE(SUM(oi.quantity * (oi.unit_price * (1 - oi.discount_pct/100.0) - p.cost)), 0)
                                                                AS gross_profit,
        COUNT(r.return_id)                                      AS returns_count,
        COUNT(oi.order_item_id)                                 AS line_items
    FROM products p
    LEFT JOIN order_items oi ON oi.product_id = p.product_id
    LEFT JOIN orders      o  ON o.order_id = oi.order_id AND o.status <> 'cancelled'
    LEFT JOIN returns     r  ON r.order_item_id = oi.order_item_id
    GROUP BY p.product_id, p.sku, p.name, p.category_id, p.list_price, p.cost
),
ranked AS (
    SELECT
        ps.*,
        c.name AS category_name,
        ROUND(100.0 * returns_count / NULLIF(line_items, 0), 2)        AS return_rate_pct,
        -- Percentile rank inside each category (0 = worst, 1 = best)
        PERCENT_RANK() OVER (PARTITION BY ps.category_id ORDER BY gross_revenue) AS pct_rank_in_cat,
        RANK()         OVER (ORDER BY gross_revenue DESC)              AS rank_overall
    FROM product_sales ps
    JOIN categories c ON c.category_id = ps.category_id
)
SELECT
    rank_overall,
    category_name,
    product_name,
    sku,
    units_sold,
    ROUND(gross_revenue, 2)                              AS gross_revenue,
    ROUND(gross_profit, 2)                               AS gross_profit,
    return_rate_pct,
    ROUND(pct_rank_in_cat::numeric, 2)                   AS pct_rank_in_cat,
    CASE
        WHEN pct_rank_in_cat >= 0.90 THEN 'Top performer'
        WHEN pct_rank_in_cat <= 0.10 THEN 'Underperformer'
        ELSE NULL
    END                                                  AS flag
FROM ranked
WHERE pct_rank_in_cat >= 0.90 OR pct_rank_in_cat <= 0.10
ORDER BY category_name, pct_rank_in_cat DESC;
