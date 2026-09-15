-- Module 2 (Product Analyst): cohort / repeat-purchase analysis.
--
-- Important dataset nuance: `customer_id` in this dataset is generated
-- PER ORDER — the same real shopper gets a new customer_id every time
-- they order. `customer_unique_id` is the actual person. Cohorting or
-- counting "repeat purchasers" on customer_id would make every customer
-- look like a one-time buyer by construction. Everything below keys off
-- customer_unique_id. (See DECISIONS.md.)

-- ---------------------------------------------------------------------
-- v_customer_first_order: each person's first order — its month,
-- category, value, and region — found with ROW_NUMBER (a window
-- function) instead of a correlated MIN() subquery per customer.
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS v_customer_first_order;
CREATE VIEW v_customer_first_order AS
WITH customer_orders AS (
    SELECT
        c.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp,
        c.customer_state,
        ROW_NUMBER() OVER (
            PARTITION BY c.customer_unique_id ORDER BY o.order_purchase_timestamp
        ) AS order_seq
    FROM stg_orders o
    JOIN stg_customers c ON c.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
),
first_order_value AS (
    SELECT order_id, SUM(price) AS order_value
    FROM stg_order_items
    GROUP BY order_id
),
first_order_category AS (
    SELECT order_id, category
    FROM (
        SELECT order_id, category,
               ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY price DESC) AS rn
        FROM v_order_revenue
    )
    WHERE rn = 1
)
SELECT
    co.customer_unique_id,
    co.order_id AS first_order_id,
    strftime('%Y-%m', co.order_purchase_timestamp) AS cohort_month,
    co.customer_state AS first_order_state,
    fov.order_value AS first_order_value,
    foc.category AS first_order_category
FROM customer_orders co
LEFT JOIN first_order_value fov ON fov.order_id = co.order_id
LEFT JOIN first_order_category foc ON foc.order_id = co.order_id
WHERE co.order_seq = 1;

-- ---------------------------------------------------------------------
-- v_customer_cohort: adds whether each person ever placed a second
-- order (is_repeat_purchaser), joined to their first-order attributes —
-- the base table for "what predicts a second purchase?" (spec 7.2).
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS v_customer_cohort;
CREATE VIEW v_customer_cohort AS
WITH order_counts AS (
    SELECT c.customer_unique_id, COUNT(DISTINCT o.order_id) AS n_orders
    FROM stg_orders o
    JOIN stg_customers c ON c.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY c.customer_unique_id
)
SELECT
    f.customer_unique_id,
    f.cohort_month,
    f.first_order_state,
    f.first_order_value,
    f.first_order_category,
    oc.n_orders,
    CASE WHEN oc.n_orders > 1 THEN 1 ELSE 0 END AS is_repeat_purchaser
FROM v_customer_first_order f
JOIN order_counts oc ON oc.customer_unique_id = f.customer_unique_id;

-- ---------------------------------------------------------------------
-- v_cohort_repeat_rate: % of each cohort that became repeat purchasers.
-- The "retention curve" for this dataset (spec 7.2) — one number per
-- cohort month rather than a month-by-month decay curve, since ~97% of
-- customers here never order again regardless of how long you wait.
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS v_cohort_repeat_rate;
CREATE VIEW v_cohort_repeat_rate AS
SELECT
    cohort_month,
    COUNT(*) AS cohort_size,
    SUM(is_repeat_purchaser) AS repeat_purchasers,
    ROUND(100.0 * SUM(is_repeat_purchaser) / COUNT(*), 2) AS repeat_rate_pct
FROM v_customer_cohort
GROUP BY cohort_month
ORDER BY cohort_month;
