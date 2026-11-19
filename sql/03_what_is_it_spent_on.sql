-- =============================================================
-- Chicago Budget Variance 2025
-- Step 3: "What is the money spent on?"
-- Groups ~180 Corporate Fund line items into 9 expense categories.
-- Uses the budget_2024 and budget_2025 tables from script 01.
-- =============================================================

-- -------------------------------------------------------------
-- 1. MAPPING: one row per line item -> expense category
-- CASE checks the rules top to bottom and uses the FIRST match,
-- so the specific rules (overtime, pensions, health care)
-- come before the general rule (other personnel).
-- Account code ranges follow the City's budget structure:
--   0000-0099 personnel, 0100-0299 contractual services & travel,
--   0300-0499 commodities & equipment, 09xx specific items,
--   92xx / 9000 programs, 998x pensions.
-- -------------------------------------------------------------
CREATE OR REPLACE VIEW budget_categorized AS
SELECT
    year,
    fund_name,
    dept_name,
    account_code,
    account_name,
    amount,
    CASE
        WHEN amount < 0                                         THEN 'Offsets & federal funding'
        WHEN account_name ILIKE '%pension%'                     THEN 'Pensions'
        WHEN account_name ILIKE '%overtime%'                    THEN 'Overtime'
        -- a city service, not an employee benefit (would otherwise match '%medical%')
        WHEN account_name ILIKE '%emergency medical transportation%' THEN 'City programs'
        WHEN account_name ILIKE '%hospital%'
          OR account_name ILIKE '%medical%'
          OR account_name ILIKE '%HMO%'
          OR account_name ILIKE '%dental%'
          OR account_name ILIKE '%vision%'
          OR account_name ILIKE '%medicare%'
          OR account_name ILIKE '%workers'' compensation%'
          OR account_name ILIKE '%life insurance%'
          OR account_name ILIKE '%unemployment%'                 THEN 'Health care & benefits'
        WHEN account_name ILIKE '%bonds%'
          OR account_name ILIKE '%judgments%'                    THEN 'Debt & legal judgments'
        WHEN account_code <  '0100'                              THEN 'Salaries & other pay'
        WHEN account_code <  '0300'                              THEN 'Contracts & services'
        WHEN account_code <  '0500'                              THEN 'Supplies, fuel & equipment'
        WHEN account_code >= '9000' AND account_code < '9900'    THEN 'City programs'
        ELSE                                                          'Other'
    END AS category
FROM (
    SELECT 2024 AS year, * FROM budget_2024
    UNION ALL
    SELECT 2025 AS year, * FROM budget_2025
);


-- -------------------------------------------------------------
-- 2. CHECK: nothing lost. Category totals must add up to the
-- Corporate Fund total ($5,788.0M for 2025).
-- -------------------------------------------------------------
SELECT year, ROUND(SUM(amount) / 1e6, 1) AS corporate_fund_musd
FROM budget_categorized
WHERE fund_name = 'Corporate Fund'
GROUP BY year
ORDER BY year;


-- -------------------------------------------------------------
-- 3. QUESTION 3: Corporate Fund by expense category,
-- 2024 vs 2025, with share of 2025 total.
-- -------------------------------------------------------------
SELECT
    category,
    ROUND(SUM(CASE WHEN year = 2024 THEN amount END) / 1e6, 1)      AS budget_2024_musd,
    ROUND(SUM(CASE WHEN year = 2025 THEN amount END) / 1e6, 1)      AS budget_2025_musd,
    ROUND((SUM(CASE WHEN year = 2025 THEN amount ELSE 0 END)
         - SUM(CASE WHEN year = 2024 THEN amount ELSE 0 END)) / 1e6, 1) AS change_musd,
    ROUND(100 * SUM(CASE WHEN year = 2025 THEN amount END)
              / SUM(SUM(CASE WHEN year = 2025 THEN amount END)) OVER (), 1) AS pct_of_2025
FROM budget_categorized
WHERE fund_name = 'Corporate Fund'
GROUP BY category
ORDER BY budget_2025_musd DESC;


-- -------------------------------------------------------------
-- 4. REVIEW: the biggest line items in 'Other', to check
-- nothing important landed in the wrong bucket.
-- -------------------------------------------------------------
SELECT account_code, account_name, ROUND(SUM(amount) / 1e6, 1) AS budget_2025_musd
FROM budget_categorized
WHERE fund_name = 'Corporate Fund' AND year = 2025 AND category = 'Other'
GROUP BY account_code, account_name
ORDER BY budget_2025_musd DESC
LIMIT 15;
