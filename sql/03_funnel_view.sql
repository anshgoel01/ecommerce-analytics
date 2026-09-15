-- Module 2 (Product Analyst): purchase funnel — stage completion and
-- time lag, at the order grain, with category/region attached so the
-- funnel can be segmented either way in the notebook or dashboard.

-- ---------------------------------------------------------------------
-- v_order_funnel_stages: one row per order with a completion flag and
-- elapsed-days-since-purchase for each of the five funnel stages (spec
-- 7.1). A CTE pulls each order's primary category (its highest-value
-- item, since an order can span categories) before joining it in.
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS v_order_funnel_stages;
CREATE VIEW v_order_funnel_stages AS
WITH order_primary_category AS (
    SELECT
        order_id,
        category,
        ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY price DESC) AS rn
    FROM v_order_revenue
)
SELECT
    o.order_id,
    c.customer_state,
    opc.category,
    o.order_purchase_timestamp,

    1 AS placed,
    CASE WHEN o.order_approved_at IS NOT NULL THEN 1 ELSE 0 END AS approved,
    CASE WHEN o.order_delivered_carrier_date IS NOT NULL THEN 1 ELSE 0 END AS shipped,
    CASE WHEN o.order_delivered_customer_date IS NOT NULL THEN 1 ELSE 0 END AS delivered,
    CASE WHEN r.review_id IS NOT NULL THEN 1 ELSE 0 END AS reviewed,

    julianday(o.order_approved_at) - julianday(o.order_purchase_timestamp) AS days_to_approved,
    julianday(o.order_delivered_carrier_date) - julianday(o.order_approved_at) AS days_to_shipped,
    julianday(o.order_delivered_customer_date) - julianday(o.order_delivered_carrier_date) AS days_to_delivered,
    julianday(r.review_creation_date) - julianday(o.order_delivered_customer_date) AS days_to_reviewed

FROM stg_orders o
JOIN stg_customers c ON c.customer_id = o.customer_id
LEFT JOIN order_primary_category opc ON opc.order_id = o.order_id AND opc.rn = 1
LEFT JOIN stg_order_reviews r ON r.order_id = o.order_id;

-- ---------------------------------------------------------------------
-- v_funnel_summary: overall stage counts, drop-off %, and median time
-- lag between consecutive stages. Filter v_order_funnel_stages directly
-- (WHERE category = ... / WHERE customer_state = ...) for the segmented
-- version of this same summary.
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS v_funnel_summary;
CREATE VIEW v_funnel_summary AS
SELECT
    SUM(placed)    AS n_placed,
    SUM(approved)  AS n_approved,
    SUM(shipped)   AS n_shipped,
    SUM(delivered) AS n_delivered,
    SUM(reviewed)  AS n_reviewed,
    ROUND(100.0 * SUM(approved)  / NULLIF(SUM(placed), 0), 2)    AS pct_approved,
    ROUND(100.0 * SUM(shipped)   / NULLIF(SUM(approved), 0), 2)  AS pct_shipped_of_approved,
    ROUND(100.0 * SUM(delivered) / NULLIF(SUM(shipped), 0), 2)   AS pct_delivered_of_shipped,
    -- NOT SUM(reviewed)/SUM(delivered): "reviewed" and "delivered" are not
    -- nested in this dataset (Olist can trigger a review survey off the
    -- ESTIMATED delivery date, independent of actual confirmation), so
    -- naively dividing produced a nonsensical 102%. Gate the numerator on
    -- delivered=1 explicitly instead. See PROBLEMS.md.
    ROUND(100.0 * SUM(delivered * reviewed) / NULLIF(SUM(delivered), 0), 2) AS pct_reviewed_of_delivered,
    ROUND(100.0 * SUM(reviewed) / NULLIF(SUM(placed), 0), 2) AS pct_reviewed_of_placed,
    ROUND(AVG(days_to_approved), 2)  AS avg_days_to_approved,
    ROUND(AVG(days_to_shipped), 2)   AS avg_days_to_shipped,
    ROUND(AVG(days_to_delivered), 2) AS avg_days_to_delivered,
    ROUND(AVG(days_to_reviewed), 2)  AS avg_days_to_reviewed
FROM v_order_funnel_stages;
