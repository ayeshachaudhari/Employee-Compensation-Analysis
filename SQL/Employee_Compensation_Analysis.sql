-- Step 1:  Create Database

CREATE DATABASE compensation_analysis;

-- Step 2: Database Select

USE compensation_analysis;

SHOW TABLES;

-- Step 3: Confirm

SELECT DATABASE();

-- Step 4: CSV File Import

-- Step 5:  Check Data

SELECT *FROM `employee_compensation (1)`
LIMIT 10;

-- Step 6: Total Employees aur Currency Check

SELECT
    currency,
    COUNT(*) AS employee_count,
    COUNT(DISTINCT employee_id) AS unique_employees
FROM `employee_compensation (1)`
GROUP BY currency
ORDER BY currency;

-- Step 7: Total Compensation Calculate

SELECT
    employee_id,
    department,
    job_level,
    job_family,
    work_location,
    base_salary,
    COALESCE(annual_bonus, 0) AS annual_bonus,
    COALESCE(equity_value, 0) AS equity_value,
    base_salary
        + COALESCE(annual_bonus, 0)
        + COALESCE(equity_value, 0) AS total_compensation,
    performance_rating,
    currency
FROM `employee_compensation (1)`
WHERE currency = 'USD'
ORDER BY total_compensation DESC;

-- Step 8: Department-wise Compensation Inequality (USD)

WITH comp AS (
    SELECT
        employee_id,
        department,
        base_salary
            + COALESCE(annual_bonus, 0)
            + COALESCE(equity_value, 0) AS total_comp
    FROM `employee_compensation (1)`
    WHERE currency = 'USD'
),
gini AS (
    SELECT
        a.department,
        SUM(ABS(a.total_comp - b.total_comp))
        / NULLIF(
            2 * POW(COUNT(DISTINCT a.employee_id), 2)
            * AVG(a.total_comp),
            0
        ) AS gini_coefficient
    FROM comp a
    JOIN comp b
        ON a.department = b.department
    GROUP BY a.department
),
ranked AS (
    SELECT
        department,
        total_comp,
        ROW_NUMBER() OVER (
            PARTITION BY department
            ORDER BY total_comp
        ) AS rn,
        COUNT(*) OVER (
            PARTITION BY department
        ) AS cnt
    FROM comp
),
medians AS (
    SELECT
        department,
        AVG(total_comp) AS median_compensation
    FROM ranked
    WHERE rn IN (
        FLOOR((cnt + 1) / 2),
        CEIL((cnt + 1) / 2)
    )
    GROUP BY department
)
SELECT
    g.department,
    m.median_compensation,
    ROUND(g.gini_coefficient, 4) AS gini_coefficient
FROM gini g
JOIN medians m
    ON g.department = m.department
ORDER BY g.gini_coefficient DESC;

/*
1. Compensation inequality and structural pay gaps

Calculate department-level compensation inequality using total compensation = base salary + annual bonus + equity value. Identify employees below department median despite above-median performance; employees in the company top 10% but below their job-level/department median; and whether disparities persist among comparable job levels, job families, and locations.
*/

-- Task 1: High Performance, Below-Median Compensation

WITH comp AS (
    SELECT
        employee_id,
        department,
        job_level,
        job_family,
        work_location,
        base_salary
            + COALESCE(annual_bonus, 0)
            + COALESCE(equity_value, 0) AS total_compensation,
        performance_rating
    FROM `employee_compensation (1)`
    WHERE currency = 'USD'
),
department_medians AS (
    SELECT
        department,
        AVG(total_compensation) AS median_compensation
    FROM (
        SELECT
            department,
            total_compensation,
            ROW_NUMBER() OVER (
                PARTITION BY department
                ORDER BY total_compensation
            ) AS rn,
            COUNT(*) OVER (
                PARTITION BY department
            ) AS cnt
        FROM comp
    ) ranked
    WHERE rn IN (
        FLOOR((cnt + 1) / 2),
        CEIL((cnt + 1) / 2)
    )
    GROUP BY department
),
performance_medians AS (
    SELECT
        department,
        AVG(performance_rating) AS median_rating
    FROM (
        SELECT
            department,
            performance_rating,
            ROW_NUMBER() OVER (
                PARTITION BY department
                ORDER BY performance_rating
            ) AS rn,
            COUNT(*) OVER (
                PARTITION BY department
            ) AS cnt
        FROM comp
    ) ranked
    WHERE rn IN (
        FLOOR((cnt + 1) / 2),
        CEIL((cnt + 1) / 2)
    )
    GROUP BY department
)
SELECT
    c.employee_id,
    c.department,
    c.job_level,
    c.job_family,
    c.work_location,
    c.total_compensation,
    c.performance_rating,
    dm.median_compensation,
    pm.median_rating
