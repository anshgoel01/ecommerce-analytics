# E-Commerce Analytics Project

An end-to-end analytics case study on the [Olist Brazilian E-Commerce dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) (~100K real, anonymized orders, 2016-2018), built as a single portfolio project that supports Business Analyst, Product Analyst, and Data Analyst interview conversations.

Rather than three shallow projects, this is one deep project structured into three modules — revenue & operations, product funnel & retention, and SQL/dashboard engineering — so the same repo, dashboard, and story can be led with differently depending on the role.

> **Status:** Pipeline, SQL layer, all three notebooks, and the dashboard are built and have been run end-to-end on the real dataset (99,441 orders). See `docs/insight_summary.md` for the headline findings, `DECISIONS.md` for why things were built the way they were, and `PROBLEMS.md` for issues hit along the way (including two real data bugs the SQL layer caught) — both logs are updated as the project develops further (dashboard deployment, screenshots, polish).

## Project structure

```
ecommerce-analytics-project/
├── data/
│   ├── raw/          # original CSVs (gitignored — see Setup)
│   └── processed/    # cleaned data + SQLite database
├── sql/              # SQL views: revenue, seller performance, funnel, cohort
├── notebooks/        # business / product / A-B test analysis notebooks
├── dashboard/        # Streamlit + Plotly dashboard app
├── docs/             # insight summary, screenshots
├── DECISIONS.md       # decision log with reasoning
├── PROBLEMS.md        # problems hit + how they were solved
└── README.md
```

## Modules

| Module | Audience | Covers |
|---|---|---|
| 1. Revenue & Operations | Business Analyst | Revenue trends by category, seller segmentation, delivery-delay vs. review score, regional analysis |
| 2. Funnel, Retention & Experimentation | Product Analyst | Purchase funnel drop-off, cohort repeat-purchase analysis, A/B test simulation |
| 3. SQL & Dashboard | Data Analyst | CTEs, window functions, multi-table joins, an interactive Streamlit dashboard |

## Tech stack

- **Database:** SQLite (see `DECISIONS.md` for why over PostgreSQL)
- **Processing:** Python — pandas, numpy
- **Stats:** scipy, statsmodels
- **Dashboard:** Streamlit + Plotly
- **Notebooks:** Jupyter

## Setup

1. **Get the data.** Download the dataset from [Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) (free account required) and unzip the 9 CSVs into `data/raw/`. You should end up with:
   ```
   data/raw/olist_orders_dataset.csv
   data/raw/olist_order_items_dataset.csv
   data/raw/olist_customers_dataset.csv
   data/raw/olist_sellers_dataset.csv
   data/raw/olist_products_dataset.csv
   data/raw/olist_order_payments_dataset.csv
   data/raw/olist_order_reviews_dataset.csv
   data/raw/olist_geolocation_dataset.csv
   data/raw/product_category_name_translation.csv
   ```

2. **Install dependencies:**
   ```
   pip install -r requirements.txt
   ```

3. **Build the database** (ingest + clean the raw CSVs into `data/processed/olist.db`):
   ```
   python scripts/01_ingest.py
   python scripts/02_clean.py
   ```

4. **Create the SQL views:**
   ```
   python scripts/03_build_views.py
   ```

5. **Run the dashboard:**
   ```
   streamlit run dashboard/app.py
   ```

6. **Explore the notebooks** in `notebooks/` for the business, product, and A/B-test writeups.

## Deliverables (tracked against the project spec)

- [x] SQL views committed to `sql/` (11 views, using CTEs, window functions, multi-table joins)
- [x] Business analysis notebook — run on real data, see `notebooks/business_analysis.ipynb`
- [x] Product/funnel/retention notebook — run on real data, see `notebooks/product_analysis.ipynb`
- [x] A/B test simulation notebook — run on real data, see `notebooks/ab_test_simulation.ipynb`
- [x] Streamlit dashboard (revenue, funnel, cohort, delivery/review, seller segmentation panels) — smoke-tested locally
- [x] One-page insight summary (`docs/insight_summary.md`) — filled in with real numbers
- [ ] Dashboard deployed to a public URL (Streamlit Community Cloud) for the shareable link
- [ ] Dashboard screenshots in `docs/screenshots/`
- [ ] GitHub repo initialized and pushed
- [x] This README, kept current

## Data quality findings worth knowing before quoting any number

Two real bugs were caught and fixed while building the SQL layer — both are the kind of thing worth mentioning in an interview as "here's how I validated my own numbers," not just "here's the number":

1. **Reviews table fan-out:** 547 orders have more than one genuinely distinct review. Left un-deduplicated, every join touching reviews silently double/triple-counted those orders. Fixed by keeping one (the most recent) review per order.
2. **`customer_id` is per-order, not per-person:** cohort/repeat-purchase logic must use `customer_unique_id` instead, or every customer looks like a one-time buyer by construction.

Full details, plus a third fix (a misleading "top growing category" calculation caused by the marketplace's own launch ramp-up), are in `PROBLEMS.md`.
