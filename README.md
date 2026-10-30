# Employee-Compensation-Analysis
MySQL SQL Case Study – Employee Compensation, Salary Inequality, Pay Gaps, Salary Inversions and Workforce Analysis.

#  Employee Compensation Analysis – Pay Equity & Compensation Architecture (MySQL)

A SQL case study on employee compensation data. It measures pay inequality across departments, detects hiring-sequence salary inversions, simulates workforce restructuring, tests how rankings change under different benchmark definitions, and closes with an executive-level view of compensation risks.

![MySQL](https://img.shields.io/badge/MySQL-8.0+-4479A1?logo=mysql&logoColor=white)
![SQL](https://img.shields.io/badge/Language-SQL-orange)
![Status](https://img.shields.io/badge/Status-Completed-brightgreen)

---

##  Project Overview

| Item | Details |
|---|---|
| **Database** | MySQL 8.0+ |
| **Database name** | `compensation_analysis` |
| **Source table** | `employee_compensation` (imported from CSV) |
| **Script** | `case_study__3.sql` |
| **Domain** | HR Analytics / Compensation & Pay Equity |
| **Questions solved** | 5 (with step-by-step queries) |

The case study answers questions an HR or compensation team would ask: *Where are the structural pay gaps? Are high performers paid below their peers? Do newer hires earn more than people who joined earlier? What happens to pay inequality if senior levels are removed? Which findings hold up across different benchmarks?*

---

##  Data Used

The script works on one flat table imported from a CSV file (one row per employee).

| Column | Meaning |
|---|---|
| `employee_id` | Unique employee identifier |
| `department` | Employee's department |
| `job_level` | Job level (e.g. L1 – L8) |
| `job_family` | Job family / function |
| `work_location` | Work location |
| `hire_date` | Date of joining |
| `employment_status` | Active / Exited |
| `performance_rating` | Latest performance rating |
| `base_salary` | Annual base salary |
| `annual_bonus` | Annual bonus (can be NULL) |
| `equity_value` | Equity value (can be NULL) |
| `currency` | Currency of the compensation figures |

> The script does not contain the data. Import your CSV into `compensation_analysis` using MySQL Workbench's Table Data Import Wizard. In the script the imported table is named `` `employee_compensation (1)` ``; if your table has a different name, update it in the queries.

---

##  Key Metric Definitions

| Metric | Formula |
|---|---|
| **Total compensation** |