FROM comp c
JOIN department_medians dm
    ON c.department = dm.department
JOIN performance_medians pm
    ON c.department = pm.department
WHERE c.total_compensation < dm.median_compensation
  AND c.performance_rating > pm.median_rating
ORDER BY c.department, c.total_compensation;

-- Task 2: Identify employees in the company’s top 10% of total compensation who earn below the median compensation of comparable employees within the same department and job level.

WITH comp AS (
    SELECT
        employee_id,
        department,
        job_level,
        job_family,
        work_location,
        base_salary
            + COALESCE(annual_bonus, 0)
            + COALESCE(equity_value, 0) AS total_compensation
    FROM `employee_compensation (1)`
    WHERE currency = 'USD'
),
ranked AS (
    SELECT
        *,
        NTILE(10) OVER (
            ORDER BY total_compensation DESC
        ) AS pay_decile
    FROM comp
),
peer_medians AS (
    SELECT
        department,
        job_level,
        AVG(total_compensation) AS peer_median
    FROM (
        SELECT
            department,
            job_level,
            total_compensation,
            ROW_NUMBER() OVER (
                PARTITION BY department, job_level
                ORDER BY total_compensation
            ) AS rn,
            COUNT(*) OVER (
                PARTITION BY department, job_level
            ) AS cnt
        FROM comp
    ) x
    WHERE rn IN (
        FLOOR((cnt + 1) / 2),
        CEIL((cnt + 1) / 2)
    )
    GROUP BY department, job_level
)
SELECT
    r.employee_id,
    r.department,
    r.job_level,
    r.job_family,
    r.work_location,
    r.total_compensation,
    p.peer_median
FROM ranked r
JOIN peer_medians p
    ON r.department = p.department
   AND r.job_level = p.job_level
WHERE r.pay_decile = 1
  AND r.total_compensation < p.peer_median
ORDER BY r.total_compensation DESC;

-- Task 4: Compensation Disparities Among Comparable Employees

WITH comp AS (
    SELECT
        employee_id,
        department,
        job_level,
        job_family,
        work_location,
        base_salary
            + COALESCE(annual_bonus, 0)
            + COALESCE(equity_value, 0) AS total_compensation
    FROM `employee_compensation (1)`
    WHERE currency = 'USD'
),
peer_comparison AS (
    SELECT
        employee_id,
        department,
        job_level,
        job_family,
        work_location,
        total_compensation,
        COUNT(*) OVER (
            PARTITION BY
                department,
                job_level,
                job_family,
                work_location
        ) AS peer_count,
        AVG(total_compensation) OVER (
            PARTITION BY
                department,
                job_level,
                job_family,
                work_location
        ) AS peer_avg_compensation,
        MIN(total_compensation) OVER (
            PARTITION BY
                department,
                job_level,
                job_family,
                work_location
        ) AS peer_min_compensation,
        MAX(total_compensation) OVER (
            PARTITION BY
                department,
                job_level,
                job_family,
                work_location
        ) AS peer_max_compensation
    FROM comp
)
SELECT
    employee_id,
    department,
    job_level,
    job_family,
    work_location,
    total_compensation,
    peer_count,
    ROUND(peer_avg_compensation, 2) AS peer_avg_compensation,
    ROUND(peer_min_compensation, 2) AS peer_min_compensation,
    ROUND(peer_max_compensation, 2) AS peer_max_compensation,
    ROUND(
        peer_max_compensation - peer_min_compensation, 2
    ) AS compensation_gap
FROM peer_comparison
WHERE peer_count >= 2
  AND peer_max_compensation > peer_min_compensation
ORDER BY compensation_gap DESC, department, job_level;

