"""
Step 3: Model — execute the SQL view definitions in sql/ against the
cleaned (stg_*) tables. Safe to re-run any time a .sql file changes.

Usage:
    python scripts/03_build_views.py
"""
import sqlite3
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DB_PATH = PROJECT_ROOT / "data" / "processed" / "olist.db"
SQL_DIR = PROJECT_ROOT / "sql"

# Order matters: 04_cohort_view.sql and 03_funnel_view.sql both read from
# v_order_revenue, which is created in 01_revenue_views.sql.
SQL_FILES_IN_ORDER = [
    "01_revenue_views.sql",
    "02_seller_performance.sql",
    "03_funnel_view.sql",
    "04_cohort_view.sql",
]


def main():
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    for filename in SQL_FILES_IN_ORDER:
        path = SQL_DIR / filename
        print(f"Running {filename} ...")
        cur.executescript(path.read_text())

    conn.commit()

    views = cur.execute(
        "SELECT name FROM sqlite_master WHERE type='view' ORDER BY name"
    ).fetchall()
    conn.close()

    print(f"\nDone. {len(views)} views created:")
    for (name,) in views:
        print(f"  - {name}")


if __name__ == "__main__":
    main()
