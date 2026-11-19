-- =============================================================
-- Chicago Budget Variance 2025
-- Step 1: Load the budget files and answer
--         "Where does the money go?"
-- Engine: DuckDB (run in DBeaver)
-- =============================================================

-- -------------------------------------------------------------
-- 1. LOAD
-- Change the folder path below to where your CSV files are.
-- Example (Mac): '/Users/yourname/chicago-budget-vs-actual-2025/data/'
-- -------------------------------------------------------------
CREATE OR REPLACE TABLE budget_2025 AS
SELECT
    "FUND TYPE"                            AS fund_type,
    "FUND CODE"                            AS fund_code,
    "FUND DESCRIPTION"                     AS fund_name,
    "DEPARTMENT NUMBER"                    AS dept_number,
    "DEPARTMENT DESCRIPTION"               AS dept_name,
    "APPROPRIATION ACCOUNT"                AS account_code,
    "APPROPRIATION ACCOUNT DESCRIPTION"    AS account_name,
    "2025 ORDINANCE (AMOUNT $)"            AS amount
FROM read_csv('/path/to/chicago-budget-vs-actual-2025/data/budget_2025.csv', header = true, all_varchar = false);

CREATE OR REPLACE TABLE budget_2024 AS
SELECT
    "FUND TYPE"                            AS fund_type,
    "FUND CODE"                            AS fund_code,
    "FUND DESCRIPTION"                     AS fund_name,
    "DEPARTMENT NUMBER"                    AS dept_number,
    "DEPARTMENT DESCRIPTION"               AS dept_name,
    "APPROPRIATION ACCOUNT"                AS account_code,
    "APPROPRIATION ACCOUNT DESCRIPTION"    AS account_name,
    "2024 ORDINANCE (AMOUNT $)"            AS amount
FROM read_csv('/path/to/chicago-budget-vs-actual-2025/data/budget_2024.csv', header = true, all_varchar = false);


-- -------------------------------------------------------------
-- 2. CHECK: do the totals match the City's official numbers?
-- Expected 2025: all funds = $18,842M, Corporate Fund = $5,788M
-- -------------------------------------------------------------
SELECT
    ROUND(SUM(amount) / 1e6, 1)                                                AS all_funds_musd,
    ROUND(SUM(CASE WHEN fund_name = 'Corporate Fund' THEN amount END) / 1e6, 1) AS corporate_fund_musd,
    COUNT(*)                                                                   AS line_items
FROM budget_2025;


-- -------------------------------------------------------------
-- 3. QUESTION 1: Where does the money go?
-- Corporate Fund budget by department, with share of total
-- and running (cumulative) share.
-- -------------------------------------------------------------
WITH dept AS (
    SELECT
        dept_name,
        SUM(amount) AS budget
    FROM budget_2025
    WHERE fund_name = 'Corporate Fund'
    GROUP BY dept_name
)
SELECT
    dept_name,
    ROUND(budget / 1e6, 1)                                                     AS budget_musd,
    ROUND(100 * budget / SUM(budget) OVER (), 1)                               AS pct_of_total,
    ROUND(100 * SUM(budget) OVER (ORDER BY budget DESC) / SUM(budget) OVER (), 1) AS cumulative_pct
FROM dept
ORDER BY budget DESC;