/*
Question 2: Hiring-Sequence Salary Inversions
Identify pairs where a later-hired employee earns more base salary than an earlier-hired employee in the same department and job family. Calculate inversion rates, rank departments, and identify employees involved in the greatest number of inversions. Segment by job level, location, and performance rating.
*/

-- Step 1: Calculate Department-Level Salary Inversion Rates


WITH inversion_summary AS (
    SELECT
        e1.department,
        COUNT(*) AS comparable_pairs,
        SUM(
            CASE
                WHEN e2.base_salary > e1.base_salary THEN 1
                ELSE 0
            END
        ) AS inverted_pairs,
        ROUND(
            100.0 * SUM(
                CASE
                    WHEN e2.base_salary > e1.base_salary THEN 1
                    ELSE 0
                END
            ) / NULLIF(COUNT(*), 0),
            2
        ) AS inversion_rate_pct
    FROM `employee_compensation (1)` e1
    JOIN `employee_compensation (1)` e2
        ON e2.department = e1.department
        AND e2.job_family = e1.job_family
        AND e2.currency = e1.currency
        AND e2.hire_date > e1.hire_date
    WHERE e1.currency = 'USD'
      AND e2.currency = 'USD'
      AND e1.hire_date IS NOT NULL
      AND e2.hire_date IS NOT NULL
      AND e1.base_salary IS NOT NULL
      AND e2.base_salary IS NOT NULL
    GROUP BY e1.department
),
ranked_departments AS (
    SELECT
        *,
        DENSE_RANK() OVER (
            ORDER BY inversion_rate_pct DESC
        ) AS department_rank
    FROM inversion_summary
)
SELECT *
FROM ranked_departments
ORDER BY department_rank;

-- Step 2: Identify Employees Involved in the Greatest Number of Salary Inversions

WITH inversion_pairs AS (
    SELECT
        e1.employee_id AS earlier_employee_id,
        e2.employee_id AS later_employee_id,
        e1.department,
        e1.job_family,
        e1.job_level AS earlier_job_level,
        e2.job_level AS later_job_level,
        e1.work_location AS earlier_location,
        e2.work_location AS later_location,
        e1.performance_rating AS earlier_performance,
        e2.performance_rating AS later_performance
    FROM `employee_compensation (1)` e1
    JOIN `employee_compensation (1)` e2
        ON e2.department = e1.department
        AND e2.job_family = e1.job_family
        AND e2.currency = e1.currency
        AND e2.hire_date > e1.hire_date
    WHERE e1.currency = 'USD'
      AND e2.currency = 'USD'
      AND e1.hire_date IS NOT NULL
      AND e2.hire_date IS NOT NULL
      AND e1.base_salary IS NOT NULL
      AND e2.base_salary IS NOT NULL
      AND e2.base_salary > e1.base_salary
),
employee_counts AS (
    SELECT
        employee_id,
        department,
        SUM(later_inversions) AS later_hire_inversions,
        SUM(earlier_inversions) AS earlier_hire_inversions
    FROM (
        SELECT
            later_employee_id AS employee_id,
            department,
            1 AS later_inversions,
            0 AS earlier_inversions
        FROM inversion_pairs

        UNION ALL

        SELECT
            earlier_employee_id AS employee_id,
            department,
            0 AS later_inversions,
            1 AS earlier_inversions
        FROM inversion_pairs
    ) x
    GROUP BY employee_id, department
)
SELECT
    employee_id,
    department,
    later_hire_inversions,
    earlier_hire_inversions,
    later_hire_inversions + earlier_hire_inversions
        AS total_inversions
FROM employee_counts
ORDER BY total_inversions DESC, employee_id
LIMIT 20;

-- Step 3: Salary Inversions by Job Level

