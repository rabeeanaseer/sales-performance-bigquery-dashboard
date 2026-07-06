# Setup Guide: BigQuery Sandbox → Power BI / Tableau

## Part A — Get the data into BigQuery Sandbox (free, no credit card)

1. **Create a Google Cloud project**
   Go to https://console.cloud.google.com → create a new project. You will NOT be asked for a billing account if you stay in Sandbox mode — BigQuery automatically runs Sandbox when no billing account is linked.

2. **Open BigQuery**
   Console → search "BigQuery" → this opens the BigQuery Studio/editor for your project.

3. **Create the dataset**
   Either run the `CREATE SCHEMA` statement at the top of `01_schema_ddl.sql`, or use the UI: click your project name → **Create Dataset** → name it `sales_dw` → region `US` (or your nearest multi-region — keep it consistent across all tables).

4. **Create the tables**
   Paste the full contents of `01_schema_ddl.sql` into the BigQuery query editor and run it. This creates `dim_date`, `dim_customers`, `dim_products`, `dim_locations`, and `fact_sales` as empty, correctly-typed tables.

5. **Load the source CSV**
   Two options:
   - **UI upload (simplest):** In the dataset, click **Create Table** → Source: *Upload* → select your cleaned CSV per dimension/fact → Destination: matching table name → under **Schema**, either auto-detect or manually map to the DDL above → set **Write preference** to "Append" if the table already has the DDL-defined schema.
   - **CLI (`bq load`), if you have the Cloud SDK locally:**
     ```
     bq load --source_format=CSV --skip_leading_rows=1 \
       your_project:sales_dw.fact_sales \
       ./data/fact_sales.csv \
       ./schemas/fact_sales_schema.json
     ```
   Note: you will need to pre-process the flat Global Superstore file into the four dimension shapes + fact shape (a simple Python/pandas or even spreadsheet split) before loading — the DDL expects the star schema shape, not the flat original.

6. **Sandbox limits to be aware of**
   - 10 GB storage free, 1 TB query processing free per month — a 10k-row retail dataset is nowhere close to either limit.
   - Sandbox tables expire after 60 days of no updates unless you upgrade to a billing account (still free-tier eligible, just requires a card on file). For a portfolio project you can simply re-run the load if it expires.
   - No streaming inserts in Sandbox mode — batch/file loads only, which is exactly what we're doing above.

7. **Validate the load**
   Run `02_analytics_queries.sql` — if it returns clean rows without null-heavy joins, your keys are aligned correctly across fact and dimension tables.

---

## Part B — Connect to Power BI Desktop (recommended path)

1. Open Power BI Desktop → **Get Data** → search **"Google BigQuery"** (built-in connector, no separate driver install needed).
2. Sign in with the same Google account used to create the Sandbox project — this uses OAuth, not a service account key, so there's no billing/credentials file to manage.
3. Select your project → `sales_dw` dataset → check the tables you want (fact + all dimensions).
4. Choose **DirectQuery** if you want live BigQuery queries on every interaction, or **Import** if you want the data cached in Power BI's in-memory engine (Import is usually smoother for a portfolio-sized dataset and avoids Sandbox query-limit edge cases).
5. In the Power BI model view, draw relationships: `fact_sales.customer_key → dim_customers.customer_key`, and similarly for `product_key`, `location_key`, and `order_date → dim_date.date_key`. This is the moment the star schema actually pays off — Power BI's relationship engine expects exactly this shape.
6. Build visuals against the DAX/measure layer, using the KPI formulas defined in the README.

## Part B (alt) — Connect to Tableau

Tableau Desktop has a native **Google BigQuery** connector under **Connect → To a Server**, using the same OAuth flow as above.

**Important distinction for Tableau Public specifically:** Tableau Public does not support a live/direct connection to external databases like BigQuery — Tableau Public workbooks only accept data via extracts. The practical path is:
1. Connect to BigQuery from **Tableau Desktop** (use the free trial if you don't have a license).
2. Build your visuals, then convert the data source to an **extract** (Data → Extract).
3. **Save to Tableau Public** from Desktop — this uploads the extract-backed workbook to your public profile, which anyone can then view without needing BigQuery credentials themselves.

This also has a side benefit for a portfolio piece: an extract-based public workbook loads fast for recruiters/hiring managers, with no live-query latency or Sandbox rate limits in their way.

---

## Common gotchas

- **"Access Denied" in Power BI/Tableau:** almost always means you're signed into the wrong Google account (a personal Gmail vs. the one you used to create the GCP project). Sign out and re-auth explicitly.
- **Relationships not working in Power BI:** confirm the join key columns are the *same data type* on both sides (e.g., `STRING` surrogate keys, not one side as `INT64`).
- **DATE vs TIMESTAMP mismatches:** `dim_date.date_key` is `DATE`; if `fact_sales.order_date` was loaded as `TIMESTAMP` by auto-detect, the relationship will silently fail. Cast explicitly (`CAST(order_date AS DATE)`) if needed.
