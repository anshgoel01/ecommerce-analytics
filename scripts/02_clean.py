"""
Step 2: Clean — handle nulls, duplicate rows, inconsistent timestamps, and
numeric/currency formatting.

Raw tables loaded by 01_ingest.py are left untouched; this script writes
cleaned versions as new tables prefixed `stg_` (staging) in the same SQLite
database, so you can always compare a cleaned row back to its raw source.
The SQL views in sql/ are built on top of the stg_ tables, not the raw ones.

Usage:
    python scripts/02_clean.py
"""
import sqlite3
from pathlib import Path

import pandas as pd

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DB_PATH = PROJECT_ROOT / "data" / "processed" / "olist.db"

TIMESTAMP_COLS_BY_TABLE = {
    "orders": [
        "order_purchase_timestamp",
        "order_approved_at",
        "order_delivered_carrier_date",
        "order_delivered_customer_date",
        "order_estimated_delivery_date",
    ],
    "order_items": ["shipping_limit_date"],
    "order_reviews": ["review_creation_date", "review_answer_timestamp"],
}


def read_table(conn, name):
    return pd.read_sql(f"SELECT * FROM {name}", conn)


def parse_timestamps(df, cols):
    for col in cols:
        if col in df.columns:
            df[col] = pd.to_datetime(df[col], errors="coerce")
    return df


def clean_orders(conn):
    df = read_table(conn, "orders")
    before = len(df)
    df = df.drop_duplicates(subset=["order_id"])
    df = parse_timestamps(df, TIMESTAMP_COLS_BY_TABLE["orders"])
    dropped = before - len(df)
    print(f"orders: {before:,} -> {len(df):,} rows ({dropped} duplicate order_id dropped)")
    return df


def clean_order_items(conn):
    df = read_table(conn, "order_items")
    before = len(df)
    df = df.drop_duplicates()
    df = parse_timestamps(df, TIMESTAMP_COLS_BY_TABLE["order_items"])
    # Currency/numeric formatting: force price & freight_value to numeric,
    # coerce anything unparseable to NaN rather than silently keeping a
    # string, then drop rows where the core money fields are unusable.
    for col in ["price", "freight_value"]:
        df[col] = pd.to_numeric(df[col], errors="coerce").round(2)
    bad_money = df[["price", "freight_value"]].isna().any(axis=1)
    if bad_money.any():
        print(f"order_items: dropping {bad_money.sum()} rows with unparseable price/freight_value")
        df = df[~bad_money]
    dropped = before - len(df)
    print(f"order_items: {before:,} -> {len(df):,} rows ({dropped} dropped total)")
    return df


def clean_customers(conn):
    df = read_table(conn, "customers")
    before = len(df)
    df = df.drop_duplicates(subset=["customer_id"])
    for col in ["customer_city", "customer_state"]:
        df[col] = df[col].astype(str).str.strip().str.lower()
    print(f"customers: {before:,} -> {len(df):,} rows")
    return df


def clean_sellers(conn):
    df = read_table(conn, "sellers")
    before = len(df)
    df = df.drop_duplicates(subset=["seller_id"])
    for col in ["seller_city", "seller_state"]:
        df[col] = df[col].astype(str).str.strip().str.lower()
    print(f"sellers: {before:,} -> {len(df):,} rows")
    return df


def clean_products(conn):
    products = read_table(conn, "products")
    translation = read_table(conn, "category_translation")
    before = len(products)
    products = products.drop_duplicates(subset=["product_id"])

    products["product_category_name"] = products["product_category_name"].str.strip()
    merged = products.merge(translation, on="product_category_name", how="left")
    merged["product_category_name_english"] = merged[
        "product_category_name_english"
    ].fillna("unknown")
    merged["product_category_name"] = merged["product_category_name"].fillna("unknown")

    print(f"products: {before:,} -> {len(merged):,} rows")
    n_unknown = (merged["product_category_name_english"] == "unknown").sum()
    print(f"products: {n_unknown} rows with missing/untranslated category -> 'unknown'")
    return merged


def clean_order_payments(conn):
    df = read_table(conn, "order_payments")
    before = len(df)
    df = df.drop_duplicates()
    df["payment_value"] = pd.to_numeric(df["payment_value"], errors="coerce").round(2)
    df = df[df["payment_value"].notna()]
    print(f"order_payments: {before:,} -> {len(df):,} rows")
    return df


def clean_order_reviews(conn):
    df = read_table(conn, "order_reviews")
    before = len(df)
    df = parse_timestamps(df, TIMESTAMP_COLS_BY_TABLE["order_reviews"])
    # Deduping on (order_id, review_id) is NOT enough: 547 orders in this
    # dataset have more than one genuinely distinct review_id (a customer
    # submitted more than one review, or a re-sent survey got a new id).
    # Every downstream view joins reviews to orders assuming one review per
    # order -- left as (order_id, review_id), those 547 orders silently
    # fanned out (99,441 orders -> 99,992 rows in v_order_funnel_stages,
    # inflating funnel/seller/delivery-review numbers). Dedup on order_id
    # alone, keeping the most recently answered review.
    df = df.sort_values("review_answer_timestamp").drop_duplicates(
        subset=["order_id"], keep="last"
    )
    dropped = before - len(df)
    print(f"order_reviews: {before:,} -> {len(df):,} rows ({dropped} rows dropped to enforce 1 review per order)")
    return df


def clean_geolocation(conn):
    df = read_table(conn, "geolocation")
    before = len(df)
    # Many rows per zip-code prefix with near-identical coordinates; this
    # table is only ever used to look up an approximate lat/lng per zip, so
    # collapse to one averaged row per prefix rather than carrying the
    # duplication downstream.
    agg = (
        df.groupby("geolocation_zip_code_prefix")
        .agg(
            geolocation_lat=("geolocation_lat", "mean"),
            geolocation_lng=("geolocation_lng", "mean"),
            geolocation_city=("geolocation_city", "first"),
            geolocation_state=("geolocation_state", "first"),
        )
        .reset_index()
    )
    print(f"geolocation: {before:,} rows -> {len(agg):,} unique zip prefixes")
    return agg


def main():
    conn = sqlite3.connect(DB_PATH)

    cleaners = {
        "stg_orders": clean_orders,
        "stg_order_items": clean_order_items,
        "stg_customers": clean_customers,
        "stg_sellers": clean_sellers,
        "stg_products": clean_products,
        "stg_order_payments": clean_order_payments,
        "stg_order_reviews": clean_order_reviews,
        "stg_geolocation": clean_geolocation,
    }

    for table_name, fn in cleaners.items():
        df = fn(conn)
        df.to_sql(table_name, conn, if_exists="replace", index=False)

    conn.close()
    print(f"\nDone. Cleaned (stg_*) tables written to {DB_PATH}")


if __name__ == "__main__":
    main()
