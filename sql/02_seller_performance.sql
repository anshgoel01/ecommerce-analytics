-- Module 1 (Business Analyst): seller performance & quadrant segmentation.

-- ---------------------------------------------------------------------
-- v_seller_order_facts: one row per (order, seller) pairing an order's
-- review score and late-delivery flag with the seller who fulfilled it.
-- Note: a review is written per ORDER, not per seller, so when an order
-- has items from multiple sellers, that same review score is counted
-- for each of them. This is a known simplification (documented here and
-- in DECISIONS.md) rather than a bug — the alternative, splitting a
-- review's "blame" across sellers, has no principled rule to do it by.
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS v_seller_order_facts;
CREATE VIEW v_seller_order_facts AS
SELECT
    oi.seller_id,
    o.order_id,
    oi.price,
    r.review_score,
    CASE
        WHEN o.order_delivered_customer_date IS NOT NULL
             AND o.order_delivered_customer_date > o.order_estimated_delivery_date
        THEN 1 ELSE 0
    END AS is_late
FROM stg_order_items oi
JOIN stg_orders o ON o.order_id = oi.order_id
LEFT JOIN stg_order_reviews r ON r.order_id = o.order_id
WHERE o.order_status = 'delivered';

-- ---------------------------------------------------------------------
-- v_seller_performance: revenue, review score, late-delivery rate per
-- seller, ranked by revenue (RANK window function), and segmented into
-- quadrants against the overall seller-base averages (spec 6.2).
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS v_seller_performance;
CREATE VIEW v_seller_performance AS
WITH seller_agg AS (
    SELECT
        seller_id,
        COUNT(DISTINCT order_id) AS orders,
        SUM(price) AS revenue,
        ROUND(AVG(review_score), 2) AS avg_review_score,
        ROUND(1.0 * SUM(is_late) / COUNT(*), 3) AS late_delivery_rate
    FROM v_seller_order_facts
    GROUP BY seller_id
),
with_benchmarks AS (
    SELECT
        *,
        AVG(revenue) OVER () AS overall_avg_revenue,
        AVG(avg_review_score) OVER () AS overall_avg_review_score,
        RANK() OVER (ORDER BY revenue DESC) AS revenue_rank
    FROM seller_agg
)
SELECT
    seller_id,
    orders,
    revenue,
    avg_review_score,
    late_delivery_rate,
    revenue_rank,
    CASE
        WHEN revenue >= overall_avg_revenue AND avg_review_score >= overall_avg_review_score
            THEN 'high_revenue_high_satisfaction'
        WHEN revenue >= overall_avg_revenue AND avg_review_score < overall_avg_review_score
            THEN 'high_revenue_low_satisfaction'
        WHEN revenue < overall_avg_revenue AND avg_review_score >= overall_avg_review_score
            THEN 'low_revenue_high_satisfaction'
        ELSE 'low_revenue_low_satisfaction'
    END AS quadrant
FROM with_benchmarks;

-- ---------------------------------------------------------------------
-- v_delivery_delay_vs_review: buckets orders by how late they were
-- delivered (vs. the estimated date) and compares average review score
-- across buckets (spec 6.2).
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS v_delivery_delay_vs_review;
CREATE VIEW v_delivery_delay_vs_review AS
WITH delay AS (
    SELECT
        o.order_id,
        r.review_score,
        CAST(julianday(o.order_delivered_customer_date) - julianday(o.order_estimated_delivery_date) AS INTEGER) AS delay_days
    FROM stg_orders o
    JOIN stg_order_reviews r ON r.order_id = o.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
)
SELECT
    CASE
        WHEN delay_days <= -7 THEN '1. 7+ days early'
        WHEN delay_days <= 0  THEN '2. on time / a little early'
        WHEN delay_days <= 3  THEN '3. 1-3 days late'
        WHEN delay_days <= 7  THEN '4. 4-7 days late'
        ELSE '5. 7+ days late'
    END AS delay_bucket,
    COUNT(*) AS orders,
    ROUND(AVG(review_score), 2) AS avg_review_score
FROM delay
GROUP BY delay_bucket
ORDER BY delay_bucket;
