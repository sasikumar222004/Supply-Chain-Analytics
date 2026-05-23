-- ============================================================
--   SUPPLY CHAIN ANALYTICS — SQL ANALYSIS SCRIPT
--   Project : End-to-End Supply Chain Performance Dashboard
--   Author  : Sasikumar 2004 | GitHub: https://github.com/sasikumar2004
--   Database: SQL Server (T-SQL)
--   Dataset : 8,523 supply chain transactions
--   Updated : 2026
-- ============================================================
-- Run schema first: docs/schema.sql
-- Then BULK INSERT data/supply_chain_data.csv
-- ============================================================

USE SupplyChainDB;
GO

-- ============================================================
-- SECTION 0: INITIAL EXPLORATION
-- ============================================================

-- 0A. Preview top 20 rows (never SELECT * in production)
SELECT TOP 20
    id,
    product_category,
    product_identifier,
    product_type,
    warehouse_setup_year,
    warehouse_identifier,
    hub_location_tier,
    warehouse_size,
    warehouse_type,
    product_visibility,
    product_weight,
    sales,
    rating
FROM dbo.supply_chain
ORDER BY id;

-- 0B. Row count
SELECT COUNT(*) AS Total_Records FROM dbo.supply_chain;  -- Expected: 8,523

-- 0C. Column metadata
SELECT
    COLUMN_NAME,
    DATA_TYPE,
    IS_NULLABLE,
    CHARACTER_MAXIMUM_LENGTH
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'supply_chain'
ORDER BY ORDINAL_POSITION;


-- ============================================================
-- SECTION 1: DATA QUALITY CHECKS
-- ============================================================

-- 1A. Null counts per column
SELECT
    'product_weight'   AS Column_Name,
    SUM(CASE WHEN product_weight IS NULL THEN 1 ELSE 0 END) AS Null_Count,
    CAST(SUM(CASE WHEN product_weight IS NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2)) AS Null_Pct
FROM dbo.supply_chain
UNION ALL
SELECT
    'warehouse_size',
    SUM(CASE WHEN warehouse_size IS NULL THEN 1 ELSE 0 END),
    CAST(SUM(CASE WHEN warehouse_size IS NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2))
FROM dbo.supply_chain;

-- 1B. Check distinct product_category values (look for inconsistent casing)
SELECT DISTINCT product_category, COUNT(*) AS Record_Count
FROM dbo.supply_chain
GROUP BY product_category
ORDER BY Record_Count DESC;

-- 1C. Standardize product_category casing
UPDATE dbo.supply_chain
SET product_category = CASE
    WHEN product_category IN ('low fat', 'LF', 'Low fat', 'LOW FAT') THEN 'Low Fat'
    WHEN product_category IN ('reg', 'regular', 'REGULAR', 'REG')    THEN 'Regular'
    ELSE product_category
END
WHERE product_category NOT IN ('Low Fat', 'Regular');

-- Assertion: verify only 2 distinct values remain
SELECT COUNT(DISTINCT product_category) AS Distinct_Category_Count  -- Must be 2
FROM dbo.supply_chain;

-- 1D. Zero visibility anomalies
SELECT
    COUNT(*)                                                          AS Zero_Visibility_Count,
    CAST(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM dbo.supply_chain) AS DECIMAL(5,2)) AS Pct_Of_Total
FROM dbo.supply_chain
WHERE product_visibility = 0;

-- 1E. Duplicate SKU + Warehouse combinations
SELECT
    product_identifier,
    warehouse_identifier,
    COUNT(*) AS Occurrences
FROM dbo.supply_chain
GROUP BY product_identifier, warehouse_identifier
HAVING COUNT(*) > 1
ORDER BY Occurrences DESC;

-- 1F. Impute missing warehouse_size with 'Medium' (most common)
UPDATE dbo.supply_chain
SET warehouse_size = 'Medium'
WHERE warehouse_size IS NULL;

-- Assertion: no nulls remain in warehouse_size
SELECT SUM(CASE WHEN warehouse_size IS NULL THEN 1 ELSE 0 END) AS Remaining_Nulls  -- Must be 0
FROM dbo.supply_chain;

