-- =============================================================================
-- 03. Cohort Retention
-- =============================================================================
-- Business question:
--   Of customers who first ordered in January 2023, what % came back in Feb,
--   Mar, Apr, ...? Build the classic cohort-retention triangle.
--
-- Techniques: self-join to find first-order month, GROUP BY two date columns,
-- PIVOT-style aggregation with FILTER, division by cohort size for percentage.
-- =============================================================================

SET search_path TO shop, public;

WITH first_orders AS (
    SELECT
        customer_id,
        DATE_TRUNC('month', MIN(order_date))::DATE AS cohort_month
    FROM orders
    WHERE status <> 'cancelled'
    GROUP BY customer_id
),
orders_with_cohort AS (
    SELECT
        o.customer_id,
        fo.cohort_month,
        DATE_TRUNC('month', o.order_date)::DATE AS activity_month,
        -- months elapsed since cohort_month
        (EXTRACT(YEAR  FROM o.order_date) - EXTRACT(YEAR  FROM fo.cohort_month)) * 12
      + (EXTRACT(MONTH FROM o.order_date) - EXTRACT(MONTH FROM fo.cohort_month))
        AS months_since_first
    FROM orders o
    JOIN first_orders fo USING (customer_id)
    WHERE o.status <> 'cancelled'
),
cohort_sizes AS (
    SELECT cohort_month, COUNT(DISTINCT customer_id) AS cohort_size
    FROM first_orders GROUP BY cohort_month
),
retention AS (
    SELECT
        cohort_month,
        months_since_first,
        COUNT(DISTINCT customer_id) AS active_customers
    FROM orders_with_cohort
    GROUP BY cohort_month, months_since_first
)
SELECT
    r.cohort_month,
    cs.cohort_size,
    -- m0 is always 100% by definition
    ROUND(100.0 * MAX(r.active_customers) FILTER (WHERE r.months_since_first = 0)  / cs.cohort_size, 1) AS m0,
    ROUND(100.0 * MAX(r.active_customers) FILTER (WHERE r.months_since_first = 1)  / cs.cohort_size, 1) AS m1,
    ROUND(100.0 * MAX(r.active_customers) FILTER (WHERE r.months_since_first = 2)  / cs.cohort_size, 1) AS m2,
    ROUND(100.0 * MAX(r.active_customers) FILTER (WHERE r.months_since_first = 3)  / cs.cohort_size, 1) AS m3,
    ROUND(100.0 * MAX(r.active_customers) FILTER (WHERE r.months_since_first = 6)  / cs.cohort_size, 1) AS m6,
    ROUND(100.0 * MAX(r.active_customers) FILTER (WHERE r.months_since_first = 12) / cs.cohort_size, 1) AS m12
FROM retention r
JOIN cohort_sizes cs USING (cohort_month)
GROUP BY r.cohort_month, cs.cohort_size
ORDER BY r.cohort_month;
