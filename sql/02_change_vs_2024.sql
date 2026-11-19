-- =============================================================
-- Chicago Budget Variance 2025
-- Step 2: "What changed from 2024 to 2025?"
-- Uses the budget_2024 and budget_2025 tables from script 01.
-- =============================================================

-- Corporate Fund budget by department, 2024 vs 2025,
-- with the change in $ and %.
WITH b24 AS (
    SELECT dept_name, SUM(amount) AS budget_2024
    FROM budget_2024
    WHERE fund_name = 'Corporate Fund'
    GROUP BY dept_name
),
b25 AS (
    SELECT dept_name, SUM(amount) AS budget_2025
    FROM budget_2025
    WHERE fund_name = 'Corporate Fund'
    GROUP BY dept_name
)
SELECT
    COALESCE(b25.dept_name, b24.dept_name)                       AS dept_name,
    ROUND(b24.budget_2024 / 1e6, 1)                              AS budget_2024_musd,
    ROUND(b25.budget_2025 / 1e6, 1)                              AS budget_2025_musd,
    ROUND((COALESCE(b25.budget_2025, 0)
         - COALESCE(b24.budget_2024, 0)) / 1e6, 1)               AS change_musd,
    ROUND(100 * (b25.budget_2025 - b24.budget_2024)
              / b24.budget_2024, 1)                              AS change_pct
FROM b24
FULL OUTER JOIN b25
    ON b24.dept_name = b25.dept_name
ORDER BY ABS(COALESCE(b25.budget_2025, 0) - COALESCE(b24.budget_2024, 0)) DESC;