-- 1G. Revenue sanity check — flag outliers
SELECT
    MIN(sales)  AS Min_Revenue,
    MAX(sales)  AS Max_Revenue,
    AVG(sales)  AS Avg_Revenue,
    STDEV(sales) AS StdDev_Revenue,
    AVG(sales) + 3 * STDEV(sales) AS Upper_Outlier_Threshold
FROM dbo.supply_chain;


-- ============================================================
-- SECTION 2: OVERALL KPIs
-- ============================================================

SELECT
    CONCAT('₹ ', FORMAT(SUM(sales) / 1000000.0, 'N2'), ' M')        AS Total_Revenue,
    FORMAT(AVG(sales), 'N0')                                          AS Avg_Transaction_INR,
    FORMAT(COUNT(*), 'N0')                                            AS Total_Shipments,
    FORMAT(ROUND(AVG(rating), 2), 'N2')                               AS Avg_Satisfaction_Score,
    FORMAT(COUNT(DISTINCT warehouse_identifier), 'N0')                AS Total_Warehouses,
    FORMAT(COUNT(DISTINCT product_identifier), 'N0')                  AS Unique_SKUs,
    FORMAT(ROUND(SUM(sales) / NULLIF(COUNT(DISTINCT warehouse_identifier), 0), 0), 'N0')
                                                                      AS Avg_Revenue_Per_Warehouse
FROM dbo.supply_chain;


-- ============================================================
-- SECTION 3: PRODUCT-LEVEL ANALYSIS
-- ============================================================

-- 3A. Revenue by Product Category
SELECT
    product_category                                                            AS Category,
    CONCAT('₹ ', FORMAT(SUM(sales) / 1000000.0, 'N2'), ' M')                  AS Total_Revenue,
    FORMAT(ROUND(AVG(sales), 0), 'N0')                                         AS Avg_Transaction_INR,
    FORMAT(COUNT(*), 'N0')                                                     AS Total_Shipments,
    CAST(SUM(sales) * 100.0 / SUM(SUM(sales)) OVER () AS DECIMAL(5,2))        AS Revenue_Share_Pct,
    ROUND(AVG(rating), 2)                                                      AS Avg_Rating
FROM dbo.supply_chain
GROUP BY product_category
ORDER BY SUM(sales) DESC;

-- 3B. Revenue by Product Type — ranked
SELECT
    ROW_NUMBER() OVER (ORDER BY SUM(sales) DESC)                               AS Rank,
    product_type                                                               AS Product_Type,
    FORMAT(ROUND(SUM(sales) / 1000.0, 2), 'N2')                               AS Total_Revenue_K,
    FORMAT(ROUND(AVG(sales), 0), 'N0')                                        AS Avg_Revenue_INR,
    FORMAT(COUNT(*), 'N0')                                                    AS Items_Shipped,
    CAST(SUM(sales) * 100.0 / SUM(SUM(sales)) OVER () AS DECIMAL(5,2))       AS Revenue_Share_Pct,
    ROUND(AVG(rating), 2)                                                     AS Avg_Rating
FROM dbo.supply_chain
GROUP BY product_type
ORDER BY SUM(sales) DESC;

-- 3C. Top 10 revenue-generating SKUs
SELECT TOP 10
    product_identifier                    AS SKU,
    product_type                          AS Product_Type,
    product_category                      AS Category,
    COUNT(*)                              AS Shipment_Count,
    FORMAT(ROUND(SUM(sales), 0), 'N0')   AS Total_Revenue,
    FORMAT(ROUND(AVG(sales), 0), 'N0')   AS Avg_Revenue,
    ROUND(AVG(product_visibility), 4)    AS Avg_Visibility,
    ROUND(AVG(rating), 2)                AS Avg_Rating
FROM dbo.supply_chain
GROUP BY product_identifier, product_type, product_category
ORDER BY SUM(sales) DESC;

