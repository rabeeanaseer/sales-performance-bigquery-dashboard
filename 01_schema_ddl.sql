-- =====================================================================
-- SALES PERFORMANCE & EXECUTIVE DASHBOARD
-- Star Schema DDL — BigQuery Sandbox (GoogleSQL dialect)
-- Source dataset assumption: Global Superstore (flat CSV export)
-- Replace `your_project.sales_dw` with your actual Sandbox project/dataset
-- =====================================================================

-- 1. Create the dataset (run once, or do it via Console UI)
CREATE SCHEMA IF NOT EXISTS `your_project.sales_dw`
OPTIONS (
  location = 'US',
  description = 'Star schema warehouse for Sales Performance Dashboard'
);

-- ---------------------------------------------------------------------
-- DIM_DATE  (calendar/date dimension — standard BI best practice)
-- Pre-built so window function date logic in analytics layer is trivial
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE `your_project.sales_dw.dim_date` (
  date_key        DATE     NOT NULL,   -- surrogate + natural key (BigQuery DATE is efficient to join/partition on)
  day_of_week     STRING,
  day_name        STRING,
  day_of_month    INT64,
  month_number    INT64,
  month_name      STRING,
  quarter_number  INT64,
  year_number     INT64,
  is_weekend      BOOL,
  fiscal_year     INT64
)
PARTITION BY date_key
OPTIONS (description = 'Calendar dimension used to drive MoM/YoY window logic');

-- ---------------------------------------------------------------------
-- DIM_CUSTOMERS
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE `your_project.sales_dw.dim_customers` (
  customer_key      STRING   NOT NULL,   -- surrogate key, e.g. hashed customer_id
  customer_id       STRING,              -- natural/business key from source
  customer_name     STRING,
  segment           STRING,              -- Consumer / Corporate / Home Office
  first_order_date  DATE,                -- used later for CAC/LTV cohorting
  customer_since_days INT64
)
OPTIONS (description = 'Customer dimension — one row per unique customer');

-- ---------------------------------------------------------------------
-- DIM_PRODUCTS
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE `your_project.sales_dw.dim_products` (
  product_key     STRING   NOT NULL,   -- surrogate key
  product_id      STRING,
  product_name    STRING,
  category        STRING,              -- Furniture / Office Supplies / Technology
  sub_category    STRING,
  unit_cost       NUMERIC,             -- estimated/derived cost basis for margin calcs
  standard_price  NUMERIC
)
OPTIONS (description = 'Product dimension — one row per SKU');

-- ---------------------------------------------------------------------
-- DIM_LOCATIONS
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE `your_project.sales_dw.dim_locations` (
  location_key  STRING   NOT NULL,   -- surrogate key
  country       STRING,
  region        STRING,
  state         STRING,
  city          STRING,
  postal_code   STRING,
  market        STRING               -- e.g. US / APAC / EMEA if using Global Superstore's global cut
)
OPTIONS (description = 'Geography dimension — one row per unique ship-to location');

-- ---------------------------------------------------------------------
-- FACT_SALES  (grain: one row per order line item)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE `your_project.sales_dw.fact_sales` (
  order_line_key   STRING     NOT NULL,   -- surrogate key: order_id + row_id
  order_id         STRING,
  order_date       DATE       NOT NULL,
  ship_date        DATE,
  order_timestamp  TIMESTAMP,             -- for intraday/audit granularity if source has time
  customer_key     STRING     NOT NULL,
  product_key      STRING     NOT NULL,
  location_key     STRING     NOT NULL,
  ship_mode        STRING,
  quantity         INT64,
  sales_amount     NUMERIC,               -- gross revenue for the line
  discount_pct     NUMERIC,
  profit_amount    NUMERIC                -- pre-computed profit for reconciliation with margin KPI
)
PARTITION BY order_date                        -- prunes scan cost — critical in a storage/compute-capped Sandbox
CLUSTER BY customer_key, product_key           -- speeds up the joins used in the analytics scripts below
OPTIONS (description = 'Fact table — grain is one row per order line item');

-- ---------------------------------------------------------------------
-- Notes on design choices (for the README / interview talking points):
-- 1. NUMERIC (not FLOAT64) is used for all currency fields to avoid
--    floating point rounding drift in financial aggregations.
-- 2. PARTITION BY order_date + CLUSTER BY customer/product mirrors how
--    a real enterprise warehouse controls BigQuery bytes-scanned cost.
-- 3. Surrogate keys (STRING hash/concat) decouple the warehouse from
--    the source system's natural keys — standard Kimball practice.
-- 4. dim_date is materialized rather than derived ad hoc so every BI
--    tool (Power BI / Tableau) gets a consistent calendar table to
--    build relationships against.
-- =====================================================================
