# Decision Log

Every notable choice made while building this project, and why. Newest entries at the top.

---

## 2026-09-15 — Cohorting by `customer_unique_id`, not `customer_id`

**Decision:** All cohort/repeat-purchase logic (`sql/04_cohort_view.sql`) groups by `customer_unique_id`, and joins to `stg_orders` through `stg_customers` to get there — never by the raw `customer_id` on the orders table.

**Why:** This is a well-known Olist gotcha: `customer_id` is generated fresh for every order, so the same real shopper gets a different `customer_id` each time they buy. Cohorting on `customer_id` would make literally every customer look like a one-time buyer, which would silently produce a 0% repeat-purchase rate for every cohort — a wrong answer that looks plausible enough to ship by accident. `customer_unique_id` is the column that actually identifies the person across orders. Catching and explaining this is a good interview moment for the Data/Product Analyst framing (spec 8.1, 7.2).

---

## 2026-09-15 — Attributing a review to every seller on a multi-seller order

**Decision:** In `v_seller_order_facts` (`sql/02_seller_performance.sql`), when an order contains items from more than one seller, that order's single review score is counted toward *every* seller who fulfilled part of it.

**Why:** Reviews in this dataset are written per order, not per seller or per item, so there's no ground truth for which seller a low score is "really" about. Splitting blame proportionally (e.g., by revenue share) would imply a precision the data doesn't support. Counting the review for every contributing seller is the simplest defensible choice, and it's called out explicitly in the SQL comment and here rather than left as a silent assumption — worth naming up front if asked about seller-satisfaction numbers in an interview.

---

## 2026-09-15 — Raw tables kept alongside cleaned `stg_*` tables

**Decision:** `scripts/02_clean.py` writes cleaned tables as new `stg_<name>` tables in the same SQLite database, instead of overwriting the raw tables loaded by `01_ingest.py`. All SQL views (`sql/*.sql`) read only from `stg_*` tables.

**Why:** Keeps every cleaning step reversible and inspectable — a raw row can always be compared against its cleaned counterpart to sanity-check a transformation (e.g., "did that dedup actually drop the row I think it did?"), without re-running ingestion. Costs a bit of extra disk space, which is a non-issue at this dataset's size (~100K orders).

---

## 2026-09-15 — Project location: build in a sandbox, ship to Desktop

**Decision:** Build and iterate on the project in Claude's cloud workspace, then sync finished files onto the user's Desktop (`OneDrive/Desktop/ecommerce-analytics-project/`) rather than working directly on the Desktop folder from the start.

**Why:** The build needs Python packages (pandas, scipy, statsmodels, streamlit, sqlite3), possibly a database engine, and iterative script/notebook runs. Doing this in a disposable sandbox keeps false starts and package installs off the user's machine, and the finished, working files get copied over once they're actually done — no half-built state ever lands on the Desktop.

**Alternatives considered:** Working directly on the Desktop via a local shell — rejected for this project because of the volume of iteration expected (multiple SQL views, notebooks, a dashboard app) and because dataset download/package installs are more reliable in the sandbox.

---

## 2026-09-15 — Dataset acquisition: manual download by user

**Decision:** The user downloads the Olist Kaggle zip themselves and provides it; Claude does not attempt to fetch it directly.

**Why:** `kaggle.com` and `huggingface.co` (checked as a possible mirror) are both blocked by the cloud sandbox's network policy (403 at the connection level, not just a tool-level restriction). Kaggle downloads also require a logged-in account, which the sandbox has no way to authenticate as. Asking the user to download once (a single click on kaggle.com/datasets/olistbr/brazilian-ecommerce) is the fastest reliable path.

**Alternatives considered:** Driving the user's browser via computer-use automation to download it — kept as a fallback if the manual download is inconvenient for the user, but not the default since it depends on an existing logged-in Kaggle session on their machine.

---

## 2026-09-15 — Database engine: SQLite over PostgreSQL

**Decision:** Use SQLite (a single `.db` file in `data/processed/`) instead of PostgreSQL for the SQL layer.

**Why:** The spec lists PostgreSQL as the primary option with "SQLite for a lighter setup" as the explicit alternative. For a portfolio project that needs to be cloned and run by anyone (including an interviewer skimming the GitHub repo), a self-contained database file with zero server setup is a real advantage — no install, no service to run, no connection string to configure. Modern SQLite (3.25+) fully supports window functions (RANK, LAG, ROW_NUMBER), CTEs, and multi-table joins, so none of the SQL techniques the spec wants demonstrated (Section 8.1) are lost. The `.sql` view files are written in standard-enough SQL that porting to Postgres later is a low-effort README note, not a rewrite.

**Alternatives considered:** PostgreSQL — would better mirror a production analytics stack and is worth mentioning as a "next step" in the README, but adds a service dependency that doesn't help a portfolio piece meant to run anywhere with just Python installed.

---

## 2026-09-15 — Dashboard: Streamlit + Plotly over Tableau/Power BI

**Decision:** Build the interactive dashboard as a Streamlit app (using Plotly for charts) rather than Tableau Public or Power BI.

**Why:** Streamlit + Plotly is pure code, which means it can be built, version-controlled, and committed to the GitHub repo like the rest of the project, and it deploys for free to a public URL (Streamlit Community Cloud) for the "shareable dashboard link" deliverable (Section 9). Tableau and Power BI are GUI desktop applications that can't be built or automated from here, and would require the user to manually recreate every chart by hand inside that application.

**Alternatives considered:** Tableau Public — produces a very polished, recruiter-familiar dashboard and is worth doing by hand later if the user wants that specific skill on display; Power BI — similar tradeoff, plus less common outside Microsoft-shop interviews.

---

## 2026-09-15 — Folder structure and tracking docs

**Decision:** Use the exact folder structure from the spec (Section 11), and add two extra top-level files: `DECISIONS.md` (this file) and `PROBLEMS.md` (issues hit + how they were resolved), updated as the build progresses.

**Why:** User asked for these explicitly, on top of the deliverables the spec already calls for (README, insight summary). They also double as strong interview material — "why did you choose X" and "what went wrong and how did you fix it" are exactly the questions this project is meant to prepare for.