-- 3D. Visibility bucket analysis
SELECT
    CASE
        WHEN product_visibility = 0     THEN '0. Zero Visibility'
        WHEN product_visibility < 0.03  THEN '1. Very Low (0–0.03)'
        WHEN product_visibility < 0.06  THEN '2. Low (0.03–0.06)'
        WHEN product_visibility < 0.10  THEN '3. Medium (0.06–0.10)'
        WHEN product_visibility < 0.15  THEN '4. High (0.10–0.15)'
        ELSE                                 '5. Very High (0.15+)'
    END                               AS Visibility_Bucket,
    COUNT(*)                          AS Item_Count,
    ROUND(AVG(sales), 0)             AS Avg_Revenue,
    ROUND(SUM(sales), 0)             AS Total_Revenue,
    ROUND(AVG(rating), 2)            AS Avg_Rating
FROM dbo.supply_chain
GROUP BY
    CASE
        WHEN product_visibility = 0     THEN '0. Zero Visibility'
        WHEN product_visibility < 0.03  THEN '1. Very Low (0–0.03)'
        WHEN product_visibility < 0.06  THEN '2. Low (0.03–0.06)'
        WHEN product_visibility < 0.10  THEN '3. Medium (0.06–0.10)'
        WHEN product_visibility < 0.15  THEN '4. High (0.10–0.15)'
        ELSE                                 '5. Very High (0.15+)'
    END
ORDER BY Visibility_Bucket;


-- ============================================================
-- SECTION 4: WAREHOUSE-LEVEL ANALYSIS
-- ============================================================

-- 4A. KPIs by Warehouse Type
SELECT
    warehouse_type                                                             AS Warehouse_Type,
    FORMAT(ROUND(SUM(sales) / 1000.0, 2), 'N2')                              AS Total_Revenue_K,
    FORMAT(ROUND(AVG(sales), 0), 'N0')                                       AS Avg_Transaction_INR,
    FORMAT(COUNT(*), 'N0')                                                   AS Total_Shipments,
    CAST(SUM(sales) * 100.0 / SUM(SUM(sales)) OVER () AS DECIMAL(5,2))      AS Revenue_Share_Pct,
    ROUND(AVG(rating), 2)                                                    AS Avg_Satisfaction_Score
FROM dbo.supply_chain
GROUP BY warehouse_type
ORDER BY SUM(sales) DESC;

-- 4B. Revenue share by warehouse size
SELECT
    warehouse_size                                                             AS Warehouse_Size,
    COUNT(DISTINCT warehouse_identifier)                                      AS Warehouse_Count,
    FORMAT(CAST(SUM(sales) AS DECIMAL(12,2)), 'N2')                          AS Total_Revenue,
    CAST(SUM(sales) * 100.0 / SUM(SUM(sales)) OVER () AS DECIMAL(5,2))      AS Revenue_Pct,
    FORMAT(ROUND(AVG(sales), 0), 'N0')                                       AS Avg_Transaction
FROM dbo.supply_chain
GROUP BY warehouse_size
ORDER BY SUM(sales) DESC;

-- 4C. Warehouse establishment year trend
SELECT
    warehouse_setup_year                                                      AS Setup_Year,
    COUNT(DISTINCT warehouse_identifier)                                      AS Warehouse_Count,
    FORMAT(COUNT(*), 'N0')                                                   AS Total_Shipments,
    FORMAT(ROUND(SUM(sales), 0), 'N0')                                       AS Total_Revenue,
    FORMAT(ROUND(AVG(sales), 0), 'N0')                                       AS Avg_Revenue
FROM dbo.supply_chain
GROUP BY warehouse_setup_year
ORDER BY warehouse_setup_year;

-- 4D. Individual warehouse performance ranking
SELECT
    ROW_NUMBER() OVER (ORDER BY SUM(sales) DESC)                             AS Rank,
    warehouse_identifier                                                     AS Warehouse_ID,
    warehouse_type                                                           AS Type,
    warehouse_size                                                           AS Size,
    hub_location_tier                                                        AS Hub_Tier,
    warehouse_setup_year                                                     AS Est_Year,
    FORMAT(COUNT(*), 'N0')                                                  AS Total_Shipments,
    FORMAT(ROUND(SUM(sales), 0), 'N0')                                      AS Total_Revenue,
    FORMAT(ROUND(AVG(sales), 0), 'N0')                                      AS Avg_Revenue,
    ROUND(AVG(rating), 2)                                                   AS Avg_Rating
