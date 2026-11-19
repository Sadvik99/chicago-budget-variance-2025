-- =============================================================
-- Chicago Budget Variance 2025
-- Step 4: "Who overspent and who underspent in 2025?"
--
-- Source of actuals: City of Chicago 2025 ACFR, Schedule A-2
-- (General Fund, budgetary basis), extracted to actuals_2025.csv
-- by python/extract_acfr_actuals.py.
-- Variance = final budget - actual.
--   Positive = UNDER budget (favorable)
--   Negative = OVER budget  (unfavorable)
-- =============================================================

-- -------------------------------------------------------------
-- 1. LOAD the actuals (set the path to your data folder, as in script 01)
-- -------------------------------------------------------------
CREATE OR REPLACE TABLE actuals_2025 AS
SELECT *
FROM read_csv('/path/to/chicago-budget-vs-actual-2025/data/actuals_2025.csv',
              header = true,
              types = {'approp_code': 'VARCHAR', 'account_code': 'VARCHAR'});


-- -------------------------------------------------------------
-- 2. RECONCILE: does the ACFR budget match our budget file?
-- The ACFR "General Fund" = Corporate Fund + Garbage Collection Fund
-- + Foreign Fire Insurance Tax Fund. It also reports Business Affairs
-- (70) under Buildings (67) and the Community Commission (62)
-- under COPA (60). With those rules, every department should match.
-- -------------------------------------------------------------
WITH ordinance AS (
    SELECT CASE dept_number WHEN 70 THEN 67 WHEN 62 THEN 60 ELSE dept_number END AS dept_number,
           SUM(amount) AS budget
    FROM budget_2025
    WHERE fund_name IN ('Corporate Fund', 'Garbage Collection Fund', 'Foreign Fire Insurance Tax Fund')
    GROUP BY 1
),
acfr AS (
    SELECT dept_number, SUM(final_budget) AS budget
    FROM actuals_2025
    GROUP BY 1
)
SELECT
    ROUND(SUM(o.budget) / 1e6, 1)                                         AS ordinance_musd,
    ROUND(SUM(a.budget) / 1e6, 1)                                         AS acfr_budget_musd,
    COUNT(*) FILTER (WHERE ABS(COALESCE(o.budget, 0) - COALESCE(a.budget, 0)) > 1000) AS depts_not_matching
FROM ordinance o
FULL OUTER JOIN acfr a USING (dept_number);


-- -------------------------------------------------------------
-- 3. QUESTION 4: budget vs actual by department.
-- Flag = material if the variance is at least $5M,
-- or at least 5% of budget AND at least $1M (so tiny offices
-- with a $40K gap don't get flagged).
-- -------------------------------------------------------------
CREATE OR REPLACE VIEW dept_variance_2025 AS
WITH names AS (
    SELECT dept_number, ANY_VALUE(dept_name) AS dept_name
    FROM budget_2025
    GROUP BY dept_number
)
SELECT
    a.dept_number,
    COALESCE(n.dept_name, ANY_VALUE(a.dept_name_acfr))                    AS dept_name,
    SUM(a.final_budget)                                                   AS budget,
    SUM(a.actual)                                                         AS actual,
    SUM(a.final_budget) - SUM(a.actual)                                   AS variance
FROM actuals_2025 a
LEFT JOIN names n USING (dept_number)
GROUP BY a.dept_number, n.dept_name;

SELECT
    dept_name,
    ROUND(budget / 1e6, 1)                                                AS budget_musd,
    ROUND(actual / 1e6, 1)                                                AS actual_musd,
    ROUND(variance / 1e6, 1)                                              AS variance_musd,
    ROUND(100 * variance / budget, 1)                                     AS variance_pct,
    CASE WHEN variance < 0 THEN 'Over budget' ELSE 'Under budget' END     AS direction,
    CASE WHEN ABS(variance) >= 5e6
           OR (ABS(variance / budget) >= 0.05 AND ABS(variance) >= 1e6)
         THEN 'Material' ELSE '' END                                      AS flag
FROM dept_variance_2025
ORDER BY variance;   -- biggest overspenders first, biggest underspenders last


-- -------------------------------------------------------------
-- 4. THE BIG PICTURE: total over vs total under.
-- -------------------------------------------------------------
SELECT
    ROUND(SUM(budget)   / 1e6, 1)                                         AS total_budget_musd,
    ROUND(SUM(actual)   / 1e6, 1)                                         AS total_actual_musd,
    ROUND(SUM(variance) / 1e6, 1)                                         AS net_under_budget_musd,
    ROUND(SUM(CASE WHEN variance < 0 THEN variance END) / 1e6, 1)         AS total_overspend_musd,
    ROUND(SUM(CASE WHEN variance > 0 THEN variance END) / 1e6, 1)         AS total_underspend_musd,
    COUNT(*) FILTER (WHERE variance < 0)                                  AS depts_over,
    COUNT(*) FILTER (WHERE variance > 0)                                  AS depts_under
FROM dept_variance_2025;
