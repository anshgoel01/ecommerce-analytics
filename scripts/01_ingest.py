"""
Step 1: Ingest — load the nine raw Olist CSVs into a SQLite database.

Reads everything as-is (no cleaning here — that happens in 02_clean.py), so
this script is safe to re-run any time the raw CSVs change. Table names drop
the olist_/_dataset boilerplate for readability.

Usage:
    python scripts/01_ingest.py
"""
import sqlite3
import sys
from pathlib import Path

import pandas as pd

PROJECT_ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = PROJECT_ROOT / "data" / "raw"
DB_PATH = PROJECT_ROOT / "data" / "processed" / "olist.db"

# (source csv filename, destination table name)
FILES_TO_TABLES = [
    ("olist_orders_dataset.csv", "orders"),
    ("olist_order_items_dataset.csv", "order_items"),
    ("olist_customers_dataset.csv", "customers"),
    ("olist_sellers_dataset.csv", "sellers"),
    ("olist_products_dataset.csv", "products"),
    ("olist_order_payments_dataset.csv", "order_payments"),
    ("olist_order_reviews_dataset.csv", "order_reviews"),
    ("olist_geolocation_dataset.csv", "geolocation"),
    ("product_category_name_translation.csv", "category_translation"),
]


def main():
    missing = [f for f, _ in FILES_TO_TABLES if not (RAW_DIR / f).exists()]
    if missing:
        print("Missing raw CSV files in data/raw/:")
        for f in missing:
            print(f"  - {f}")
        print(
            "\nDownload the dataset from "
            "https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce "
            "and unzip the CSVs into data/raw/ first."
        )
        sys.exit(1)

    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)

    for filename, table in FILES_TO_TABLES:
        path = RAW_DIR / filename
        print(f"Loading {filename} -> {table} ...", end=" ")
        df = pd.read_csv(path)
        df.to_sql(table, conn, if_exists="replace", index=False)
        print(f"{len(df):,} rows")

    conn.close()
    print(f"\nDone. Database written to {DB_PATH}")


if __name__ == "__main__":
    main()
