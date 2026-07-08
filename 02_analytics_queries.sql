-- =====================================================================
-- SALES PERFORMANCE & EXECUTIVE DASHBOARD
-- Pre-Dashboard Validation Analytics — BigQuery Sandbox (GoogleSQL)
-- Three scripts an analyst runs to sanity-check KPIs before wiring up
-- Power BI / Tableau, demonstrating CTEs, window functions, CASE WHEN.
-- =====================================================================


-- =====================================================================
-- SCRIPT 1: MONTH-OVER-MONTH REVENUE GROWTH + 3-MONTH ROLLING AVERAGE
-- Demonstrates: CTE chaining, LAG(), SUM() OVER (rolling window), CASE WHEN
-- =====================================================================

WITH monthly_revenue AS (
  -- Step 1: collapse fact table to one row per calendar month
  SELECT
    DATE_TRUNC(f.order_date, MONTH) AS sales_month,
    SUM(f.sales_amount)             AS total_revenue,
    SUM(f.profit_amount)            AS total_profit,
    COUNT(DISTINCT f.order_id)      AS order_count
  FROM `your_project.sales_dw.fact_sales` f
  GROUP BY sales_month
),

revenue_with_lag AS (
  -- Step 2: bring the prior month's revenue alongside the current row
  SELECT
    sales_month,
    total_revenue,
    total_profit,
    order_count,
    LAG(total_revenue)  OVER (ORDER BY sales_month) AS prev_month_revenue,
    LEAD(total_revenue) OVER (ORDER BY sales_month) AS next_month_revenue,
    -- 3-month trailing rolling average, classic ROWS BETWEEN frame
    AVG(total_revenue) OVER (
      ORDER BY sales_month
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS rolling_3mo_avg_revenue
  FROM monthly_revenue
),

revenue_growth AS (
  -- Step 3: compute MoM % growth and flag direction
  SELECT
    sales_month,
    total_revenue,
    total_profit,
    order_count,
    prev_month_revenue,
    rolling_3mo_avg_revenue,
    SAFE_DIVIDE(total_revenue - prev_month_revenue, prev_month_revenue) AS mom_growth_pct,
    CASE
      WHEN prev_month_revenue IS NULL              THEN 'First Month On Record'
      WHEN total_revenue > prev_month_revenue       THEN 'Growth'
      WHEN total_revenue < prev_month_revenue       THEN 'Decline'
      ELSE 'Flat'
    END AS mom_trend_flag
  FROM revenue_with_lag
)

SELECT
  sales_month,
  ROUND(total_revenue, 2)          AS total_revenue,
  ROUND(rolling_3mo_avg_revenue,2) AS rolling_3mo_avg_revenue,
  ROUND(mom_growth_pct * 100, 2)   AS mom_growth_pct,
  mom_trend_flag,
  -- Performance tiering used directly on the executive dashboard
  CASE
    WHEN mom_growth_pct >= 0.10                         THEN 'Tier 1: High Growth'
    WHEN mom_growth_pct >= 0.00 AND mom_growth_pct < 0.10 THEN 'Tier 2: Stable Growth'
    WHEN mom_growth_pct < 0.00 AND mom_growth_pct >= -0.10 THEN 'Tier 3: Mild Decline'
    WHEN mom_growth_pct < -0.10                          THEN 'Tier 4: At Risk'
    ELSE 'Tier 5: Baseline (No Prior Data)'
  END AS growth_performance_tier
FROM revenue_growth
ORDER BY sales_month;


-- =====================================================================
-- SCRIPT 2: CUSTOMER VALUE SEGMENTATION (LTV proxy + performance tiers)
-- Demonstrates: CTE modularity, window functions for ranking/percentile,
-- CASE WHEN for RFM-style tiering
-- =====================================================================

WITH customer_orders AS (
  SELECT
    c.customer_key,
    c.customer_name,
    c.segment,
    f.order_id,
    f.order_date,
    f.sales_amount,
    f.profit_amount
  FROM `your_project.sales_dw.fact_sales` f
  JOIN `your_project.sales_dw.dim_customers` c
    ON f.customer_key = c.customer_key
),

customer_summary AS (
  -- Step 1: one row per customer, core lifetime metrics
  SELECT
    customer_key,
    customer_name,
    segment,
    COUNT(DISTINCT order_id)                 AS total_orders,
    SUM(sales_amount)                         AS lifetime_revenue,
    SUM(profit_amount)                        AS lifetime_profit,
    MIN(order_date)                           AS first_purchase_date,
    MAX(order_date)                           AS last_purchase_date,
    DATE_DIFF(MAX(order_date), MIN(order_date), DAY) AS customer_tenure_days
  FROM customer_orders
  GROUP BY customer_key, customer_name, segment
),

customer_ranked AS (
  -- Step 2: window functions rank each customer within their segment
  SELECT
    *,
    SAFE_DIVIDE(lifetime_revenue, NULLIF(total_orders, 0)) AS avg_order_value,
    RANK() OVER (PARTITION BY segment ORDER BY lifetime_revenue DESC) AS revenue_rank_in_segment,
    NTILE(4) OVER (ORDER BY lifetime_revenue DESC) AS revenue_quartile -- 1 = top 25%
  FROM customer_summary
)

SELECT
  customer_name,
  segment,
  total_orders,
  ROUND(lifetime_revenue, 2)  AS lifetime_revenue,
  ROUND(avg_order_value, 2)   AS avg_order_value,
  customer_tenure_days,
  revenue_rank_in_segment,
  revenue_quartile,
  CASE
    WHEN revenue_quartile = 1                         THEN 'VIP / Champion'
    WHEN revenue_quartile = 2                         THEN 'Loyal Customer'
    WHEN revenue_quartile = 3                         THEN 'Developing Customer'
    ELSE 'At-Risk / Low Engagement'
  END AS customer_value_tier
FROM customer_ranked
ORDER BY lifetime_revenue DESC;


-- =====================================================================
-- SCRIPT 3: PRODUCT/CATEGORY YoY PERFORMANCE + CUMULATIVE CONTRIBUTION
-- Demonstrates: CTEs, YoY via self-referencing window (LAG with PARTITION),
-- running totals (SUM OVER), CASE WHEN for margin health tiers
-- =====================================================================

WITH yearly_category_sales AS (
  SELECT
    p.category,
    EXTRACT(YEAR FROM f.order_date) AS sales_year,
    SUM(f.sales_amount)             AS category_revenue,
    SUM(f.profit_amount)            AS category_profit
  FROM `your_project.sales_dw.fact_sales` f
  JOIN `your_project.sales_dw.dim_products` p
    ON f.product_key = p.product_key
  GROUP BY p.category, sales_year
),

yoy_calc AS (
  SELECT
    category,
    sales_year,
    category_revenue,
    category_profit,
    SAFE_DIVIDE(category_profit, NULLIF(category_revenue, 0)) AS gross_margin_pct,
    -- YoY comparison: partition by category so we never compare across categories
    LAG(category_revenue) OVER (
      PARTITION BY category ORDER BY sales_year
    ) AS prior_year_revenue
  FROM yearly_category_sales
),

yoy_final AS (
  SELECT
    *,
    SAFE_DIVIDE(category_revenue - prior_year_revenue, prior_year_revenue) AS yoy_growth_pct,
    -- Running total of revenue across years per category (cumulative contribution)
    SUM(category_revenue) OVER (
      PARTITION BY category ORDER BY sales_year
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_revenue_to_date
  FROM yoy_calc
)

SELECT
  category,
  sales_year,
  ROUND(category_revenue, 2)        AS category_revenue,
  ROUND(gross_margin_pct * 100, 2)  AS gross_margin_pct,
  ROUND(yoy_growth_pct * 100, 2)    AS yoy_growth_pct,
  ROUND(cumulative_revenue_to_date, 2) AS cumulative_revenue_to_date,
  CASE
    WHEN gross_margin_pct >= 0.25 THEN 'Healthy Margin'
    WHEN gross_margin_pct >= 0.10 THEN 'Watch List'
    WHEN gross_margin_pct >= 0    THEN 'Thin Margin'
    ELSE 'Loss-Making'
  END AS margin_health_flag,
  CASE
    WHEN yoy_growth_pct IS NULL      THEN 'No Prior Year Data'
    WHEN yoy_growth_pct >= 0.15      THEN 'Accelerating'
    WHEN yoy_growth_pct >= 0        THEN 'Steady'
    ELSE 'Declining'
  END AS yoy_trend_flag
FROM yoy_final
ORDER BY category, sales_year;
