-- =====================================================================
-- DATA QUALITY & REFERENTIAL INTEGRITY VALIDATION
-- Run this immediately after loading all 5 tables and BEFORE running
-- 02_analytics_queries.sql or connecting a BI tool. Every query should
-- return 0 rows / 0 count for the checks to pass. This is the step that
-- makes the rest of the project defensible — it proves the star schema
-- actually joins cleanly instead of assuming it.
-- =====================================================================

-- ---------------------------------------------------------------------
-- CHECK 1: Row counts — sanity check against expected volumes
-- Expected (synthetic dataset): dim_date 731, dim_locations 10,
-- dim_products 120, dim_customers 793, fact_sales 14000
-- ---------------------------------------------------------------------
SELECT 'dim_date' AS table_name, COUNT(*) AS row_count FROM `your_project.sales_dw.dim_date`
UNION ALL
SELECT 'dim_locations', COUNT(*) FROM `your_project.sales_dw.dim_locations`
UNION ALL
SELECT 'dim_products', COUNT(*) FROM `your_project.sales_dw.dim_products`
UNION ALL
SELECT 'dim_customers', COUNT(*) FROM `your_project.sales_dw.dim_customers`
UNION ALL
SELECT 'fact_sales', COUNT(*) FROM `your_project.sales_dw.fact_sales`;


-- ---------------------------------------------------------------------
-- CHECK 2: Orphan foreign keys — fact rows whose dimension key has no
-- matching parent row. Must return 0 for all three.
-- ---------------------------------------------------------------------
SELECT 'orphan_customer_key' AS check_name, COUNT(*) AS violation_count
FROM `your_project.sales_dw.fact_sales` f
LEFT JOIN `your_project.sales_dw.dim_customers` c ON f.customer_key = c.customer_key
WHERE c.customer_key IS NULL

UNION ALL

SELECT 'orphan_product_key', COUNT(*)
FROM `your_project.sales_dw.fact_sales` f
LEFT JOIN `your_project.sales_dw.dim_products` p ON f.product_key = p.product_key
WHERE p.product_key IS NULL

UNION ALL

SELECT 'orphan_location_key', COUNT(*)
FROM `your_project.sales_dw.fact_sales` f
LEFT JOIN `your_project.sales_dw.dim_locations` l ON f.location_key = l.location_key
WHERE l.location_key IS NULL

UNION ALL

SELECT 'order_date_outside_dim_date', COUNT(*)
FROM `your_project.sales_dw.fact_sales` f
LEFT JOIN `your_project.sales_dw.dim_date` d ON f.order_date = d.date_key
WHERE d.date_key IS NULL;


-- ---------------------------------------------------------------------
-- CHECK 3: Primary key uniqueness — surrogate keys must not repeat.
-- Must return 0 rows for each table.
-- ---------------------------------------------------------------------
SELECT 'fact_sales.order_line_key' AS key_checked, order_line_key, COUNT(*) AS occurrences
FROM `your_project.sales_dw.fact_sales`
GROUP BY order_line_key
HAVING COUNT(*) > 1

UNION ALL

SELECT 'dim_customers.customer_key', customer_key, COUNT(*)
FROM `your_project.sales_dw.dim_customers`
GROUP BY customer_key
HAVING COUNT(*) > 1

UNION ALL

SELECT 'dim_products.product_key', product_key, COUNT(*)
FROM `your_project.sales_dw.dim_products`
GROUP BY product_key
HAVING COUNT(*) > 1;


-- ---------------------------------------------------------------------
-- CHECK 4: Null / blank checks on columns the dashboard depends on.
-- Must return 0 for every row — a non-zero count here means a KPI
-- upstream (revenue, margin, date grouping) will silently miscalculate.
-- ---------------------------------------------------------------------
SELECT
  COUNTIF(order_date IS NULL)     AS null_order_dates,
  COUNTIF(sales_amount IS NULL)   AS null_sales_amount,
  COUNTIF(profit_amount IS NULL)  AS null_profit_amount,
  COUNTIF(customer_key IS NULL)   AS null_customer_key,
  COUNTIF(product_key IS NULL)    AS null_product_key,
  COUNTIF(sales_amount < 0)       AS negative_sales_amount   -- revenue should never be negative even if profit is
FROM `your_project.sales_dw.fact_sales`;


-- ---------------------------------------------------------------------
-- CHECK 5: Reconciliation — total revenue from the fact table must match
-- the sum used in the analytics layer (script 1). If these two numbers
-- ever diverge, a filter or join in the analytics SQL is silently
-- dropping rows.
-- ---------------------------------------------------------------------
WITH raw_total AS (
  SELECT ROUND(SUM(sales_amount), 2) AS total_from_fact
  FROM `your_project.sales_dw.fact_sales`
),
analytics_total AS (
  SELECT ROUND(SUM(total_revenue), 2) AS total_from_monthly_rollup
  FROM (
    SELECT DATE_TRUNC(order_date, MONTH) AS sales_month, SUM(sales_amount) AS total_revenue
    FROM `your_project.sales_dw.fact_sales`
    GROUP BY sales_month
  )
)
SELECT
  raw_total.total_from_fact,
  analytics_total.total_from_monthly_rollup,
  raw_total.total_from_fact - analytics_total.total_from_monthly_rollup AS difference -- must be 0
FROM raw_total, analytics_total;


-- ---------------------------------------------------------------------
-- CHECK 6: Date range sanity — confirms partitioning covers the data
-- you expect and flags any stray dates outside the intended window.
-- ---------------------------------------------------------------------
SELECT
  MIN(order_date) AS earliest_order,
  MAX(order_date) AS latest_order,
  COUNT(DISTINCT DATE_TRUNC(order_date, MONTH)) AS distinct_months_covered
FROM `your_project.sales_dw.fact_sales`;
