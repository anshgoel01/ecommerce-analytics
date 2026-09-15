# Problems Log

Issues hit while building this project, and how they were resolved. Newest entries at the top. This doubles as interview material — "tell me about a challenge you ran into" answers live here.

---

## 2026-09-15 — Couldn't push the built database to the Desktop directly

**Problem:** Two blockers, both on the delivery side rather than the analysis itself. (1) The file-transfer tool that copies files onto your Desktop caps each file at 20MB and 100MB per call — the built `olist.db` is ~173MB, and the raw `olist_geolocation_dataset.csv` alone is ~59MB, both over that per-file limit. (2) Running commands directly on your machine (which would have avoided the transfer entirely) is broken by a Windows update from September 8 unrelated to this project — Claude's remote shell can't currently mount your folders on this device.

**Solution:** Delivered `olist.db` (already ingested, cleaned, and with all 11 views built) as a direct chat download instead, for you to drop into `data/processed/olist.db`. Everything else (code, SQL, notebooks with real outputs, docs) went to the Desktop folder normally, since those are all small text files. You already have the original Kaggle zip on your machine (you attached it from there) — if you ever want the raw CSVs in `data/raw/` too (e.g., to re-run the pipeline from scratch), just unzip it there directly.

**Status:** Resolved via a workaround; not something to fix in the project itself.

---

## 2026-09-15 — Reviews table fanning out every join it touched (99,441 orders becoming 99,992 rows)

**Problem:** `v_order_funnel_stages` had 99,992 rows despite the `orders` table having exactly 99,441 rows — a silent fan-out from a `LEFT JOIN` that was supposed to be one-to-one. Traced it to `stg_order_reviews`: my original dedup logic (`02_clean.py`) deduplicated on `(order_id, review_id)`, which only removes exact-duplicate review rows. It missed that 547 orders in this dataset have more than one *genuinely distinct* `review_id` (a customer submitted a second review, or a re-sent survey generated a new id) — 551 extra rows in total. Every view that left-joins reviews to orders (`v_order_funnel_stages`, `v_seller_order_facts`, `v_delivery_delay_vs_review`) was silently counting some orders 2-3 times.

**Solution:** Changed the dedup key in `clean_order_reviews()` to `order_id` alone (keeping the most recently answered review per order), enforcing the one-review-per-order assumption every downstream view already relied on. Re-ran the full pipeline: `v_order_funnel_stages` now has exactly 99,441 rows matching 99,441 distinct order ids.

**Status:** Resolved. This is the kind of bug that doesn't throw an error or look obviously wrong (99,992 vs 99,441 both look like "a lot of orders") — caught it by cross-checking a view's row count against its known source-table count, which is worth doing as a standing habit after building any join-heavy view.

---

## 2026-09-15 — "Top growing categories" was measuring launch ramp-up, not a trend

**Problem:** The first version of the growing/declining-categories analysis (`notebooks/business_analysis.ipynb`) compared each category's first month of GMV to its last month. This produced absurd numbers like +89,161% for `health_beauty` — not because the category actually grew that much, but because the marketplace itself launched tiny (the whole platform did ~2 orders total in September 2016), so almost any category's "first month" was a near-zero denominator.

**Solution:** Changed the comparison to average GMV over each category's first 3 months present vs. its last 3 months, and added a minimum-GMV floor on the first window (R$300) to keep a near-zero denominator from producing a similarly misleading swing in the other direction. Growth percentages are still large (three-to-four digits) after the fix, but that now reflects genuine platform-wide growth over 2016-2018, not a single-order artifact — worth stating that context explicitly when presenting this number rather than quoting it bare.

**Status:** Resolved. Good example of a number that looked directionally right but needed a sanity check on *why* it was that large before trusting it.

---

## 2026-09-15 — `pct_reviewed_of_delivered` came out at 102% (impossible)

**Problem:** First run of `v_funnel_summary` on the real data showed `pct_reviewed_of_delivered = 102.29%` — a conversion rate over 100% is a logical impossibility and an immediate sign of a modeling bug, not a data quirk to shrug off. The view computed it as `SUM(reviewed) / SUM(delivered)`, implicitly assuming every reviewed order is also a delivered order (i.e., that "reviewed" is a subset of "delivered").

**Root cause:** Checked directly — cross-tabbing `delivered` x `reviewed` on `v_order_funnel_stages` showed 2,865 orders with a review but *not* marked delivered, and 646 delivered orders with *no* review. Olist appears to trigger review requests off the estimated delivery date rather than strictly gating them on confirmed delivery, so the two flags aren't nested the way a "funnel" assumes.

**Solution:** Changed the numerator to `SUM(delivered * reviewed)` — i.e., explicitly count orders that are *both* delivered *and* reviewed — instead of `SUM(reviewed)` alone. Also added `pct_reviewed_of_placed` as a second, unambiguous cut. Re-ran: now a sane 99.33%. Fixed in `sql/03_funnel_view.sql`, comment left in place explaining why the naive version was wrong.

**Status:** Resolved. Good interview example of catching a metric that's mechanically impossible rather than trusting the first number that comes out of a query.

---

## 2026-09-15 — Kaggle/Hugging Face unreachable from the build sandbox

**Problem:** Attempted to fetch the Olist dataset directly (first tried `kaggle.com`, then checked whether a Hugging Face mirror existed). Both hosts returned a connection-level 403 — blocked by the sandbox's network egress policy, not a missing-file or auth issue.

**Solution:** Asked the user to download the dataset zip from Kaggle themselves (one-click, no API key needed for the website download) and hand it off directly in the chat. Logged as a decision in DECISIONS.md. If this comes up in an interview: it's a good real example of working around an environment constraint rather than being blocked by it.

**Status:** Resolved — user provided `archive.zip` directly; all 9 CSVs verified present and matching the expected filenames before ingesting.
