-- =============================================================
-- Chicago Budget Variance 2025
-- Step 5: "Why did they over/underspend?"
-- Drill from department totals down to the lines that drive them.
-- Uses actuals_2025 and budget_2025 from scripts 01 and 04.
-- Variance = budget - actual (negative = over budget).
-- =============================================================

-- -------------------------------------------------------------
-- 1. DRILL-DOWN: the lines behind the 3 biggest stories
-- (57 = Police, 59 = Fire, 99 = Finance General)
-- -------------------------------------------------------------
SELECT
    dept_name_acfr                                     AS department,
    approp_code,
    account_group,
    ROUND(final_budget / 1e6, 1)                       AS budget_musd,
    ROUND(actual / 1e6, 1)                             AS actual_musd,
    ROUND((final_budget - actual) / 1e6, 1)            AS variance_musd
FROM actuals_2025
WHERE dept_number IN (57, 59, 99)
  AND ABS(final_budget - actual) >= 1e6               -- only lines with a $1M+ gap
ORDER BY dept_number, ABS(final_budget - actual) DESC;


-- -------------------------------------------------------------
-- 2. DRIVERS: the whole General Fund variance grouped by cause,
-- across all departments. This turns 395 lines into a short
-- list a CFO can read.
-- -------------------------------------------------------------
CREATE OR REPLACE VIEW variance_by_driver AS
SELECT
    CASE
        WHEN account_code = '9646'                      THEN 'Federal funding credit not applied (Fire)'
        WHEN account_code = '9333'                      THEN 'Budgeted savings target'
        WHEN account_code IN ('0931', '0934')           THEN 'Lawsuits & judgments'
        WHEN account_code = '0912'                      THEN 'Debt payments'
        WHEN account_code = '0000' AND dept_number = 99 THEN 'Citywide personnel pool (wage adjustments, health care)'
        WHEN account_code = '0000'                      THEN 'Department payroll (incl. overtime)'
        WHEN account_code = '0100'                      THEN 'Contracts & services'
        ELSE                                                 'Everything else'
    END                                                 AS driver,
    dept_number,
    dept_name_acfr,
    final_budget,
    actual,
    final_budget - actual                               AS variance
FROM actuals_2025;

SELECT
    driver,
    ROUND(SUM(final_budget) / 1e6, 1)                   AS budget_musd,
    ROUND(SUM(actual) / 1e6, 1)                         AS actual_musd,
    ROUND(SUM(variance) / 1e6, 1)                       AS variance_musd
FROM variance_by_driver
GROUP BY driver
ORDER BY variance_musd;


-- -------------------------------------------------------------
-- 3. PAYROLL by department: who is over on payroll, who is under?
-- -------------------------------------------------------------
SELECT
    dept_name_acfr                                      AS department,
    ROUND(SUM(final_budget) / 1e6, 1)                   AS payroll_budget_musd,
    ROUND(SUM(actual) / 1e6, 1)                         AS payroll_actual_musd,
    ROUND(SUM(variance) / 1e6, 1)                       AS variance_musd
FROM variance_by_driver
WHERE driver = 'Department payroll (incl. overtime)'
GROUP BY dept_name_acfr
HAVING ABS(SUM(variance)) >= 2e6
ORDER BY variance_musd;


-- -------------------------------------------------------------
-- 4. CONTEXT from the budget file: what sits inside
--    (a) Police payroll budget and (b) the citywide personnel pool?
-- -------------------------------------------------------------
SELECT 'Police payroll' AS budget_area, account_name, ROUND(SUM(amount) / 1e6, 1) AS budget_2025_musd
FROM budget_2025
WHERE dept_number = 57 AND fund_name = 'Corporate Fund' AND account_code < '0100'
GROUP BY account_name
UNION ALL
SELECT 'Citywide personnel pool', account_name, ROUND(SUM(amount) / 1e6, 1)
FROM budget_2025
WHERE dept_number = 99
  AND fund_name IN ('Corporate Fund', 'Garbage Collection Fund', 'Foreign Fire Insurance Tax Fund')
  AND account_code < '0100'
GROUP BY account_name
ORDER BY budget_area, budget_2025_musd DESC;
