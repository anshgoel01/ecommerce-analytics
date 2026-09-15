# One-Page Insight Summary

## Problem

E-commerce marketplaces sit between thousands of independent sellers and customers, and small operational frictions (a late delivery, a low-satisfaction seller) compound into real revenue and retention risk. This project analyzes ~99,441 real orders from Olist, a Brazilian e-commerce marketplace, to answer: **where is revenue concentrated and at risk, where does the purchase funnel leak, and what predicts whether a customer comes back?**

## Data

Olist Brazilian E-Commerce Public Dataset (Kaggle): 99,441 orders, 112,650 order items, 2016–2018, across 9 linked tables. Real, messy, multi-table data — cleaned and modeled into a SQLite database with 11 SQL views (see `sql/`). Two data-quality issues were found and fixed during cleaning; see `PROBLEMS.md` for the full account (worth reading before quoting any number below).

## Method

- SQL: CTEs and window functions (RANK, LAG, ROW_NUMBER) over multi-table joins to build revenue, seller-performance, funnel, and cohort views (`sql/`).
- Python: pandas for cleaning and aggregation, statsmodels for a logistic regression on repeat-purchase predictors, scipy for an as-if A/B test (two-sample t-test with 95% confidence interval).
- Dashboard: Streamlit + Plotly, five panels covering revenue, funnel, cohort, delivery/review, and seller segmentation.

## Insight

- **Delivery delay is the single strongest lever on satisfaction.** Average review score falls from 4.32 (delivered 7+ days early) to 1.70 (delivered 7+ days late) — a 2.6-point drop on a 5-point scale, and it's not a smooth decline: the cliff is between "1-3 days late" (3.29) and "4-7 days late" (2.10).
- **The funnel barely leaks after purchase — the real gap is unfulfilled promise, not process friction.** 99.84% of orders get approved, 98.4% of approved orders ship, 98.8% of shipped orders are marked delivered. The system executes reliably; the problem is what "on time" means to the customer (see above).
- **Seller quadrants split cleanly on delivery reliability, not just satisfaction.** High-revenue/low-satisfaction sellers (306 sellers, avg. R$19,073 revenue) have a 9.8% late-delivery rate, versus 6.1% for high-revenue/high-satisfaction sellers (304 sellers, avg. R$16,821 revenue) — the two groups generate similar revenue, but the low-satisfaction group is measurably less reliable on delivery.
- **Repeat purchase is rare (3.04% overall) and barely predictable from what we can observe.** A logistic regression on first-order value, category, and region explained almost none of the variance (pseudo-R² ≈ 0.002); first-order category alone shows more spread (furniture_decor ~4.7% repeat rate vs. electronics ~1.7%) than value or region do — a signal, but a weak one, on top of the honest headline that most Olist customers simply don't come back a second time.
- **Freight cost and delivery time both concentrate in the same handful of remote states** — Roraima, Maranhão, Rondônia, Amazonas, and Sergipe have the five highest freight ratios (24-28% of order value) and, unsurprisingly, some of the longest delivery times (19-28 days vs. 8.7 days for São Paulo, the hub state).
- **The as-if A/B test found no significant difference** between two volume-and-mix-matched states (Piauí vs. Rio Grande do Norte) on delivery time (p = 0.83, 95% CI for the difference: [-1.95, 1.57] days) — a clean negative result, useful as a calibration check that the test itself isn't biased toward finding effects.

## Recommendation

Prioritize a delivery-reliability intervention for the **high-revenue/low-satisfaction seller segment** (306 sellers) — they already drive comparable revenue to the top-satisfaction group, so closing their 9.8%→6.1% late-delivery gap is a retention lever without needing new seller acquisition. Separately, the five underserved remote states are a candidate for a regional logistics or fulfillment-partner review, since both cost and speed are worst there simultaneously rather than trading off against each other.
