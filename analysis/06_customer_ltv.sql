-- =============================================================================
-- 06. Customer Lifetime Value (LTV) & order behavior
-- =============================================================================
-- Business question:
--   What does the spend distribution look like? Average order value (AOV),
--   days between purchases, and lifetime spend by acquisition channel.
--
-- Techniques: LAG() to compute inter-purchase gaps, PERCENTILE_CONT for
-- distribution stats, joining through customer_acquisition -> campaigns.
-- =============================================================================

SET search_path TO shop, public;

-- ---- Part A: per-customer summary (one row per customer) -------------------
WITH order_totals AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.order_date,
        SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct/100.0)) AS order_value
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.status <> 'cancelled'
    GROUP BY o.order_id, o.customer_id, o.order_date
),
ordered AS (
    SELECT
        ot.*,
        LAG(order_date) OVER (PARTITION BY customer_id ORDER BY order_date) AS prev_order_date
    FROM order_totals ot
),
per_customer AS (
    SELECT
        customer_id,
        COUNT(*)                                                          AS n_orders,
        SUM(order_value)                                                  AS lifetime_value,
        AVG(order_value)                                                  AS avg_order_value,
        AVG(EXTRACT(EPOCH FROM (order_date - prev_order_date)) / 86400.0) AS avg_days_between_orders,
        MIN(order_date)::DATE                                             AS first_order,
        MAX(order_date)::DATE                                             AS last_order
    FROM ordered
    GROUP BY customer_id
)
-- ---- Part B: LTV by acquisition channel (the headline insight) ------------
SELECT
    COALESCE(cmp.channel, 'unknown')                              AS acquisition_channel,
    COUNT(*)                                                       AS customers,
    ROUND(AVG(pc.lifetime_value), 2)                               AS avg_ltv,
    ROUND(AVG(pc.n_orders)::numeric, 2)                            AS avg_orders,
    ROUND(AVG(pc.avg_order_value), 2)                              AS avg_order_value,
    ROUND(AVG(pc.avg_days_between_orders)::numeric, 1)             AS avg_days_between,
    ROUND( (PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pc.lifetime_value))::numeric, 2 )
                                                                   AS median_ltv,
    ROUND( (PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY pc.lifetime_value))::numeric, 2 )
                                                                   AS p90_ltv
FROM per_customer pc
LEFT JOIN customer_acquisition ca ON ca.customer_id = pc.customer_id
LEFT JOIN campaigns            cmp ON cmp.campaign_id = ca.campaign_id
GROUP BY COALESCE(cmp.channel, 'unknown')
ORDER BY avg_ltv DESC;
