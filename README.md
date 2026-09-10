# E-commerce Analytics with PostgreSQL

An end-to-end SQL analytics project on a simulated online retailer: a normalized
schema, a procedurally-generated dataset (~5K customers, ~14K orders, ~57K line
items over 3 years), and **10 analytical queries** answering the kinds of
questions a data analyst gets asked on the job — revenue trends, customer
segmentation, cohort retention, churn, lifetime value, and product performance.

Every query in this repo has been executed against **PostgreSQL 16** and the
outputs below are real results from the generated data.

### 🔴 [Live interactive dashboard →](https://sql-ecommerce-dashboard.vercel.app)

Charts of every analysis **plus a live SQL playground** — a full PostgreSQL
database runs in your browser (via PGlite/WASM) so you can run the queries
yourself. No setup, nothing sent to a server.

> **Why this project?** It's built to show breadth of practical SQL — not just
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
| **Recursive** CTE (hierarchy traversal + roll-up) | [`analysis/10`](analysis/10_recursive_category_tree.sql) |
| Conditional aggregation (`FILTER`, `CASE`) | analyses 01, 03, 08 |
| `PERCENTILE_CONT` (median / p90) | [`analysis/06`](analysis/06_customer_ltv.sql) |
| RFM customer segmentation | [`analysis/02`](analysis/02_customer_rfm_segmentation.sql) |
| Cohort retention analysis | [`analysis/03`](analysis/03_cohort_retention.sql) |
| Views + **materialized view** | [`schema/03_views.sql`](schema/03_views.sql), [`functions/`](functions/rfm_segment_function.sql) |
| PL/pgSQL function | [`functions/rfm_segment_function.sql`](functions/rfm_segment_function.sql) |
| Reproducible synthetic data generation (`generate_series`, `setseed`) | [`data/`](data/) |

---

## Dataset

A simulated retailer selling Electronics, Home & Kitchen, Apparel, and Books
across 21 cities. Generated deterministically (seeded RNG) so anyone who runs it
gets identical numbers.

| Table | Rows | Description |
|---|---:|---|
| `customers` | 5,000 | signup date, location, acquisition channel |
| `orders` | ~14,200 | order header (status, payment method) |
| `order_items` | ~56,800 | **fact grain** — one row per product per order |
| `products` | 400 | catalog across a 3-level category tree |
| `categories` | 22 | self-referential hierarchy |
| `returns` | ~4,700 | line-item returns with reasons |
| `campaigns` | 11 | marketing spend by channel |

Behavioral patterns baked into the data so the analyses surface something:
- **Growth** — the customer base and revenue grow year over year.
- **Seasonality** — November/December run ~2× the monthly baseline.
- **Churn** — ~60% of customers are one-and-done; a ~5% VIP tier drives outsized revenue.
- **Returns** — higher for Electronics & Apparel (~12%) than other departments (~5%).

See [`docs/ER_diagram.md`](docs/ER_diagram.md) for the full entity-relationship diagram.

---

## Quick start

**Option A — Docker (no local Postgres needed):**

```bash
# 1. start a throwaway Postgres
docker run -d --name pg -e POSTGRES_PASSWORD=pw -e POSTGRES_DB=ecommerce_analytics -p 5432:5432 postgres:16

# 2. load schema + data + views/functions (one shot)
docker cp . pg:/work
docker exec -w /work pg psql -U postgres -d ecommerce_analytics -f run_all.sql

# 3. run any analysis
docker exec -w /work pg psql -U postgres -d ecommerce_analytics -f analysis/03_cohort_retention.sql
```

**Option B — local psql:**

```bash
createdb ecommerce_analytics
psql -d ecommerce_analytics -f run_all.sql
psql -d ecommerce_analytics -f analysis/02_customer_rfm_segmentation.sql
```

All objects live in a `shop` schema. In an interactive session run
`SET search_path TO shop;` first.

---

## The analyses

### 01 · Revenue overview &nbsp;·&nbsp; [`analysis/01_revenue_overview.sql`](analysis/01_revenue_overview.sql)
Monthly gross/net/realized revenue, return rate, gross margin, and a 3-month
moving average. *Techniques: conditional aggregation, `AVG() OVER` window, `LAG`
for YoY deltas.* The holiday spike is unmistakable:

```
  month  | net_revenue | returned_rev | orders | active_customers
---------+-------------+--------------+--------+------------------
 2024-10 | 2,901,828   | 209,708      |    468 |              422
 2024-11 | 5,690,311   | 450,680      |    950 |              466   <- Black Friday
 2024-12 | 6,139,069   | 496,408      |   1027 |              496   <- December
```

