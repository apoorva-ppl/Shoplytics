-- =============================================================================
-- 10. Recursive CTE: full category hierarchy + rolled-up revenue
-- =============================================================================
-- Business question:
--   Show every category as a tree (Electronics > Computers > Laptops), and
--   for each *leaf*-category roll revenue all the way up to its top-level
--   department.
--
-- Techniques: recursive WITH, path-building via array_append, joining the
-- recursive output to a fact table for roll-up.
-- =============================================================================

SET search_path TO shop, public;

WITH RECURSIVE cat_tree AS (
    -- Anchor: top-level departments
    SELECT
        category_id,
        name,
        parent_category_id,
        1                                       AS depth,
        ARRAY[name]                             AS path,
        category_id                             AS root_category_id
    FROM categories
    WHERE parent_category_id IS NULL

    UNION ALL

    -- Recursive step: children inherit their parent's root
    SELECT
        child.category_id,
        child.name,
        child.parent_category_id,
        parent.depth + 1,
        parent.path || child.name,
        parent.root_category_id
    FROM categories child
    JOIN cat_tree   parent ON child.parent_category_id = parent.category_id
),
leaf_revenue AS (
    SELECT
        p.category_id,
        SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct/100.0)) AS revenue
    FROM order_items oi
    JOIN orders   o ON o.order_id   = oi.order_id AND o.status <> 'cancelled'
    JOIN products p ON p.product_id = oi.product_id
    GROUP BY p.category_id
)
SELECT
    ct.depth,
    REPEAT('  ', ct.depth - 1) || ct.name             AS indented_name,
    array_to_string(ct.path, ' > ')                   AS full_path,
    ROUND(COALESCE(lr.revenue, 0), 2)                  AS direct_revenue,
    -- Roll-up: total revenue underneath this node (including itself)
    ROUND( (
        SELECT COALESCE(SUM(lr2.revenue), 0)
        FROM cat_tree     descendant
        JOIN leaf_revenue lr2 ON lr2.category_id = descendant.category_id
        WHERE ct.name = ANY(descendant.path)
    ), 2)                                              AS rollup_revenue
FROM cat_tree ct
LEFT JOIN leaf_revenue lr ON lr.category_id = ct.category_id
ORDER BY ct.path;
