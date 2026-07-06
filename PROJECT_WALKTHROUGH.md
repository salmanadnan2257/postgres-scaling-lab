# PostgreSQL Scaling Project: End-to-End Walkthrough

## A. Project Overview
This project demonstrates advanced PostgreSQL scaling techniques to optimize database performance for high-load scenarios. The goal was to extract maximum performance from an RDBMS before considering a migration to NoSQL.

**Key Objectives:**
1.  **Optimize Slow Queries:** Using B-tree and GIN indexes.
2.  **Manage Time-Series Data:** Using Table Partitioning.
3.  **Scale Read Throughput:** Using Read Replicas and Load Balancing.

---

## B. Task Breakdown

### Part 1: Indexing
- **Goal:** Identify slow queries from logs and speed them up.
- **Scenario:** A user/order system with 100k users and 500k orders.
- **Technique:** `EXPLAIN ANALYZE` analysis and targeted indexing.

### Part 2: Partitioning
- **Goal:** Optimize performance for a large time-series dataset.
- **Scenario:** An event logging system with millions of records.
- **Technique:** Range partitioning (Monthly/Weekly) to reduce I/O.

### Part 3: Read Replicas
- **Goal:** Distribute read traffic to prevent primary bottleneck.
- **Scenario:** High read/write ratio application.
- **Technique:** Async streaming replication with 1 Primary and 2 Replicas.

---

## C. Execution Guide

### Prerequisites
- Docker & Docker Compose
- Python 3.x
- `psql` client (optional but recommended)

### Step-by-Step Execution

#### Part 1: Indexing
1.  **Navigate to directory:** `cd part_1`
2.  **Start services:** `docker compose up -d` (Starts DB on port 5433)
3.  **Generate load:** The `load_tester` container runs automatically.
4.  **Analyze logs:** `docker compose logs db > db_logs.txt`
5.  **Apply indexes:** `docker compose exec -T db psql -U postgres -d indexing_demo < solution.sql`
6.  **Verify:** Check logs again to see reduced execution times.
7.  **Cleanup:** `docker compose down`

#### Part 2: Partitioning
1.  **Navigate to directory:** `cd part_2`
2.  **Start services:** `docker compose up -d` (Starts DB on port 5435)
3.  **Run baseline:** run the four benchmark queries from `part_2/README.md` with `EXPLAIN (ANALYZE, BUFFERS)` against the `events` table and note the timings.
4.  **Partition & Migrate:** `docker compose exec -T db psql -U postgres -d events_db < solution.sql`
5.  **Verify:** rerun the same benchmark queries against `events_partitioned` and compare.
6.  **Cleanup:** `docker compose down`

#### Part 3: Read Replicas
1.  **Navigate to directory:** `cd part_3`
2.  **Start cluster:** `docker compose up -d` (Primary: 5436, Replicas: 5437, 5438)
3.  **Setup Python env:**
    ```bash
    cd app
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
    ```
4.  **Run tests:** `pytest` (Verifies read/write splitting)
5.  **Cleanup:** `docker compose down`

---

## D. Architecture

### Part 1 & 2 (Single Node)
- **Database:** PostgreSQL 17.0
- **Configuration:** Tuned for logging (`log_min_duration_statement=5ms`, `auto_explain`).
- **Client:** Python load tester or SQL scripts.

### Part 3 (Cluster)
- **Primary Node (Port 5436):**
  - Accepts `INSERT`, `UPDATE`, `DELETE`.
  - Streams WAL (Write-Ahead Log) to replicas.
- **Replica Nodes (Ports 5437, 5438):**
  - Read-only (`SELECT` only).
  - Asynchronous replication from Primary.
- **Application Layer:**
  - Python `psycopg` adapter.
  - Logic to route writes to Primary and reads to random Replicas.

---

## E. Changes & Rationale

### Part 1: Indexing Decisions
- **`idx_users_email` (B-tree):** For exact/prefix email searches. Reduced time by 98%.
- **`idx_users_name_trgm` (GIN):** For `ILIKE '%pattern%'` searches. Standard B-tree cannot handle leading wildcards.
- **`idx_users_metadata_gin` (GIN):** For JSONB containment queries (`@>`).
- **`idx_orders_user_id`:** Crucial for joining `users` and `orders` tables.

### Part 2: Partitioning Strategy
- **Range Partitioning:** Best for time-series data.
- **Monthly Partitions (Historical):** Good balance of size for older data.
- **Weekly Partitions (Recent):** Smaller, "hotter" partitions for recent data to maximize cache hits.
- **Default Partition:** Catch-all for future data or outliers.

### Part 3: Replication Strategy
- **Async Replication:** Chosen for performance. Writes don't wait for replicas to acknowledge.
- **Random Load Balancing:** Simple, stateless distribution of read queries.
- **Replication Lag Handling:** Application must tolerate slight delays (eventual consistency).

---

## F. Implementation Details & Validation

### Part 1 Validation
- **Metric:** Query Execution Time.
- **Result:**
  - Email lookup: 35ms -> 0.5ms
  - Complex Join: 4500ms -> 1800ms
  - **Overall:** 70% reduction in slow queries.

### Part 2 Validation
- **Metric:** Buffer Usage (I/O).
- **Result:**
  - Monthly Analysis: 9154 blocks -> 975 blocks (90% reduction).
  - **Why?** Partition pruning allowed Postgres to skip scanning 11 months of data.

### Part 3 Validation
- **Metric:** Test Pass Rate & Replication State.
- **Result:**
  - `pg_stat_replication` shows 2 streaming replicas.
  - `pytest` passed 5/5 tests, confirming writes go to Primary and reads come from Replicas.

---

## G. End-to-End Verification (DIY)

To verify the entire project yourself, run this sequence:

```bash
# --- Part 1 ---
cd part_1
docker compose up -d
sleep 60 # Wait for logs
docker compose logs db | grep "duration" | head -n 5
# You should see slow queries
docker compose exec -T db psql -U postgres -d indexing_demo < solution.sql
sleep 30
docker compose logs db | grep "duration" | tail -n 5
# You should see faster times
docker compose down
cd ..

# --- Part 2 ---
cd part_2
docker compose up -d
sleep 5
docker compose exec -T db psql -U postgres -d events_db < solution.sql
# Check partition sizes
docker compose exec -T db psql -U postgres -d events_db -c "SELECT relname, pg_size_pretty(pg_relation_size(oid)) FROM pg_class WHERE relname LIKE 'events_2%';"
docker compose down
cd ..

# --- Part 3 ---
cd part_3
docker compose up -d
sleep 10
# Check replication
docker compose exec primary psql -U postgres -c "SELECT * FROM pg_stat_replication;"
# Run app tests
cd app
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
pytest
cd ../..
```
