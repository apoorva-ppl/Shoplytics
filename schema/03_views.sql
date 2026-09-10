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
