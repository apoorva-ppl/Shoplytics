# (Shoplytics)E-commerce Analytics with PostgreSQL

An end-to-end SQL analytics project on a simulated online retailer: a normalized
schema, a procedurally generated dataset (~5K customers, ~14K orders, ~57K line
items over 3 years), and **10 analytical queries** answering the kinds of
questions a data analyst is asked on the job — revenue trends, customer
segmentation, cohort retention, churn, lifetime value, and product performance.

Every query in this repository has been executed against **PostgreSQL 16**, and
the outputs shown below are real results from the generated dataset.

**[Live interactive dashboard →](https://sql-ecommerce-dashboard.vercel.app)**

Charts for every analysis, plus a live SQL playground — a full PostgreSQL
database runs in your browser (via PGlite/WASM), so you can run the queries
yourself. No setup required, and nothing is sent to a server.

> **Why this project?** It demonstrates breadth in practical SQL — not just
> `SELECT ... GROUP BY`, but window functions, recursive CTEs, RFM scoring,
> cohort triangles, and a materialized view backed by a PL/pgSQL function —
> against data that behaves like a real business (seasonality, growth, churn).

---

## SQL techniques demonstrated

| Technique | Where to find it |
|---|---|
| Schema design (PK/FK, `CHECK` constraints, surrogate keys) | [`schema/01_create_tables.sql`](schema/01_create_tables.sql) |
| Indexing strategy for analytical workloads | [`schema/02_indexes.sql`](schema/02_indexes.sql) |
| Window functions — `ROW_NUMBER`, `RANK`, `NTILE`, `LAG`, `PERCENT_RANK` | analyses 02, 04, 05, 06, 09 |
| Running totals / moving averages (`SUM/AVG OVER`) | [`analysis/01`](analysis/01_revenue_overview.sql), [`09`](analysis/09_running_totals_pareto.sql) |
| Common Table Expressions (multi-CTE pipelines) | every analysis |
| Recursive CTE (hierarchy traversal + roll-up) | [`analysis/10`](analysis/10_recursive_category_tree.sql) |
| Conditional aggregation (`FILTER`, `CASE`) | analyses 01, 03, 08 |
| `PERCENTILE_CONT` (median / p90) | [`analysis/06`](analysis/06_customer_ltv.sql) |
| RFM customer segmentation | [`analysis/02`](analysis/02_customer_rfm_segmentation.sql) |
| Cohort retention analysis | [`analysis/03`](analysis/03_cohort_retention.sql) |
| Views and a materialized view | [`schema/03_views.sql`](schema/03_views.sql), [`functions/`](functions/rfm_segment_function.sql) |
| PL/pgSQL function | [`functions/rfm_segment_function.sql`](functions/rfm_segment_function.sql) |
| Reproducible synthetic data generation (`generate_series`, `setseed`) | [`data/`](data/) |

---

## Dataset

A simulated retailer selling Electronics, Home & Kitchen, Apparel, and Books
across 21 cities. Generated deterministically (seeded RNG), so anyone who runs
it gets identical numbers.

| Table | Rows | Description |
|---|---:|---|
| `customers` | 5,000 | Signup date, location, acquisition channel |
| `orders` | ~14,200 | Order header (status, payment method) |
| `order_items` | ~56,800 | Fact grain — one row per product per order |
| `products` | 400 | Catalog across a 3-level category tree |
| `categories` | 22 | Self-referential hierarchy |
| `returns` | ~4,700 | Line-item returns with reasons |
| `campaigns` | 11 | Marketing spend by channel |

Behavioral patterns built into the data so the analyses surface something
meaningful:

- **Growth** — the customer base and revenue grow year over year.
- **Seasonality** — November/December run roughly 2x the monthly baseline.
- **Churn** — about 60% of customers are one-and-done; a ~5% VIP tier drives
  outsized revenue.
- **Returns** — higher for Electronics and Apparel (~12%) than other
  departments (~5%).

See [`docs/ER_diagram.md`](docs/ER_diagram.md) for the full entity-relationship
diagram.

---

## Quick start

**Option A — Docker (no local Postgres needed):**

```bash
# 1. Start a throwaway Postgres instance
docker run -d --name pg -e POSTGRES_PASSWORD=pw -e POSTGRES_DB=ecommerce_analytics -p 5432:5432 postgres:16

# 2. Load schema, data, views, and functions (one shot)
docker cp . pg:/work
docker exec -w /work pg psql -U postgres -d ecommerce_analytics -f run_all.sql

# 3. Run any analysis
docker exec -w /work pg psql -U postgres -d ecommerce_analytics -f analysis/03_cohort_retention.sql
```

**Option B — Local psql:**

```bash
createdb ecommerce_analytics
psql -d ecommerce_analytics -f run_all.sql
psql -d ecommerce_analytics -f analysis/02_customer_rfm_segmentation.sql
```

All objects live in a `shop` schema. In an interactive session, run
`SET search_path TO shop;` first.

---

## The analyses

### 01 · Revenue overview — [`analysis/01_revenue_overview.sql`](analysis/01_revenue_overview.sql)

Monthly gross/net/realized revenue, return rate, gross margin, and a 3-month
moving average. *Techniques: conditional aggregation, `AVG() OVER` window,
`LAG` for YoY deltas.* The holiday spike is unmistakable:

```
  month  | net_revenue | returned_rev | orders | active_customers
---------+-------------+--------------+--------+------------------
 2024-10 | 2,901,828   | 209,708      |    468 |              422
 2024-11 | 5,690,311   | 450,680      |    950 |              466   <- Black Friday
 2024-12 | 6,139,069   | 496,408      |   1027 |              496   <- December
```

### 02 · RFM customer segmentation — [`analysis/02_customer_rfm_segmentation.sql`](analysis/02_customer_rfm_segmentation.sql)

Scores every customer 1–5 on **R**ecency, **F**requency, and **M**onetary
value using `NTILE(5)`, then buckets them into actionable segments. The
headline: roughly 19% of buyers ("Champions") drive about 41% of revenue.

```
     segment     | customers | avg_spend | total_revenue
-----------------+-----------+-----------+---------------
 Champion        |       914 | 32,835    | 30,010,918
 At Risk         |       895 | 19,008    | 17,011,880
 Loyal           |       450 | 23,083    | 10,387,139
 Regular         |      1001 | 8,240     | 8,248,138
 Lost            |      1009 | 4,796     | 4,838,686
 New / Promising |       494 | 4,813     | 2,377,615
```

### 03 · Cohort retention — [`analysis/03_cohort_retention.sql`](analysis/03_cohort_retention.sql)

The classic retention triangle: of customers who first ordered in month *X*,
what percentage came back *N* months later? *Techniques: first-order
self-join, month arithmetic, pivot via `FILTER`.*

```
 cohort_month | cohort_size |  m0   |  m1  |  m2  |  m3  |  m6  | m12
--------------+-------------+-------+------+------+------+------+-----
 2022-01-01   |          26 | 100.0 | 23.1 | 15.4 | 19.2 | 11.5 | 7.7
 2022-04-01   |          70 | 100.0 | 27.1 | 18.6 | 15.7 | 18.6 | 5.7
```

### 04 · Product performance — [`analysis/04_product_performance.sql`](analysis/04_product_performance.sql)

Ranks products and flags the top and bottom 10% within each category using
`PERCENT_RANK()`, including a `LEFT JOIN` so zero-sales products aren't lost.

### 05 · Top-N per group — [`analysis/05_top_n_per_group.sql`](analysis/05_top_n_per_group.sql)

The canonical "best-selling product per category per year" problem, solved
with `ROW_NUMBER() OVER (PARTITION BY year, category ORDER BY revenue DESC)`.

### 06 · Customer lifetime value — [`analysis/06_customer_ltv.sql`](analysis/06_customer_ltv.sql)

Average order value, days between purchases (`LAG`), and LTV distribution
(`PERCENTILE_CONT` for median and p90), broken out by acquisition channel —
directly useful for deciding where to spend marketing dollars.

```
 acquisition_channel | customers | avg_ltv  | avg_order_value | median_ltv | p90_ltv
---------------------+-----------+----------+-----------------+------------+----------
 display             |       434 | 20098.36 |         6093.37 |   13926.06 | 41949.57
 social              |       316 | 16501.25 |         6219.48 |    8266.21 | 38504.37
 referral            |      3731 | 16253.09 |         6074.93 |    9322.43 | 35644.20
```

### 07 · Churn analysis — [`analysis/07_churn_analysis.sql`](analysis/07_churn_analysis.sql)

Quarter-over-quarter churn rate (did an active customer come back the next
quarter?), joined against marketing spend to check whether spend moves the
needle.

### 08 · Year-over-year growth — [`analysis/08_yoy_growth.sql`](analysis/08_yoy_growth.sql)

Revenue by category by year, pivoted wide with `FILTER`, with YoY percentage
columns and `NULLIF` guards against divide-by-zero.

### 09 · Pareto / ABC analysis — [`analysis/09_running_totals_pareto.sql`](analysis/09_running_totals_pareto.sql)

Tests the 80/20 rule with a cumulative running total
(`SUM() OVER (ORDER BY revenue DESC)`) and classifies every product A/B/C.

### 10 · Recursive category tree — [`analysis/10_recursive_category_tree.sql`](analysis/10_recursive_category_tree.sql)

A `WITH RECURSIVE` walk down the category hierarchy that builds the full path
(e.g., `Electronics > Computers > Laptops`) and rolls leaf revenue up to each
ancestor.

```
 depth | indented_name |       full_path        | direct_revenue | rollup_revenue
-------+---------------+------------------------+----------------+----------------
     1 | Apparel       | Apparel                |           0.00 |   14,435,496.49
     2 |   Womens      | Apparel > Womens       |   5,103,643.97 |    5,103,643.97
     1 | Electronics   | Electronics            |           0.00 |   37,897,570.92
```

---

## Repository structure

```
sql-ecommerce-analytics/
├── README.md
├── run_all.sql                      # One-shot build: schema -> data -> views/functions
├── schema/
│   ├── 01_create_tables.sql         # Tables, PK/FK, CHECK constraints
│   ├── 02_indexes.sql               # Indexes for the analytical workload
│   └── 03_views.sql                 # Reusable revenue views
├── data/
│   ├── 01_seed_reference_data.sql   # Categories, products, campaigns
│   └── 02_seed_transactions.sql     # Procedurally generated customers/orders/...
├── functions/
│   └── rfm_segment_function.sql     # PL/pgSQL function + materialized view
├── analysis/
│   ├── 01_revenue_overview.sql
│   ├── 02_customer_rfm_segmentation.sql
│   ├── 03_cohort_retention.sql
│   ├── 04_product_performance.sql
│   ├── 05_top_n_per_group.sql
│   ├── 06_customer_ltv.sql
│   ├── 07_churn_analysis.sql
│   ├── 08_yoy_growth.sql
│   ├── 09_running_totals_pareto.sql
│   └── 10_recursive_category_tree.sql
└── docs/
    └── ER_diagram.md
```

---

## Notes and assumptions

- Revenue is recognized at the order-item grain; cancelled orders are
  excluded from revenue but kept for funnel/cancellation analysis.
- Returns are modeled one per line item (no partial-quantity returns).
- The dataset is synthetic and seeded for reproducibility — it is not real
  customer data.