FROM dbo.supply_chain
GROUP BY warehouse_identifier, warehouse_type, warehouse_size,
         hub_location_tier, warehouse_setup_year
ORDER BY SUM(sales) DESC;


-- ============================================================
-- SECTION 5: GEOGRAPHIC / HUB TIER ANALYSIS
-- ============================================================

-- 5A. Revenue by Hub Location Tier
SELECT
    hub_location_tier                                                         AS Distribution_Zone,
    COUNT(DISTINCT warehouse_identifier)                                     AS Warehouse_Count,
    FORMAT(COUNT(*), 'N0')                                                  AS Total_Shipments,
    FORMAT(ROUND(SUM(sales), 0), 'N0')                                      AS Total_Revenue,
    CAST(SUM(sales) * 100.0 / SUM(SUM(sales)) OVER () AS DECIMAL(5,2))     AS Revenue_Share_Pct,
    FORMAT(ROUND(AVG(sales), 0), 'N0')                                      AS Avg_Transaction
FROM dbo.supply_chain
GROUP BY hub_location_tier
ORDER BY SUM(sales) DESC;

-- 5B. Hub Tier × Product Category cross-tab
SELECT
    hub_location_tier                                                        AS Hub_Tier,
    product_category                                                         AS Category,
    FORMAT(ROUND(SUM(sales) / 1000.0, 2), 'N2')                            AS Total_Revenue_K,
    FORMAT(ROUND(AVG(sales), 0), 'N0')                                     AS Avg_Revenue,
    FORMAT(COUNT(*), 'N0')                                                 AS Shipment_Count,
    ROUND(AVG(rating), 2)                                                  AS Avg_Rating
FROM dbo.supply_chain
GROUP BY hub_location_tier, product_category
ORDER BY SUM(sales) DESC;

-- 5C. PIVOT — Revenue by Hub Tier and Product Category
SELECT
    hub_location_tier,
    ISNULL([Low Fat], 0)                              AS Low_Fat_Revenue,
    ISNULL([Regular], 0)                              AS Regular_Revenue,
    ISNULL([Low Fat], 0) + ISNULL([Regular], 0)      AS Total_Revenue
FROM (
    SELECT
        hub_location_tier,
        product_category,
        CAST(SUM(sales) AS DECIMAL(12,2)) AS Revenue
    FROM dbo.supply_chain
    GROUP BY hub_location_tier, product_category
) AS Src
PIVOT (
    SUM(Revenue)
    FOR product_category IN ([Low Fat], [Regular])
) AS PivotTable
ORDER BY Total_Revenue DESC;

-- 5D. Year × Hub Tier heatmap data
SELECT
    warehouse_setup_year     AS Setup_Year,
    hub_location_tier        AS Hub_Tier,
    COUNT(*)                 AS Shipments,
    ROUND(SUM(sales), 0)    AS Total_Revenue
FROM dbo.supply_chain
GROUP BY warehouse_setup_year, hub_location_tier
ORDER BY warehouse_setup_year, hub_location_tier;


-- ============================================================
-- SECTION 6: ADVANCED WINDOW FUNCTION ANALYSIS
-- ============================================================

-- 6A. Running total revenue by Product Type
SELECT
    product_type,
    ROUND(SUM(sales), 0)                                                        AS Type_Revenue,
    ROUND(SUM(SUM(sales)) OVER (ORDER BY SUM(sales) DESC
                                ROWS UNBOUNDED PRECEDING), 0)                   AS Running_Total,
    CAST(SUM(SUM(sales)) OVER (ORDER BY SUM(sales) DESC
                                ROWS UNBOUNDED PRECEDING) * 100.0
         / SUM(SUM(sales)) OVER () AS DECIMAL(5,2))                            AS Cumulative_Pct
FROM dbo.supply_chain
GROUP BY product_type
ORDER BY Type_Revenue DESC;

-- 6B. Revenue rank within each Hub Tier by Product Type
SELECT
    hub_location_tier,
    product_type,
    ROUND(SUM(sales), 0)                                                        AS Total_Revenue,
    RANK() OVER (PARTITION BY hub_location_tier ORDER BY SUM(sales) DESC)      AS Rank_In_Tier