SELECT
    e1.department,
    e1.job_family,
    e1.job_level AS earlier_job_level,
    e2.job_level AS later_job_level,
    COUNT(*) AS comparable_pairs,
    SUM(
        CASE
            WHEN e2.base_salary > e1.base_salary THEN 1
            ELSE 0
        END
    ) AS inverted_pairs,
    ROUND(
        100.0 * SUM(
            CASE
                WHEN e2.base_salary > e1.base_salary THEN 1
                ELSE 0
            END
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS inversion_rate_pct
FROM `employee_compensation (1)` e1
JOIN `employee_compensation (1)` e2
    ON e1.department = e2.department
    AND e1.job_family = e2.job_family
    AND e1.currency = e2.currency
    AND e2.hire_date > e1.hire_date
WHERE e1.currency = 'USD'
    AND e1.hire_date IS NOT NULL
    AND e2.hire_date IS NOT NULL
    AND e1.base_salary IS NOT NULL
    AND e2.base_salary IS NOT NULL
GROUP BY
    e1.department,
    e1.job_family,
    e1.job_level,
    e2.job_level
ORDER BY
    inversion_rate_pct DESC,
    comparable_pairs DESC;

-- Step 4: Salary Inversions by Work Location

SELECT
    e1.department,
    e1.job_family,
    e1.work_location AS earlier_location,
    e2.work_location AS later_location,
    COUNT(*) AS comparable_pairs,
    SUM(
        CASE
            WHEN e2.base_salary > e1.base_salary THEN 1
            ELSE 0
        END
    ) AS inverted_pairs,
    ROUND(
        100.0 * SUM(
            CASE
                WHEN e2.base_salary > e1.base_salary THEN 1
                ELSE 0
            END
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS inversion_rate_pct
FROM `employee_compensation (1)` e1
JOIN `employee_compensation (1)` e2
    ON e1.department = e2.department
    AND e1.job_family = e2.job_family
    AND e1.currency = e2.currency
    AND e2.hire_date > e1.hire_date
WHERE e1.currency = 'USD'
    AND e1.hire_date IS NOT NULL
    AND e2.hire_date IS NOT NULL
    AND e1.base_salary IS NOT NULL
    AND e2.base_salary IS NOT NULL
GROUP BY
    e1.department,
    e1.job_family,
    e1.work_location,
    e2.work_location
ORDER BY
    inversion_rate_pct DESC,
    comparable_pairs DESC;
    
-- Step 5: Salary Inversions by Performance Rating

SELECT
    e1.department,
    e1.job_family,
    e1.performance_rating AS earlier_performance_rating,
    e2.performance_rating AS later_performance_rating,
    COUNT(*) AS comparable_pairs,
    SUM(
        CASE
            WHEN e2.base_salary > e1.base_salary THEN 1
            ELSE 0
        END
    ) AS inverted_pairs,
    ROUND(
        100.0 * SUM(
            CASE
                WHEN e2.base_salary > e1.base_salary THEN 1
                ELSE 0
            END
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS inversion_rate_pct
FROM `employee_compensation (1)` e1
JOIN `employee_compensation (1)` e2
    ON e1.department = e2.department
    AND e1.job_family = e2.job_family
    AND e1.currency = e2.currency
    AND e2.hire_date > e1.hire_date
WHERE e1.currency = 'USD'
    AND e1.hire_date IS NOT NULL
    AND e2.hire_date IS NOT NULL
    AND e1.base_salary IS NOT NULL
    AND e2.base_salary IS NOT NULL
    AND e1.performance_rating IS NOT NULL
    AND e2.performance_rating IS NOT NULL
GROUP BY
    e1.department,
    e1.job_family,
    e1.performance_rating,
    e2.performance_rating
ORDER BY
    inversion_rate_pct DESC,
    comparable_pairs DESC;
    
/*
3. Counterfactual workforce restructuring
For each department, calculate how mean salary, median salary, and total compensation inequality change when employees at levels L7 and L8 are excluded. Separately rank individual employee removals by marginal effect on department-level salary variance, with a minimum department-size requirement.
*/

-- Step 1: Department-wise Salary Comparison

WITH department_metrics AS (
    SELECT
        department,

        COUNT(base_salary) AS original_employee_count,

        AVG(base_salary) AS original_mean_salary,

        VAR_POP(base_salary) AS original_salary_variance,

        COUNT(
            CASE
                WHEN job_level NOT IN ('L7', 'L8')
                THEN base_salary
            END
        ) AS revised_employee_count,

        AVG(
            CASE
                WHEN job_level NOT IN ('L7', 'L8')
                THEN base_salary
            END
        ) AS revised_mean_salary,

        VAR_POP(
            CASE
                WHEN job_level NOT IN ('L7', 'L8')
                THEN base_salary
            END
        ) AS revised_salary_variance

    FROM `employee_compensation (1)`
    WHERE currency = 'USD'
    GROUP BY department
)

SELECT
    department,
    original_employee_count,
    revised_employee_count,

    ROUND(original_mean_salary, 2)
        AS original_mean_salary,

    ROUND(revised_mean_salary, 2)
        AS revised_mean_salary,

    ROUND(
        revised_mean_salary - original_mean_salary, 2
    ) AS mean_salary_change,

    ROUND(original_salary_variance, 2)
        AS original_salary_variance,

    ROUND(revised_salary_variance, 2)
        AS revised_salary_variance,

    ROUND(
        revised_salary_variance - original_salary_variance, 2
    ) AS variance_change

FROM department_metrics
ORDER BY department;

-- Step 2: Department-wise Median Salary

WITH ranked_salaries AS (
    SELECT
        department,
        base_salary,
        job_level,
        ROW_NUMBER() OVER (
            PARTITION BY department
            ORDER BY base_salary
        ) AS original_rank,
        COUNT(*) OVER (
            PARTITION BY department
        ) AS original_count,
        ROW_NUMBER() OVER (
            PARTITION BY department,
                CASE
                    WHEN job_level NOT IN ('L7', 'L8') THEN 1
                END
            ORDER BY base_salary
        ) AS revised_rank
    FROM `employee_compensation (1)`
    WHERE currency = 'USD'
),
median_values AS (
    SELECT
        department,
        AVG(
            CASE
                WHEN original_rank IN (
                    FLOOR((original_count + 1) / 2),
                    FLOOR((original_count + 2) / 2)
                )
                THEN base_salary
            END
        ) AS original_median_salary,
        AVG(
            CASE
                WHEN job_level NOT IN ('L7', 'L8')
                THEN base_salary
            END
        ) AS revised_mean_check
    FROM ranked_salaries
    GROUP BY department
),
revised_ranked AS (
    SELECT
        department,
        base_salary,
        ROW_NUMBER() OVER (
            PARTITION BY department
            ORDER BY base_salary
        ) AS salary_rank,
        COUNT(*) OVER (
            PARTITION BY department
        ) AS total_count
    FROM `employee_compensation (1)`
    WHERE currency = 'USD'
      AND job_level NOT IN ('L7', 'L8')
),
revised_medians AS (
    SELECT
        department,
        AVG(
            CASE
                WHEN salary_rank IN (
                    FLOOR((total_count + 1) / 2),
                    FLOOR((total_count + 2) / 2)
                )
                THEN base_salary
            END
        ) AS revised_median_salary
    FROM revised_ranked
    GROUP BY department
)
SELECT
    m.department,
    ROUND(m.original_median_salary, 2) AS original_median_salary,
    ROUND(r.revised_median_salary, 2) AS revised_median_salary,
    ROUND(
        r.revised_median_salary - m.original_median_salary, 2
    ) AS median_salary_change
FROM median_values m
LEFT JOIN revised_medians r
    ON m.department = r.department
ORDER BY m.department;

-- Step 3: Total Compensation Inequality (Gini)

WITH employee_comp AS (
    SELECT
        employee_id,
        department,
        job_level,
        base_salary
            + COALESCE(annual_bonus, 0)
            + COALESCE(equity_value, 0) AS total_compensation
    FROM `employee_compensation (1)`
    WHERE currency = 'USD'
),
scenarios AS (
    SELECT
        employee_id,
        department,
        'Original' AS scenario,
        total_compensation
    FROM employee_comp

    UNION ALL

    SELECT
        employee_id,
        department,
        'L7_L8_Excluded' AS scenario,
        total_compensation
    FROM employee_comp
    WHERE job_level NOT IN ('L7', 'L8')
),
department_stats AS (
    SELECT
        department,
        scenario,
        COUNT(*) AS employee_count,
        AVG(total_compensation) AS mean_compensation
    FROM scenarios
    GROUP BY department, scenario
),
pair_differences AS (
    SELECT
        a.department,
        a.scenario,
        SUM(ABS(a.total_compensation - b.total_compensation))
            AS difference_sum
    FROM scenarios a
    JOIN scenarios b
        ON a.department = b.department
       AND a.scenario = b.scenario
    GROUP BY a.department, a.scenario
)
SELECT
    d.department,
    d.scenario,
    d.employee_count,
    ROUND(d.mean_compensation, 2) AS mean_compensation,
    ROUND(
        p.difference_sum /
        (2 * d.employee_count * d.employee_count * d.mean_compensation),
        4
    ) AS gini_coefficient
FROM department_stats d
JOIN pair_differences p
    ON d.department = p.department
   AND d.scenario = p.scenario
ORDER BY d.department, d.scenario;

-- Step 4: Individual Employee Removal Ranking

WITH department_sizes AS (
    SELECT
        department,
        COUNT(*) AS original_count
    FROM `employee_compensation (1)`
    WHERE currency = 'USD'
    GROUP BY department
),
original_variance AS (
    SELECT
        department,
        COUNT(*) AS employee_count,
        VAR_POP(base_salary) AS original_variance
    FROM `employee_compensation (1)`
    WHERE currency = 'USD'
    GROUP BY department
),
removal_candidates AS (
    SELECT
        e.employee_id,
        e.department,
        e.job_level,
        e.base_salary,
        d.original_count
    FROM `employee_compensation (1)` e
    JOIN department_sizes d
        ON e.department = d.department
    WHERE e.currency = 'USD'
      AND d.original_count - 1 >= 5
),
variance_after_removal AS (
    SELECT
        c.employee_id,
        c.department,
        c.job_level,
        c.base_salary,
        o.original_variance,
        (
            SELECT VAR_POP(e2.base_salary)
            FROM `employee_compensation (1)` e2
            WHERE e2.currency = 'USD'
              AND e2.department = c.department
              AND e2.employee_id <> c.employee_id
        ) AS revised_variance
    FROM removal_candidates c
    JOIN original_variance o
        ON c.department = o.department
)
SELECT
    employee_id,
    department,
    job_level,
    base_salary,
    ROUND(original_variance, 2) AS original_variance,
    ROUND(revised_variance, 2) AS revised_variance,
    ROUND(revised_variance - original_variance, 2)
        AS variance_change
FROM variance_after_removal
ORDER BY variance_change ASC
LIMIT 20;

/*
Compensation trajectory and benchmark instability
Calculate rankings under all employees, active employees only, and active employees hired within the last five
years. Identify employees whose ranking improves by at least five positions when exited employees are
excluded and employees who remain in the top 10% across all three definitions.
*/

-- Step 1: Check Employee Status

SELECT
    employment_status,
    COUNT(*) AS employee_count
FROM `employee_compensation (1)`
WHERE currency = 'USD'
GROUP BY employment_status;

-- Step 2: Calculate Compensation Rankings Under All Three Definitions

WITH employee_data AS (
    SELECT
        employee_id,
        employment_status,
        hire_date,
        base_salary
            + COALESCE(annual_bonus, 0)
            + COALESCE(equity_value, 0) AS total_compensation
    FROM `employee_compensation (1)`
    WHERE currency = 'USD'
),
all_rankings AS (
    SELECT
        *,
        RANK() OVER (
            ORDER BY total_compensation DESC
        ) AS all_employee_rank
    FROM employee_data
),
active_rankings AS (
    SELECT
        employee_id,
        RANK() OVER (
            ORDER BY total_compensation DESC
        ) AS active_employee_rank
    FROM employee_data
    WHERE employment_status = 'Active'
),
recent_active_rankings AS (
    SELECT
        employee_id,
        RANK() OVER (
            ORDER BY total_compensation DESC
        ) AS recent_active_rank
    FROM employee_data
    WHERE employment_status = 'Active'
      AND hire_date >= DATE_SUB(CURDATE(), INTERVAL 5 YEAR)
)
SELECT
    a.employee_id,
    a.employment_status,
    a.hire_date,
    ROUND(a.total_compensation, 2) AS total_compensation,
    a.all_employee_rank,
    ar.active_employee_rank,
    rr.recent_active_rank
FROM all_rankings a
LEFT JOIN active_rankings ar
    ON a.employee_id = ar.employee_id
LEFT JOIN recent_active_rankings rr
    ON a.employee_id = rr.employee_id
ORDER BY a.all_employee_rank;

-- Step 3: Identify Employees Whose Ranking Improves by at Least 5 Positions

WITH employee_data AS (
    SELECT
        employee_id,
        employment_status,
        base_salary
            + COALESCE(annual_bonus, 0)
            + COALESCE(equity_value, 0) AS total_compensation
    FROM `employee_compensation (1)`
    WHERE currency = 'USD'
),
all_rankings AS (
    SELECT
        employee_id,
        employment_status,
        total_compensation,
        RANK() OVER (
            ORDER BY total_compensation DESC
        ) AS original_rank
    FROM employee_data
),
rankings_without_exited AS (
    SELECT
        employee_id,
        RANK() OVER (
            ORDER BY total_compensation DESC
        ) AS revised_rank
    FROM employee_data
    WHERE employment_status <> 'Exited'
)
SELECT
    a.employee_id,
    a.employment_status,
    ROUND(a.total_compensation, 2) AS total_compensation,
    a.original_rank,
    r.revised_rank,
    a.original_rank - r.revised_rank AS positions_improved
FROM all_rankings a
JOIN rankings_without_exited r
    ON a.employee_id = r.employee_id
WHERE a.employment_status <> 'Exited'
  AND a.original_rank - r.revised_rank >= 5
ORDER BY positions_improved DESC, a.employee_id;

-- Step 4: Identify Employees Who Remain in the Top 10% Across All Three Rankings

WITH employee_data AS (
    SELECT
        employee_id,
        employment_status,
        hire_date,
        base_salary
            + COALESCE(annual_bonus, 0)
            + COALESCE(equity_value, 0) AS total_compensation
    FROM `employee_compensation (1)`
    WHERE currency = 'USD'
),
all_rankings AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            ORDER BY total_compensation DESC, employee_id
        ) AS all_rank,
        COUNT(*) OVER () AS all_count
    FROM employee_data
),
active_rankings AS (
    SELECT
        employee_id,
        ROW_NUMBER() OVER (
            ORDER BY total_compensation DESC, employee_id
        ) AS active_rank,
        COUNT(*) OVER () AS active_count
    FROM employee_data
    WHERE employment_status = 'Active'
),
recent_active_rankings AS (
    SELECT
        employee_id,
        ROW_NUMBER() OVER (
            ORDER BY total_compensation DESC, employee_id
        ) AS recent_rank,
        COUNT(*) OVER () AS recent_count
    FROM employee_data
    WHERE employment_status = 'Active'
      AND hire_date >= DATE_SUB(CURDATE(), INTERVAL 5 YEAR)
)
SELECT
    a.employee_id,
    ROUND(a.total_compensation, 2) AS total_compensation,
    a.all_rank,
    ar.active_rank,
    rr.recent_rank
FROM all_rankings a
JOIN active_rankings ar
    ON a.employee_id = ar.employee_id
JOIN recent_active_rankings rr
    ON a.employee_id = rr.employee_id
WHERE a.all_rank <= CEIL(a.all_count * 0.10)
  AND ar.active_rank <= CEIL(ar.active_count * 0.10)
  AND rr.recent_rank <= CEIL(rr.recent_count * 0.10)
ORDER BY a.total_compensation DESC;

/*
 Executive recommendation
Produce a ranked list of five compensation architecture risks, each supported by a measurable indicator,
affected population, and magnitude of discrepancy
*/

-- Step 1: Measure Compensation Inequality by Department

WITH compensation_data AS (
    SELECT
        employee_id,
        department,
        base_salary
            + COALESCE(annual_bonus, 0)
            + COALESCE(equity_value, 0) AS total_compensation
    FROM `employee_compensation (1)`
    WHERE currency = 'USD'
),
department_totals AS (
    SELECT
        department,
        COUNT(*) AS employee_count,
        SUM(total_compensation) AS total_compensation,
        AVG(total_compensation) AS mean_compensation
    FROM compensation_data
    GROUP BY department
),
pairwise_differences AS (
    SELECT
        a.department,
        SUM(ABS(a.total_compensation - b.total_compensation))
            AS total_absolute_difference
    FROM compensation_data a
    JOIN compensation_data b
        ON a.department = b.department
    GROUP BY a.department
)
SELECT
    d.department,
    d.employee_count,
    ROUND(d.mean_compensation, 2) AS mean_compensation,
    ROUND(
        p.total_absolute_difference
        / (2 * d.employee_count * d.total_compensation),
        4
    ) AS gini_coefficient
FROM department_totals d
JOIN pairwise_differences p
    ON d.department = p.department
ORDER BY gini_coefficient DESC;

-- Step 2: Identify Pay Inequity Risk

WITH employee_data AS (
    SELECT
        employee_id,
        department,
        performance_rating,
        base_salary
            + COALESCE(annual_bonus, 0)
            + COALESCE(equity_value, 0) AS total_compensation
    FROM `employee_compensation (1)`
    WHERE currency = 'USD'
),
department_medians AS (
    SELECT
        department,
        AVG(total_compensation) AS median_compensation
    FROM (
        SELECT
            department,
            total_compensation,
            ROW_NUMBER() OVER (
                PARTITION BY department
                ORDER BY total_compensation
            ) AS rn,
            COUNT(*) OVER (
                PARTITION BY department
            ) AS cnt
        FROM employee_data
    ) ranked
    WHERE rn IN (
        FLOOR((cnt + 1) / 2),
        FLOOR((cnt + 2) / 2)
    )
    GROUP BY department
),
performance_medians AS (
    SELECT
        department,
        AVG(performance_rating) AS median_performance
    FROM employee_data
    GROUP BY department
)
SELECT
    e.employee_id,
    e.department,
    e.performance_rating,
    ROUND(e.total_compensation, 2) AS total_compensation,
    ROUND(d.median_compensation, 2) AS department_median,
    ROUND(
        d.median_compensation - e.total_compensation, 2
    ) AS compensation_gap
FROM employee_data e
JOIN department_medians d
    ON e.department = d.department
JOIN performance_medians p
    ON e.department = p.department
WHERE e.total_compensation < d.median_compensation
  AND e.performance_rating > p.median_performance
ORDER BY compensation_gap DESC;

-- Step 3: Measure Hiring-Sequence Salary Inversions

WITH employee_pairs AS (
    SELECT
        earlier.employee_id AS earlier_employee,
        later.employee_id AS later_employee,
        earlier.department,
        earlier.job_family,
        earlier.hire_date AS earlier_hire_date,
        later.hire_date AS later_hire_date,
        earlier.base_salary AS earlier_salary,
        later.base_salary AS later_salary,
        later.base_salary - earlier.base_salary AS salary_gap
    FROM `employee_compensation (1)` earlier
    JOIN `employee_compensation (1)` later
        ON earlier.department = later.department
       AND earlier.job_family = later.job_family
       AND earlier.hire_date < later.hire_date
    WHERE earlier.currency = 'USD'
      AND later.currency = 'USD'
      AND later.base_salary > earlier.base_salary
)
SELECT
    department,
    job_family,
    COUNT(*) AS inversion_count,
    ROUND(MAX(salary_gap), 2) AS largest_salary_gap,
    ROUND(AVG(salary_gap), 2) AS average_salary_gap
FROM employee_pairs
GROUP BY department, job_family
ORDER BY inversion_count DESC, largest_salary_gap DESC;

-- Step 4: Identify Compensation Gaps Among Comparable Employees

SELECT
    department,
    job_level,
    job_family,
    work_location,
    COUNT(*) AS employee_count,
    ROUND(MIN(total_compensation), 2) AS minimum_compensation,
    ROUND(MAX(total_compensation), 2) AS maximum_compensation,
    ROUND(
        MAX(total_compensation) - MIN(total_compensation), 2
    ) AS compensation_gap
FROM (
    SELECT
        employee_id,
        department,
        job_level,
        job_family,
        work_location,
        base_salary
            + COALESCE(annual_bonus, 0)
            + COALESCE(equity_value, 0) AS total_compensation
    FROM `employee_compensation (1)`
    WHERE currency = 'USD'
) AS employee_data
GROUP BY
    department,
    job_level,
    job_family,
    work_location
HAVING COUNT(*) >= 2
ORDER BY compensation_gap DESC;
