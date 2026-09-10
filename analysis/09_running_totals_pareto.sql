-- =============================================================================
-- 09. Pareto Analysis: do 20% of products drive 80% of revenue?
-- =============================================================================
-- Business question:
--   Test the 80/20 rule on the product catalog. What share of products
--   accounts for 80% of revenue?
--
-- Techniques: running total via SUM() OVER, cumulative percentage,
-- rank-based slicing.
-- =============================================================================

SET search_path TO shop, public;

WITH product_revenue AS (
    SELECT
        p.product_id,
        p.name AS product_name,
        SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct/100.0)) AS revenue
    FROM order_items oi
    JOIN orders o   ON o.order_id = oi.order_id AND o.status <> 'cancelled'
    JOIN products p ON p.product_id = oi.product_id
    GROUP BY p.product_id, p.name
),
ranked AS (
    SELECT
        product_id,
        product_name,
        revenue,
        ROW_NUMBER() OVER (ORDER BY revenue DESC)                                   AS rank,
        SUM(revenue) OVER (ORDER BY revenue DESC
                           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)        AS cumulative_revenue,
        SUM(revenue) OVER ()                                                        AS total_revenue,
        COUNT(*)     OVER ()                                                        AS total_products
    FROM product_revenue
)
SELECT
    rank,
    product_name,
    ROUND(revenue, 2)                                              AS revenue,
    ROUND(100.0 * cumulative_revenue / total_revenue, 2)           AS cum_revenue_pct,
    ROUND(100.0 * rank / total_products, 2)                        AS cum_product_pct,
    CASE WHEN cumulative_revenue / total_revenue <= 0.80 THEN 'A (top 80%)'
         WHEN cumulative_revenue / total_revenue <= 0.95 THEN 'B (next 15%)'
         ELSE                                                  'C (long tail)'
    END                                                            AS abc_class
FROM ranked
ORDER BY rank;