FROM dbo.supply_chain
GROUP BY hub_location_tier, product_type
ORDER BY hub_location_tier, Rank_In_Tier;

-- 6C. Year-over-Year warehouse revenue growth (LAG)
WITH YearlyRevenue AS (
    SELECT
        warehouse_identifier,
        warehouse_setup_year,
        ROUND(SUM(sales), 0) AS Revenue
    FROM dbo.supply_chain
    GROUP BY warehouse_identifier, warehouse_setup_year
)
SELECT
    warehouse_identifier,
    warehouse_setup_year,
    FORMAT(Revenue, 'N0')                                                   AS Revenue,
    FORMAT(LAG(Revenue) OVER (PARTITION BY warehouse_identifier
                               ORDER BY warehouse_setup_year), 'N0')       AS Prev_Revenue,
    CAST(
        (Revenue - LAG(Revenue) OVER (PARTITION BY warehouse_identifier
                                       ORDER BY warehouse_setup_year))
        * 100.0
        / NULLIF(LAG(Revenue) OVER (PARTITION BY warehouse_identifier
                                     ORDER BY warehouse_setup_year), 0)
    AS DECIMAL(6,2))                                                        AS YoY_Growth_Pct
FROM YearlyRevenue
ORDER BY warehouse_identifier, warehouse_setup_year;

-- 6D. Revenue quartile + percentile ranking per SKU
SELECT
    product_identifier,
    product_type,
    ROUND(SUM(sales), 0)                                   AS Total_Revenue,
    NTILE(4)      OVER (ORDER BY SUM(sales))              AS Revenue_Quartile,
    CAST(PERCENT_RANK() OVER (ORDER BY SUM(sales)) * 100
         AS DECIMAL(5,1))                                  AS Percentile_Rank,
    CAST(CUME_DIST()    OVER (ORDER BY SUM(sales)) * 100
         AS DECIMAL(5,1))                                  AS Cumulative_Dist_Pct
FROM dbo.supply_chain
GROUP BY product_identifier, product_type
ORDER BY Total_Revenue DESC;

-- 6E. Moving average revenue (3-year window) by warehouse year
SELECT
    warehouse_setup_year,
    ROUND(SUM(sales), 0)                                                    AS Yearly_Revenue,
    ROUND(AVG(SUM(sales)) OVER (ORDER BY warehouse_setup_year
                                 ROWS BETWEEN 2 PRECEDING AND CURRENT ROW),
          0)                                                                AS Moving_Avg_3Yr
FROM dbo.supply_chain
GROUP BY warehouse_setup_year
ORDER BY warehouse_setup_year;

-- 6F. Warehouse performance tier (above/below average)
WITH WH_Stats AS (
    SELECT
        warehouse_identifier,
        warehouse_type,
        hub_location_tier,
        ROUND(AVG(sales), 2)   AS Avg_Revenue,
        COUNT(*)               AS Shipments,
        ROUND(AVG(rating), 2)  AS Avg_Rating
    FROM dbo.supply_chain
    GROUP BY warehouse_identifier, warehouse_type, hub_location_tier
),
Overall AS (
    SELECT ROUND(AVG(Avg_Revenue), 2) AS Global_Avg FROM WH_Stats
)
SELECT
    w.warehouse_identifier,
    w.warehouse_type,
    w.hub_location_tier,
    w.Avg_Revenue,
    o.Global_Avg,
    CASE
        WHEN w.Avg_Revenue >= o.Global_Avg * 1.15 THEN 'High Performer'
        WHEN w.Avg_Revenue >= o.Global_Avg        THEN 'Above Average'
        WHEN w.Avg_Revenue >= o.Global_Avg * 0.85 THEN 'Below Average'
        ELSE                                           'Under Performer'
    END AS Performance_Tier,
    w.Avg_Rating
FROM WH_Stats w
CROSS JOIN Overall o
ORDER BY w.Avg_Revenue DESC;

-- ============================================================
-- END OF SCRIPT
-- ============================================================
