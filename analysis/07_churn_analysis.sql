-- =============================================================================
-- 07. Churn Analysis
-- =============================================================================
-- Business question:
--   What share of customers active in a given quarter did NOT come back the
--   next quarter? (Quarterly churn rate.) And in which quarters is churn
--   worst — does that line up with marketing spend?
--
-- Techniques: self-join (a customer-quarter pair compared with the next),
-- DATE_TRUNC to quarter, LEAD-style logic via UNION + COUNT.
-- =============================================================================

SET search_path TO shop, public;

WITH customer_quarters AS (
    SELECT DISTINCT
        customer_id,
        DATE_TRUNC('quarter', order_date)::DATE AS quarter
    FROM orders
    WHERE status <> 'cancelled'
),
churn_eval AS (
    SELECT
        cq.quarter,
        cq.customer_id,
        -- did this customer have ANY order the following quarter?
        EXISTS (
            SELECT 1
              FROM customer_quarters next_q
             WHERE next_q.customer_id = cq.customer_id
               AND next_q.quarter = cq.quarter + INTERVAL '3 months'
        ) AS retained_next_q
    FROM customer_quarters cq
    -- Don't evaluate the latest quarter (no "next quarter" exists yet)
    WHERE cq.quarter < (SELECT MAX(quarter) FROM customer_quarters)
),
campaign_spend AS (
    SELECT
        DATE_TRUNC('quarter', start_date)::DATE AS quarter,
        SUM(spend_usd)                          AS marketing_spend
    FROM campaigns
    GROUP BY 1
)
SELECT
    ce.quarter,
    COUNT(*)                                                   AS active_customers,
    COUNT(*) FILTER (WHERE NOT retained_next_q)                AS churned,
    ROUND(100.0 * COUNT(*) FILTER (WHERE NOT retained_next_q) / COUNT(*), 2)
                                                                AS churn_rate_pct,
    COALESCE(cs.marketing_spend, 0)                            AS marketing_spend_usd
FROM churn_eval ce
LEFT JOIN campaign_spend cs ON cs.quarter = ce.quarter
GROUP BY ce.quarter, cs.marketing_spend
ORDER BY ce.quarter;
