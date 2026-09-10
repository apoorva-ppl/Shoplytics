-- =============================================================================
-- 01. Revenue Overview
-- =============================================================================
-- Business question:
--   How is the business doing? Show monthly gross revenue, net revenue
--   (after discounts and returns), gross margin, and a 3-month rolling avg.
--
-- Techniques: aggregation, LEFT JOIN to a sparse table (returns),
-- window functions (AVG OVER), date_trunc, derived columns.
-- =============================================================================

SET search_path TO shop, public;

WITH line_revenue AS (
    SELECT
        DATE_TRUNC('month', o.order_date)::DATE                       AS month,
        oi.order_item_id,
        oi.quantity,
        oi.unit_price,
        oi.discount_pct,
        oi.quantity * oi.unit_price                                   AS gross_revenue,
        oi.quantity * oi.unit_price * (1 - oi.discount_pct/100.0)     AS net_revenue,
        oi.quantity * p.cost                                          AS cogs,
        CASE WHEN r.return_id IS NOT NULL THEN 1 ELSE 0 END           AS is_returned
    FROM order_items oi
    JOIN orders   o ON o.order_id   = oi.order_id
    JOIN products p ON p.product_id = oi.product_id
    LEFT JOIN returns r ON r.order_item_id = oi.order_item_id
    WHERE o.status <> 'cancelled'
),
monthly AS (
    SELECT
        month,
        SUM(gross_revenue)                                              AS gross_revenue,
        SUM(net_revenue)                                                AS net_revenue,
        SUM(net_revenue) FILTER (WHERE is_returned = 1)                 AS returned_revenue,
        SUM(net_revenue) - SUM(net_revenue) FILTER (WHERE is_returned = 1)
                                                                        AS realized_revenue,
        SUM(cogs)                                                       AS cogs,
        COUNT(DISTINCT order_item_id)                                   AS line_items,
        COUNT(*) FILTER (WHERE is_returned = 1)                         AS returns_count
    FROM line_revenue
    GROUP BY month
)
SELECT
    month,
    gross_revenue,
    net_revenue,
    realized_revenue,
    ROUND(100.0 * returned_revenue / NULLIF(net_revenue, 0), 2)          AS return_rate_pct,
    ROUND(100.0 * (realized_revenue - cogs) / NULLIF(realized_revenue,0), 2)
                                                                          AS gross_margin_pct,
    ROUND(AVG(realized_revenue) OVER (
              ORDER BY month
              ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2)               AS rev_3mo_avg,
    realized_revenue
        - LAG(realized_revenue, 12) OVER (ORDER BY month)                 AS yoy_delta
FROM monthly
ORDER BY month;
