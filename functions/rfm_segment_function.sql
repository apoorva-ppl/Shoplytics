-- =============================================================================
-- PL/pgSQL function: shop.rfm_segment(r, f, m) -> text
-- =============================================================================
-- Encapsulates the RFM segment-naming rules so they live in ONE place and can
-- be reused across queries, dashboards, and the materialized view below.
--
-- Demonstrates: CREATE FUNCTION, IMMUTABLE marking, parameter handling.
-- =============================================================================

SET search_path TO shop, public;

CREATE OR REPLACE FUNCTION rfm_segment(
    r_score INT,
    f_score INT,
    m_score INT
) RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN
        RETURN 'Champion';
    ELSIF r_score >= 3 AND f_score >= 4 THEN
        RETURN 'Loyal';
    ELSIF r_score >= 4 AND f_score <= 2 THEN
        RETURN 'New / Promising';
    ELSIF r_score <= 2 AND f_score >= 3 THEN
        RETURN 'At Risk';
    ELSIF r_score <= 2 AND f_score <= 2 THEN
        RETURN 'Lost';
    ELSE
        RETURN 'Regular';
    END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- Materialized view that pre-computes RFM for every customer using the
-- function above. Refresh nightly in production: REFRESH MATERIALIZED VIEW ...
-- -----------------------------------------------------------------------------
DROP MATERIALIZED VIEW IF EXISTS mv_customer_rfm;
CREATE MATERIALIZED VIEW mv_customer_rfm AS
WITH analysis_date AS (
    SELECT MAX(order_date)::DATE + 1 AS today FROM orders
),
facts AS (
    SELECT
        co.customer_id,
        (SELECT today FROM analysis_date) - co.last_order_date AS recency_days,
        co.orders                                              AS frequency,
        co.realized_revenue                                    AS monetary
    FROM v_customer_orders co
),
scored AS (
    SELECT
        customer_id, recency_days, frequency, monetary,
        6 - NTILE(5) OVER (ORDER BY recency_days) AS r_score,
        NTILE(5) OVER (ORDER BY frequency)        AS f_score,
        NTILE(5) OVER (ORDER BY monetary)         AS m_score
    FROM facts
)
SELECT
    customer_id,
    recency_days,
    frequency,
    ROUND(monetary, 2) AS monetary,
    r_score, f_score, m_score,
    rfm_segment(r_score, f_score, m_score) AS segment
FROM scored;

CREATE UNIQUE INDEX idx_mv_customer_rfm_pk ON mv_customer_rfm (customer_id);

-- Quick rollup you can run after building it:
--   SELECT segment, COUNT(*), ROUND(SUM(monetary),0) AS revenue
--   FROM mv_customer_rfm GROUP BY segment ORDER BY revenue DESC;
