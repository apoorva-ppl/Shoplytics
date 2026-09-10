-- =============================================================================
-- 02. RFM Customer Segmentation
-- =============================================================================
-- Business question:
--   Group customers into "Champions / Loyal / At-Risk / Lost" buckets so
--   marketing can prioritize retention campaigns.
--
-- RFM scoring:
--   Recency   = days since most recent order  (lower is better)
--   Frequency = number of distinct orders
--   Monetary  = total realized revenue
-- Each scored 1-5 via NTILE, then concatenated.
--
-- Techniques: NTILE window function, CTE chaining, CASE-based segmentation,
-- handling of cancelled/returned items in the monetary calculation.
-- =============================================================================

SET search_path TO shop, public;

WITH analysis_date AS (
    -- "today" for this dataset = day after the last order
    SELECT MAX(order_date)::DATE + 1 AS today FROM orders
),
customer_facts AS (
    SELECT
        c.customer_id,
        c.email,
        c.country,
        (SELECT today FROM analysis_date)
            - MAX(o.order_date)::DATE                                  AS recency_days,
        COUNT(DISTINCT o.order_id)                                     AS frequency,
        SUM( oi.quantity * oi.unit_price * (1 - oi.discount_pct/100.0)
             * CASE WHEN r.return_id IS NULL THEN 1 ELSE 0 END )       AS monetary
    FROM customers c
    JOIN orders      o  ON o.customer_id = c.customer_id
                       AND o.status <> 'cancelled'
    JOIN order_items oi ON oi.order_id   = o.order_id
    LEFT JOIN returns r ON r.order_item_id = oi.order_item_id
    GROUP BY c.customer_id, c.email, c.country
),
scored AS (
    SELECT
        cf.*,
        -- Recency: lower days = higher score, so reverse the NTILE
        6 - NTILE(5) OVER (ORDER BY recency_days)            AS r_score,
        NTILE(5) OVER (ORDER BY frequency)                   AS f_score,
        NTILE(5) OVER (ORDER BY monetary)                    AS m_score
    FROM customer_facts cf
)
SELECT
    customer_id,
    email,
    country,
    recency_days,
    frequency,
    ROUND(monetary, 2)                                       AS monetary,
    r_score, f_score, m_score,
    (r_score * 100 + f_score * 10 + m_score)                 AS rfm_code,
    CASE
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champion'
        WHEN r_score >= 3 AND f_score >= 4                  THEN 'Loyal'
        WHEN r_score >= 4 AND f_score <= 2                  THEN 'New / Promising'
        WHEN r_score <= 2 AND f_score >= 3                  THEN 'At Risk'
        WHEN r_score <= 2 AND f_score <= 2                  THEN 'Lost'
        ELSE                                                     'Regular'
    END                                                      AS segment
FROM scored
ORDER BY rfm_code DESC, monetary DESC;
