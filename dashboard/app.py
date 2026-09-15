"""
Interactive dashboard — Module 3 (Data Analyst) deliverable.

Panels (spec §8.2):
  Revenue Trend        | line chart, monthly GMV      | filter: category, region
  Purchase Funnel      | funnel chart                 | filter: category, month
  Cohort Retention     | heatmap                       | filter: cohort month
  Delivery vs. Review  | scatter / grouped bar         | filter: region
  Seller Segmentation  | quadrant scatter              | filter: revenue tier

Run with:
    streamlit run dashboard/app.py
"""
import sqlite3
from pathlib import Path

import pandas as pd
import plotly.express as px
import streamlit as st

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DB_PATH = PROJECT_ROOT / "data" / "processed" / "olist.db"

st.set_page_config(page_title="Olist E-Commerce Analytics", layout="wide")


@st.cache_resource
def get_connection():
    return sqlite3.connect(DB_PATH, check_same_thread=False)


@st.cache_data
def load(sql):
    return pd.read_sql(sql, get_connection())


if not DB_PATH.exists():
    st.error(
        f"Database not found at `{DB_PATH}`.\n\n"
        "Run `python scripts/01_ingest.py`, `02_clean.py`, and `03_build_views.py` first."
    )
    st.stop()

st.title("Olist E-Commerce Analytics Dashboard")
st.caption(
    "Business, product, and SQL-engineering modules from a single dataset — "
    "see README.md for the full project write-up."
)

tab_revenue, tab_funnel, tab_cohort, tab_delivery, tab_sellers = st.tabs(
    ["Revenue Trend", "Purchase Funnel", "Cohort Retention", "Delivery vs. Review", "Seller Segmentation"]
)

# ---------------------------------------------------------------------
# Revenue Trend
# ---------------------------------------------------------------------
with tab_revenue:
    rev = load("SELECT * FROM v_monthly_revenue_by_category")
    regional = load("SELECT DISTINCT customer_state FROM stg_customers ORDER BY customer_state")

    categories = sorted(rev["category"].dropna().unique())
    col1, col2 = st.columns(2)
    picked_categories = col1.multiselect("Category", categories, default=categories[:5])
    st.caption("Region filtering for revenue requires joining v_order_revenue by state — see notebooks/business_analysis.ipynb for the region-level cut.")

    filtered = rev[rev["category"].isin(picked_categories)] if picked_categories else rev
    fig = px.line(filtered, x="order_month", y="gmv", color="category", title="Monthly GMV by category")
    st.plotly_chart(fig, use_container_width=True)

# ---------------------------------------------------------------------
# Purchase Funnel
# ---------------------------------------------------------------------
with tab_funnel:
    stages = load("SELECT * FROM v_order_funnel_stages")
    categories = sorted(stages["category"].dropna().unique())
    picked = st.selectbox("Category (optional filter)", ["All"] + categories)

    df = stages if picked == "All" else stages[stages["category"] == picked]
    counts = df[["placed", "approved", "shipped", "delivered", "reviewed"]].sum()
    fig = px.funnel(
        x=counts.values,
        y=["Placed", "Approved", "Shipped", "Delivered", "Reviewed"],
        title=f"Purchase funnel — {picked}",
    )
    st.plotly_chart(fig, use_container_width=True)

# ---------------------------------------------------------------------
# Cohort Retention
# ---------------------------------------------------------------------
with tab_cohort:
    cohort = load("SELECT * FROM v_cohort_repeat_rate")
    fig = px.bar(
        cohort, x="cohort_month", y="repeat_rate_pct",
        title="Repeat-purchase rate by cohort (month of first purchase)",
        hover_data=["cohort_size", "repeat_purchasers"],
    )
    st.plotly_chart(fig, use_container_width=True)
    st.caption(
        "Shown as a bar (not a monthly retention-decay heatmap) because most Olist "
        "customers buy exactly once — see DECISIONS.md / product_analysis.ipynb."
    )

# ---------------------------------------------------------------------
# Delivery vs. Review
# ---------------------------------------------------------------------
with tab_delivery:
    delay = load("SELECT * FROM v_delivery_delay_vs_review")
    fig = px.bar(
        delay, x="delay_bucket", y="avg_review_score", text="orders",
        title="Average review score by delivery-delay bucket",
    )
    st.plotly_chart(fig, use_container_width=True)

# ---------------------------------------------------------------------
# Seller Segmentation
# ---------------------------------------------------------------------
with tab_sellers:
    sellers = load("SELECT * FROM v_seller_performance")
    tier = st.select_slider(
        "Minimum revenue tier (percentile)", options=[0, 25, 50, 75, 90], value=0
    )
    cutoff = sellers["revenue"].quantile(tier / 100)
    filtered = sellers[sellers["revenue"] >= cutoff]

    fig = px.scatter(
        filtered, x="revenue", y="avg_review_score", color="quadrant", size="orders",
        hover_data=["seller_id", "late_delivery_rate"],
        title="Seller segmentation: revenue vs. satisfaction",
    )
    st.plotly_chart(fig, use_container_width=True)
    st.dataframe(filtered["quadrant"].value_counts().rename("seller_count"))
