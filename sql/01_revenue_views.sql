-- Module 1 (Business Analyst): revenue trend and regional views.
-- Built on the stg_* (cleaned) tables from scripts/02_clean.py.

-- ---------------------------------------------------------------------
-- v_order_revenue: one row per order-item, with order month, category,
-- and customer state attached. This is the base layer every revenue
-- view below reads from, so the join logic lives in exactly one place.
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS v_order_revenue;
CREATE VIEW v_order_revenue AS
SELECT
    oi.order_id,
    oi.product_id,
    oi.seller_id,
    oi.price,
    oi.freight_value,
    o.order_status,
    o.order_purchase_timestamp,
    strftime('%Y-%m', o.order_purchase_timestamp) AS order_month,
    p.product_category_name_english AS category,
    c.customer_state,
    c.customer_unique_id
FROM stg_order_items oi
JOIN stg_orders o        ON o.order_id = oi.order_id
JOIN stg_products p      ON p.product_id = oi.product_id
JOIN stg_customers c     ON c.customer_id = o.customer_id
WHERE o.order_status NOT IN ('canceled', 'unavailable');
-- Cancelled/unavailable orders never generated real revenue; excluding
-- them here means every downstream revenue view is automatically correct.

-- ---------------------------------------------------------------------
-- v_monthly_revenue_by_category: GMV per category per month, plus the
-- prior month's GMV and month-over-month % change (LAG window function)
-- so "top 5 growing / declining categories" (spec 6.2) is a one-line
-- filter on top of this view.
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS v_monthly_revenue_by_category;
CREATE VIEW v_monthly_revenue_by_category AS
WITH monthly AS (
    SELECT
        order_month,
        category,
        SUM(price) AS gmv,
        COUNT(DISTINCT order_id) AS orders,
        SUM(price) / COUNT(DISTINCT order_id) AS aov
    FROM v_order_revenue
    GROUP BY order_month, category
)
SELECT
    order_month,
    category,
    gmv,
    orders,
    aov,
    LAG(gmv) OVER (PARTITION BY category ORDER BY order_month) AS prev_month_gmv,
    ROUND(
        100.0 * (gmv - LAG(gmv) OVER (PARTITION BY category ORDER BY order_month))
        / NULLIF(LAG(gmv) OVER (PARTITION BY category ORDER BY order_month), 0),
        1
    ) AS mom_pct_change
FROM monthly;

-- ---------------------------------------------------------------------
-- v_regional_analysis: AOV, freight cost, and delivery time by state,
-- to spot regions that are underserved or disproportionately costly to
-- fulfill (spec 6.2).
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS v_regional_analysis;
CREATE VIEW v_regional_analysis AS
SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS orders,
    ROUND(SUM(oi.price) / COUNT(DISTINCT o.order_id), 2) AS aov,
    ROUND(AVG(oi.freight_value), 2) AS avg_freight,
    ROUND(AVG(oi.freight_value) / AVG(oi.price), 3) AS freight_ratio,
    ROUND(
        AVG(julianday(o.order_delivered_customer_date) - julianday(o.order_purchase_timestamp)),
        1
    ) AS avg_delivery_days
FROM stg_orders o
JOIN stg_order_items oi ON oi.order_id = o.order_id
JOIN stg_customers c    ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_state;
