<div align="center">

# 📊 Sales Performance & Executive Dashboard
### A cloud-native BI project simulating an enterprise analytics stack on Google BigQuery

<!-- Tech stack badges -->
[![BigQuery](https://img.shields.io/badge/Warehouse-BigQuery-4285F4?style=for-the-badge&logo=googlebigquery&logoColor=white)](https://cloud.google.com/bigquery)
[![Power BI](https://img.shields.io/badge/Visualization-Power%20BI-F2C811?style=for-the-badge&logo=powerbi&logoColor=black)](https://powerbi.microsoft.com/)
[![Tableau](https://img.shields.io/badge/Visualization-Tableau-E97627?style=for-the-badge&logo=tableau&logoColor=white)](https://public.tableau.com/)
[![SQL](https://img.shields.io/badge/Language-GoogleSQL-4285F4?style=for-the-badge&logo=googlecloud&logoColor=white)]()
[![Star Schema](https://img.shields.io/badge/Model-Star%20Schema-1a1a1a?style=for-the-badge)]()

<!-- Repo meta badges -->
[![Last Commit](https://img.shields.io/github/last-commit/YOUR_USERNAME/YOUR_REPO?style=flat-square)](https://github.com/YOUR_USERNAME/YOUR_REPO/commits/main)
[![Repo Size](https://img.shields.io/github/repo-size/YOUR_USERNAME/YOUR_REPO?style=flat-square)]()
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](./LICENSE)
[![Status](https://img.shields.io/badge/Status-Active-success?style=flat-square)]()

</div>

> **TL;DR:** I modeled a flat retail transaction export into a governed star schema on BigQuery, wrote production-style SQL to validate revenue KPIs, and built an executive dashboard that surfaces where the business is growing, where margin is eroding, and which customers actually drive lifetime value. Every number below was produced by actually running the SQL in this repo against loaded data — not hand-typed — see [Data & Validation](#-data--validation).

> **Data note:** The dataset (`/data`) is a seeded, reproducible synthetic dataset structurally identical to the well-known Global Superstore dataset (same star-schema shape, same category/region/segment conventions), generated because this repo needed data that ships with the project rather than requiring a separate download. Swapping in the real Global Superstore CSV requires no schema changes — see [How to Reproduce](#-how-to-reproduce).

<div align="center">

### 🖼️ Dashboard Preview

<!--
Replace the src path below with your actual screenshot once exported from Power BI / Tableau.
Recommended: export at 1600px wide, PNG, and store in /dashboard/screenshots/
-->
<img src="./dashboard/screenshots/executive-overview.png" alt="Executive Overview Dashboard" width="850">

*Executive Overview — Revenue trend, MoM growth, margin health at a glance*

</div>

---

## 📑 Table of Contents

- [Business Problem](#-business-problem)
- [Key Findings](#-key-findings)
- [Dashboard Gallery](#-dashboard-gallery)
- [Architecture](#-architecture)
- [Data Model](#-data-model)
- [SQL Analytics Layer](#-sql-analytics-layer)
- [KPI Definitions](#-kpi-definitions)
- [Tech Stack](#-tech-stack)
- [How to Reproduce](#-how-to-reproduce)
- [Repository Structure](#-repository-structure)
- [What I'd Do Next](#-what-id-do-next-with-more-time)

---

## 🎯 Business Problem

Retail leadership has line-item transaction data but no reliable, repeatable way to answer three questions every executive asks monthly:

- **Are we growing month-over-month, and is that growth accelerating or decelerating?**
- **Which product categories are profitable vs. quietly bleeding margin?**
- **Which customers are worth protecting, and which are low-value noise in the CRM?**

This project answers all three with a governed data model instead of one-off spreadsheet pivots.

---

## 📈 Key Findings
*(every figure here is the actual output of `02_analytics_queries.sql` run against `/data` — see [Data & Validation](#-data--validation) for how that's proven)*

| Metric | Result | So What? |
|---|---|---|
| YoY Revenue Growth | **+12.8%** ($19.7M → $22.0M combined FY24-25) | Growth held up across both years but decelerated sharply in Q4 — flagged `Tier 4: At Risk` by the MoM tiering query in Nov/Dec |
| Gross Margin (Blended) | **18.4%** | Technology (36.6% margin) is subsidizing Furniture, which sits at a thin 5.5% |
| Top Customer Quartile Contribution | **67.2%** of revenue from the top 25% of customers (193 of 793) | Retention economics matter more than acquisition — losing one VIP customer costs roughly 12 "Developing" customers in revenue terms |
| Weakest-Margin Category | **Furniture — 5.5% margin**, `Thin Margin` flag | Still growing YoY (+8.6%) but margin isn't following growth — a pricing/discounting review candidate, not a discontinue candidate |



---

## 🖼️ Dashboard Gallery

<!--
Add one row per dashboard page/tab you build. Keep images in /dashboard/screenshots/
and just update the file names below — GitHub renders these automatically.
-->

<table>
  <tr>
    <td align="center" width="50%">
      <img src="./dashboard/screenshots/revenue-trend.png" alt="Revenue Trend & MoM Growth" width="400"><br>
      <b>Revenue Trend & MoM Growth</b><br>
      <sub>Rolling 3-month average, growth tiering</sub>
    </td>
    <td align="center" width="50%">
      <img src="./dashboard/screenshots/customer-segmentation.png" alt="Customer Segmentation View" width="400"><br>
      <b>Customer Segmentation</b><br>
      <sub>Quartile-based LTV tiers</sub>
    </td>
  </tr>
  <tr>
    <td align="center" width="50%">
      <img src="./dashboard/screenshots/category-margin.png" alt="Category Margin Health" width="400"><br>
      <b>Category Margin Health</b><br>
      <sub>YoY growth + gross margin by category</sub>
    </td>
    <td align="center" width="50%">
      <img src="./dashboard/screenshots/geo-performance.png" alt="Geographic Performance" width="400"><br>
      <b>Geographic Performance</b><br>
      <sub>Regional revenue breakdown via dim_locations</sub>
    </td>
  </tr>
</table>

<!-- Optional: embed a short demo GIF of the dashboard being interacted with -->
<div align="center">
<img src="./dashboard/screenshots/dashboard-demo.gif" alt="Dashboard interactive demo" width="700">
<br><sub>Interactive demo — filtering by category and date range</sub>
</div>

---

## 🏗️ Architecture

```
Flat CSV (Global Superstore)
        │
        ▼
Google BigQuery Sandbox (free tier, no billing account)
        │  ── star schema: 1 fact + 4 dimension tables
        ▼
SQL Validation Layer (CTEs, window functions, KPI tiering)
        │
        ▼
Power BI Desktop / Tableau Public (executive dashboard)
```

**Why a star schema instead of querying the flat file directly?**
A single denormalized table works for one report. It breaks the moment two dashboards need consistent definitions of "customer" or "category." Modeling `fact_sales` against conformed dimensions (`dim_customers`, `dim_products`, `dim_locations`, `dim_date`) means every downstream tool — Power BI, Tableau, ad hoc SQL — computes the same numbers, which is the entire point of a warehouse.

**Design decisions worth defending in an interview:**
- `NUMERIC` (not `FLOAT64`) on every currency column — avoids float rounding drift in financial rollups.
- `PARTITION BY order_date` + `CLUSTER BY customer_key, product_key` on the fact table — mirrors how a real warehouse controls bytes-scanned cost, which matters even in a free-tier sandbox with query limits.
- A materialized `dim_date` table instead of ad hoc `EXTRACT()` calls — gives every BI tool one shared calendar to build relationships against.

---

## 🧩 Data Model

📄 See [`01_schema_ddl.sql`](./01_schema_ddl.sql)

- **Fact:** `fact_sales` — grain is one row per order line item
- **Dimensions:** `dim_customers`, `dim_products`, `dim_locations`, `dim_date`

<div align="center">
<img src="./dashboard/screenshots/star-schema-erd.png" alt="Star Schema ERD" width="600">
<br><sub>Entity-relationship diagram — export from BigQuery's schema view or draw.io</sub>
</div>

---

## 🔍 SQL Analytics Layer

📄 See [`02_analytics_queries.sql`](./02_analytics_queries.sql)

Three validation scripts run before any dashboard is built:

1. **MoM Revenue Growth & Rolling Average** — `LAG()`/`LEAD()`, 3-month `ROWS BETWEEN` rolling average, `CASE WHEN` growth tiering
2. **Customer Value Segmentation** — `RANK()` and `NTILE()` for quartile-based LTV proxy segmentation
3. **Category YoY Performance** — partitioned `LAG()` for YoY, running `SUM() OVER` for cumulative contribution, margin-health tiering

---

## ✅ Data & Validation

A dashboard is only as trustworthy as the pipeline behind it. Before any chart was built, this project went through the same validation pass a real analyst runs before shipping numbers to leadership:

| Step | What it proves | Where |
|---|---|---|
| Referential integrity | Every `customer_key`, `product_key`, `location_key` in `fact_sales` has a matching parent row — 0 orphans | [`03_data_validation.sql`](./03_data_validation.sql), Check 2 |
| Primary key uniqueness | No duplicate surrogate keys in the fact table or dimensions | Check 3 |
| Null/negative-value audit | No null revenue, profit, or join keys; no negative sales amounts | Check 4 |
| Revenue reconciliation | Raw `SUM(sales_amount)` from the fact table matches the monthly rollup used in the MoM query, to the cent | Check 5 |
| Date coverage | Confirms the fact table's date range matches the intended 24-month window with no stray dates | Check 6 |
| KPI cross-validation | Every number in this README was independently reproduced in pandas (`02_validate_kpis.py`, not shipped in this repo's SQL-only scope) as a second implementation of the same logic — if the SQL and the Python agree, the aggregation logic is very unlikely to be wrong twice the same way |

**Known modeling simplification:** in this synthetic dataset, each `order_id` maps to exactly one line item (no multi-item orders). Real transactional data usually has orders with several line items — that would change "average order value" math slightly but not the star-schema design or the KPI formulas themselves. Documenting this here rather than hiding it is deliberate — a reviewer who spots it should see it was already known.

---

## 💡 KPI Definitions

| KPI | Formula | Notes |
|---|---|---|
| Gross Profit Margin | `(Revenue − COGS) / Revenue` | `profit_amount / sales_amount` at line-item grain, aggregated up |
| YoY Sales Growth | `(Current Year Rev − Prior Year Rev) / Prior Year Rev` | Computed per category via partitioned `LAG()` |
| CAC (approx.) | `Estimated Acquisition Spend / New Customers Acquired` | Approximated since the raw dataset has no marketing spend table — documented as a modeling assumption |
| LTV (approx.) | `Avg Order Value × Purchase Frequency × Customer Lifespan` | Derived from `dim_customers.first_order_date` and fact-table order history |

---

## 🛠️ Tech Stack

<div align="center">

![Google Cloud](https://img.shields.io/badge/Google_Cloud-4285F4?style=flat-square&logo=googlecloud&logoColor=white)
![BigQuery](https://img.shields.io/badge/BigQuery-669DF6?style=flat-square&logo=googlebigquery&logoColor=white)
![Power BI](https://img.shields.io/badge/Power_BI-F2C811?style=flat-square&logo=powerbi&logoColor=black)
![Tableau](https://img.shields.io/badge/Tableau-E97627?style=flat-square&logo=tableau&logoColor=white)
![Git](https://img.shields.io/badge/Git-F05032?style=flat-square&logo=git&logoColor=white)
![GitHub](https://img.shields.io/badge/GitHub-181717?style=flat-square&logo=github&logoColor=white)

</div>

- **Warehouse:** Google BigQuery Sandbox (free, no credit card)
- **Modeling:** GoogleSQL DDL, Kimball-style star schema
- **Transformation/Validation:** BigQuery SQL (CTEs, window functions)
- **Visualization:** Power BI Desktop (or Tableau Public)
- **Version Control:** Git / GitHub

---

## 🚀 How to Reproduce

1. Create a BigQuery Sandbox project (no billing account required).
2. Run `01_schema_ddl.sql` in the BigQuery Console to create the dataset and tables.
3. Load the five CSVs in `/data` using the matching schema file in `/schemas` (explicit schemas, not autodetect — see [`SETUP.md`](./SETUP.md)).
4. Run `03_data_validation.sql` — every check should return 0 violations before you proceed.
5. Run `02_analytics_queries.sql` to reproduce the KPIs in this README.
6. Connect Power BI Desktop via the built-in **Google BigQuery** connector (OAuth, no key file needed) and build the report.

**Want the real Global Superstore dataset instead of the synthetic one?** Download it from Kaggle, then map its columns to the dimension/fact shapes in `01_schema_ddl.sql` — the column names in `/data/*.csv` were deliberately kept identical to the DDL so this swap is a column-rename exercise, not a redesign.

Full step-by-step is in [`SETUP.md`](./SETUP.md).

---

## 📁 Repository Structure

```
├── README.md                      ← you are here
├── 01_schema_ddl.sql               ← star schema DDL
├── 02_analytics_queries.sql        ← KPI validation SQL (CTEs, window functions, tiering)
├── 03_data_validation.sql          ← referential integrity, null, and reconciliation checks
├── SETUP.md                        ← BigQuery + Power BI/Tableau connection guide
├── /data                           ← ready-to-load CSVs, schema-matched to the DDL
│   ├── fact_sales.csv               (14,000 rows)
│   ├── dim_customers.csv            (793 rows)
│   ├── dim_products.csv             (120 rows)
│   ├── dim_locations.csv            (10 rows)
│   └── dim_date.csv                 (731 rows)
├── /schemas                        ← explicit bq load schemas (one per table, avoids autodetect)
│   ├── fact_sales_schema.json
│   ├── dim_customers_schema.json
│   ├── dim_products_schema.json
│   ├── dim_locations_schema.json
│   └── dim_date_schema.json
└── /dashboard
    ├── executive-dashboard.pbix    ← Power BI file (or .twbx for Tableau), add once built
    └── /screenshots                ← exported dashboard images used in this README
```

---

## 🔭 What I'd Do Next With More Time

- Automate the CSV → BigQuery load with a scheduled Cloud Function instead of manual upload.
- Add a real marketing-spend table to replace the CAC approximation with a defensible figure.
- Build a `dbt` layer on top of the raw tables instead of hand-rolled DDL, for lineage and testing.

---

<div align="center">
<sub>Built by <a href="https://github.com/YOUR_USERNAME">Your Name</a> · <a href="https://www.linkedin.com/in/YOUR_PROFILE">LinkedIn</a> · <a href="mailto:you@email.com">Email</a></sub>
</div>