### 02 · RFM customer segmentation &nbsp;·&nbsp; [`analysis/02_customer_rfm_segmentation.sql`](analysis/02_customer_rfm_segmentation.sql)
Scores every customer 1–5 on **R**ecency, **F**requency, **M**onetary using
`NTILE(5)`, then buckets them into actionable segments. The headline: ~19% of
buyers ("Champions") drive ~41% of revenue.

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

### 03 · Cohort retention &nbsp;·&nbsp; [`analysis/03_cohort_retention.sql`](analysis/03_cohort_retention.sql)
The classic retention triangle: of customers who first ordered in month *X*, what
% came back *N* months later? *Techniques: first-order self-join, month
arithmetic, pivot via `FILTER`.*

```
 cohort_month | cohort_size |  m0   |  m1  |  m2  |  m3  |  m6  | m12
--------------+-------------+-------+------+------+------+------+-----
 2022-01-01   |          26 | 100.0 | 23.1 | 15.4 | 19.2 | 11.5 | 7.7
 2022-04-01   |          70 | 100.0 | 27.1 | 18.6 | 15.7 | 18.6 | 5.7
```

### 04 · Product performance &nbsp;·&nbsp; [`analysis/04_product_performance.sql`](analysis/04_product_performance.sql)
Ranks products and flags the **top & bottom 10% within each category** using
`PERCENT_RANK()`, including a `LEFT JOIN` so zero-sales products aren't lost.

### 05 · Top-N per group &nbsp;·&nbsp; [`analysis/05_top_n_per_group.sql`](analysis/05_top_n_per_group.sql)
The canonical "best-selling product per category per year" — solved with
`ROW_NUMBER() OVER (PARTITION BY year, category ORDER BY revenue DESC)`.

### 06 · Customer lifetime value &nbsp;·&nbsp; [`analysis/06_customer_ltv.sql`](analysis/06_customer_ltv.sql)
Average order value, days between purchases (`LAG`), and LTV distribution
(`PERCENTILE_CONT` for median & p90) **by acquisition channel** — directly
useful for deciding where to spend marketing dollars.

```
 acquisition_channel | customers | avg_ltv  | avg_order_value | median_ltv | p90_ltv
---------------------+-----------+----------+-----------------+------------+----------
 display             |       434 | 20098.36 |         6093.37 |   13926.06 | 41949.57
 social              |       316 | 16501.25 |         6219.48 |    8266.21 | 38504.37
 referral            |      3731 | 16253.09 |         6074.93 |    9322.43 | 35644.20
```

### 07 · Churn analysis &nbsp;·&nbsp; [`analysis/07_churn_analysis.sql`](analysis/07_churn_analysis.sql)
Quarter-over-quarter churn rate (did an active customer come back next quarter?),
joined against marketing spend to eyeball whether spend moves the needle.

### 08 · Year-over-year growth &nbsp;·&nbsp; [`analysis/08_yoy_growth.sql`](analysis/08_yoy_growth.sql)
Revenue by category by year, pivoted wide with `FILTER`, with YoY % columns and
`NULLIF` guards against divide-by-zero.

### 09 · Pareto / ABC analysis &nbsp;·&nbsp; [`analysis/09_running_totals_pareto.sql`](analysis/09_running_totals_pareto.sql)
Tests the 80/20 rule with a cumulative running total (`SUM() OVER (ORDER BY
revenue DESC)`) and classifies every product A/B/C.

### 10 · Recursive category tree &nbsp;·&nbsp; [`analysis/10_recursive_category_tree.sql`](analysis/10_recursive_category_tree.sql)
A **`WITH RECURSIVE`** walk down the category hierarchy that builds the full path
(`Electronics > Computers > Laptops`) and rolls leaf revenue up to each ancestor.

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
├── run_all.sql                 # one-shot build: schema -> data -> views/functions
├── schema/
│   ├── 01_create_tables.sql    # tables, PK/FK, CHECK constraints
│   ├── 02_indexes.sql          # indexes for the analytical workload
│   └── 03_views.sql            # reusable revenue views
├── data/
│   ├── 01_seed_reference_data.sql   # categories, products, campaigns
│   └── 02_seed_transactions.sql     # procedurally generated customers/orders/...
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

## Notes & assumptions

- Revenue is recognized at the **order-item grain**; `cancelled` orders are
  excluded from revenue but kept for funnel/cancellation analysis.
- Returns are modeled one-per-line (no partial-quantity returns).
- The dataset is synthetic and seeded for reproducibility — it is **not** real
  customer data.


