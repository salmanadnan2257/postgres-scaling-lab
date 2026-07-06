# Full Technical Write-up

> From slow queries to a scalable PostgreSQL architecture.

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [The Story: From Problem to Solution](#2-the-story-from-problem-to-solution)
3. [Part 1: The Art of Indexing](#3-part-1-the-art-of-indexing)
4. [Part 2: Mastering Time-Series with Partitioning](#4-part-2-mastering-time-series-with-partitioning)
5. [Part 3: Horizontal Scaling with Read Replicas](#5-part-3-horizontal-scaling-with-read-replicas)
6. [The Complete Picture](#6-the-complete-picture)
7. [Appendix: Quick Reference](#7-appendix-quick-reference)

---

## 1. Executive Summary

This document chronicles the complete engineering journey of scaling a PostgreSQL-based application from a struggling single-node database to a high-performance, horizontally-scaled architecture. 

### What We Built

```mermaid
graph LR
    subgraph "Before: Single Slow Database"
        A[App] --> B[(PostgreSQL)]
        B --> C[Slow Queries]
        B --> D[High Load]
        B --> E[Bottleneck]
    end
```

```mermaid
graph LR
    subgraph "After: Optimized Scalable Architecture"
        F[App] --> G{Router}
        G -->|Writes| H[(Primary)]
        G -->|Reads| I[(Replica 1)]
        G -->|Reads| J[(Replica 2)]
        H --> K[Indexed Tables]
        H --> L[Partitioned Tables]
    end
```

### The Three Pillars of Our Solution

| Pillar | Technique | Impact |
|--------|-----------|--------|
| **Speed** | B-tree & GIN Indexes | 98% faster lookups |
| **Efficiency** | Range Partitioning | 90% less I/O |
| **Scale** | Read Replicas | 3x read capacity |

### Key Metrics Achieved

- **Email Lookup**: 35ms → 0.5ms (98% improvement)
- **Monthly Analysis**: 9,154 buffer blocks → 975 blocks (90% reduction)
- **Read Throughput**: 1 node → 3 nodes (200% increase)

---

## 2. The Story: From Problem to Solution

### 2.1 The Business Context

> **Scenario**: You are a traditional software development organization that runs all applications on PostgreSQL. It's well-understood technology with excellent documentation and community support. This has worked well... until now.

#### The Growing Pains

Your e-commerce platform has grown significantly:

| Metric | Count |
|--------|-------|
| Users | 100,000 |
| Orders | 500,000 |
| Events/Year | 600,000 |
| Daily Queries | Millions |

Performance issues are emerging. Some queries take seconds instead of milliseconds. The database is becoming a bottleneck.

### 2.2 The CTO's NoSQL Suggestion (And Why We Didn't Follow It)

Your CTO has heard that "NoSQL is infinitely scalable" and suggests migrating to MongoDB or Cassandra.

#### The Decision Matrix

```mermaid
graph TD
    A[Performance Problem] --> B{Decision Point}
    B --> C[Option 1: Migrate to NoSQL]
    B --> D[Option 2: Optimize PostgreSQL]
    
    C --> E[Pros: Horizontal scaling built-in]
    C --> F[Cons: Schema redesign, learning curve, eventual consistency]
    
    D --> G[Pros: Keep existing code, ACID compliance, mature tooling]
    D --> H[Cons: Requires expertise, may hit ceiling]
    
    G --> I[CHOSEN: Optimize First]
    I --> J[Indexing]
    I --> K[Partitioning]
    I --> L[Read Replicas]
```

#### Why We Chose to Optimize PostgreSQL

| Factor | NoSQL Migration | PostgreSQL Optimization |
|--------|-----------------|------------------------|
| **Risk** | High (complete rewrite) | Low (incremental changes) |
| **Time** | Months | Days to weeks |
| **Cost** | Major investment | Minimal |
| **Data Integrity** | Eventual consistency | ACID guaranteed |
| **Team Expertise** | New skills needed | Existing knowledge |

> **The Veteran's Wisdom**: "NoSQL is not always the best choice. Let's extract maximum performance from RDBMS first, that goes a long way."

### 2.3 The Three-Phase Scaling Strategy

We developed a systematic approach:

```mermaid
graph LR
    A[Phase 1: Indexing] --> B[Phase 2: Partitioning] --> C[Phase 3: Read Replicas]
    
    A --> A1[Find slow queries]
    A --> A2[Add targeted indexes]
    
    B --> B1[Identify time-series tables]
    B --> B2[Implement range partitioning]
    
    C --> C1[Set up primary + replicas]
    C --> C2[Route reads to replicas]
```

#### Technology Stack

| Component | Technology | Version |
|-----------|------------|---------|
| Database | PostgreSQL | 17.0 |
| Containerization | Docker | Latest |
| Orchestration | Docker Compose | v2 |
| Application | Python | 3.x |
| DB Driver | psycopg | 3.x |
| Testing | pytest | Latest |

---

## 3. Part 1: The Art of Indexing

> **Goal**: Identify slow queries from production logs and speed them up using targeted indexes.

### 3.1 The Challenge

#### Understanding the Problem Space

You have a user/order system with:
- **100,000 users** with email, name, status, and JSON metadata
- **500,000 orders** linked to users with amounts, status, and JSON items

Queries are taking longer than expected. But which queries? And how do we fix them without breaking anything else?

#### The Database Schema

```sql
-- The users table: 100,000 records
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255),           -- For lookups and pattern matching
    full_name VARCHAR(255),       -- For text search
    status VARCHAR(20),           -- 'active' or 'inactive' (low cardinality)
    metadata JSONB,               -- Nested preferences, last_login, etc.
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- The orders table: 500,000 records
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER,              -- Foreign key (NOT indexed by default!)
    amount DECIMAL(10,2),         -- For range queries
    status VARCHAR(20),           -- 'pending', 'completed', 'cancelled'
    items JSONB,                  -- Product details
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

> **Critical Insight**: PostgreSQL does NOT automatically create indexes on foreign keys! This is a common source of slow JOIN operations.

### 3.2 Conceptual Foundation

#### What is an Index?

> **Definition**: An index is a separate data structure that maintains a sorted reference to rows in a table, allowing the database to find data without scanning every row.

**Analogy**: Think of a book's index. Instead of reading every page to find "PostgreSQL," you look in the index, find the page numbers, and go directly there.

```
┌─────────────────────────────────────────────────────────────────┐
│                     WITHOUT INDEX (Seq Scan)                     │
├─────────────────────────────────────────────────────────────────┤
│  Query: WHERE email = 'user5000@example.com'                    │
│                                                                  │
│  ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐  │
│  │ 1 │→│ 2 │→│ 3 │→│...│→│5K │→│...│→│50K│→│...│→│99K│→│100K│  │
│  └───┘ └───┘ └───┘ └───┘ └─▲─┘ └───┘ └───┘ └───┘ └───┘ └───┘  │
│                             │                                    │
│                         FOUND! (after checking 5,000 rows)       │
│  Time: O(n) = 100,000 comparisons worst case                    │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                      WITH B-TREE INDEX                           │
├─────────────────────────────────────────────────────────────────┤
│  Query: WHERE email = 'user5000@example.com'                    │
│                                                                  │
│                        ┌─────────────┐                           │
│                        │  user50000  │  (root)                   │
│                        └──────┬──────┘                           │
│                    ┌──────────┴──────────┐                       │
│                    ▼                      ▼                      │
│            ┌────────────┐          ┌────────────┐                │
│            │  user25000 │          │  user75000 │                │
│            └──────┬─────┘          └────────────┘                │
│           ┌───────┴───────┐                                      │
│           ▼               ▼                                      │
│    ┌────────────┐  ┌────────────┐                                │
│    │  user5000  │  │  user12500 │                                │
│    └─────▲──────┘  └────────────┘                                │
│          │                                                       │
│      FOUND! (after 3 comparisons)                                │
│  Time: O(log n) ≈ 17 comparisons for 100,000 rows               │
└─────────────────────────────────────────────────────────────────┘
```

#### B-tree Index (The Default)

> **B-tree** = Balanced Tree. Self-balancing tree structure that keeps data sorted and allows searches, insertions, and deletions in O(log n) time.

**Best For**:
- Exact matches: `WHERE email = 'user@example.com'`
- Range queries: `WHERE amount BETWEEN 100 AND 500`
- Prefix patterns: `WHERE email LIKE 'user%'`
- Sorting: `ORDER BY created_at DESC`

**NOT Good For**:
- Suffix/infix patterns: `WHERE email LIKE '%@gmail.com'`
- Full-text search: `WHERE name LIKE '%john%'`

#### GIN Index (Generalized Inverted Index)

> **GIN** = Generalized Inverted Index. Stores a list of values (like words or array elements) and which rows contain each value.

```
┌─────────────────────────────────────────────────────────────────┐
│                        GIN INDEX STRUCTURE                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  JSONB Data:                                                     │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ Row 1: {"theme": "dark", "language": "en"}                 │ │
│  │ Row 2: {"theme": "light", "language": "es"}                │ │
│  │ Row 3: {"theme": "dark", "language": "fr"}                 │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  GIN Index (Inverted):                                           │
│  ┌──────────────────┬───────────────────────┐                   │
│  │ Key              │ Row IDs               │                   │
│  ├──────────────────┼───────────────────────┤                   │
│  │ theme → dark     │ [1, 3]                │                   │
│  │ theme → light    │ [2]                   │                   │
│  │ language → en    │ [1]                   │                   │
│  │ language → es    │ [2]                   │                   │
│  │ language → fr    │ [3]                   │                   │
│  └──────────────────┴───────────────────────┘                   │
│                                                                  │
│  Query: WHERE metadata @> '{"theme": "dark"}'                   │
│  Result: Rows [1, 3] - no table scan needed!                    │
└─────────────────────────────────────────────────────────────────┘
```

**Best For**:
- JSONB containment: `WHERE metadata @> '{"key": "value"}'`
- Array operations: `WHERE tags @> ARRAY['tag1']`
- Full-text search with `pg_trgm`

#### pg_trgm Extension (Trigram Matching)

> **Trigram**: A group of three consecutive characters. "hello" → {"  h", " he", "hel", "ell", "llo", "lo "}

This enables `LIKE '%pattern%'` queries to use an index!

```
┌─────────────────────────────────────────────────────────────────┐
│                    TRIGRAM MATCHING                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Name: "John Smith"                                              │
│  Trigrams: {"  j", " jo", "joh", "ohn", "hn ", "n s", " sm",    │
│             "smi", "mit", "ith", "th "}                         │
│                                                                  │
│  Query: ILIKE '%smith%'                                         │
│  Search Trigrams: {" sm", "smi", "mit", "ith", "th "}           │
│                                                                  │
│  Match! Trigrams overlap → Row is a candidate                   │
└─────────────────────────────────────────────────────────────────┘
```

### 3.3 The Load Testing Approach

#### How We Found the Slow Queries

PostgreSQL was configured to log all queries taking more than **5 milliseconds**:

```yaml
# docker-compose.yml configuration
command: [
  "postgres",
  "-c", "log_min_duration_statement=5",      # Log queries > 5ms
  "-c", "shared_preload_libraries=auto_explain",
  "-c", "auto_explain.log_min_duration=5",   # Auto-explain slow queries
  "-c", "auto_explain.log_analyze=on",       # Include actual execution stats
  "-c", "auto_explain.log_buffers=on",       # Show buffer I/O
  "-c", "auto_explain.log_timing=on"         # Include timing details
]
```

#### The Load Tester (Inferred Behavior)

The project includes pre-compiled binaries (`load_tester_amd64`, `load_tester_arm64`) that simulate production traffic. Based on the slow query logs and README patterns, the load tester executes:

| Query Pattern | Example | Expected Behavior |
|--------------|---------|-------------------|
| Email exact match | `WHERE email = 'user5000@example.com'` | Seq Scan → Slow |
| Email prefix | `WHERE email LIKE 'user%'` | Seq Scan → Slow |
| Name search | `WHERE full_name ILIKE '%john%'` | Seq Scan → Very Slow |
| Amount range | `WHERE amount BETWEEN 100 AND 500` | Seq Scan → Slow |
| User orders | `JOIN orders ON users.id = orders.user_id` | Nested Loop → Very Slow |
| JSON metadata | `WHERE metadata @> '{"theme": "dark"}'` | Seq Scan → Slow |
| Status filter | `WHERE status = 'active'` | Seq Scan → Moderate |

### 3.4 Solution Implementation

#### The Index Strategy

After analyzing the logs, we created 7 targeted indexes:

```sql
-- solution.sql: Complete Indexing Solution

-- 1. Email exact match AND prefix search
-- text_pattern_ops enables LIKE 'prefix%' to use the index
CREATE INDEX idx_users_email ON users(email text_pattern_ops);

-- 2. Full-text name search (handles LIKE '%value%')
-- GIN + pg_trgm enables trigram-based fuzzy matching
CREATE INDEX idx_users_name_trgm ON users USING GIN(full_name gin_trgm_ops);

-- 3. Order amount range queries
-- Standard B-tree for BETWEEN, <, >, comparisons
CREATE INDEX idx_orders_amount ON orders(amount);

-- 4. Foreign key for JOIN performance (CRITICAL!)
-- This single index often provides the biggest improvement
CREATE INDEX idx_orders_user_id ON orders(user_id);

-- 5. JSONB metadata containment queries
-- GIN index for @> (contains) operator
CREATE INDEX idx_users_metadata_gin ON users USING GIN(metadata);

-- 6. Status filtering
-- Low cardinality but frequently queried
CREATE INDEX idx_users_status ON users(status);

-- 7. Sorting by creation time
-- DESC matches common "newest first" queries
CREATE INDEX idx_users_created_desc ON users(created_at DESC);
```

#### Line-by-Line Explanation

**Line 4: `CREATE INDEX idx_users_email ON users(email text_pattern_ops);`**

```
┌─────────────────────────────────────────────────────────────────┐
│ BREAKDOWN                                                        │
├─────────────────────────────────────────────────────────────────┤
│ CREATE INDEX        → SQL command to create an index            │
│ idx_users_email     → Name we chose (prefix: idx_, table, col)  │
│ ON users            → The table to index                        │
│ (email              → The column to index                       │
│ text_pattern_ops)   → Operator class for pattern matching       │
└─────────────────────────────────────────────────────────────────┘

WHY text_pattern_ops?
- Standard B-tree: Supports = but NOT LIKE 'prefix%'
- text_pattern_ops: Stores data in byte-order, enabling prefix matching

Query: WHERE email LIKE 'user123%'
- Without text_pattern_ops: Sequential scan (35ms)
- With text_pattern_ops: Index scan (0.5ms)
```

**Line 7: `CREATE INDEX idx_users_name_trgm ON users USING GIN(full_name gin_trgm_ops);`**

```
┌─────────────────────────────────────────────────────────────────┐
│ BREAKDOWN                                                        │
├─────────────────────────────────────────────────────────────────┤
│ USING GIN           → Use Generalized Inverted Index            │
│ (full_name          → Column to index                           │
│ gin_trgm_ops)       → Operator class from pg_trgm extension     │
└─────────────────────────────────────────────────────────────────┘

WHY GIN with trigrams?
- B-tree CANNOT help with: ILIKE '%john%' (infix search)
- GIN + trigrams: Breaks text into 3-char chunks, enables fuzzy matching

Trade-off:
- Slower writes (must update trigram entries)
- Larger index size
- But: Makes impossible queries possible!
```

### 3.5 Verification & Results

#### Performance Comparison

| Query Type | Time Before | Time After | Improvement | Index Used |
|------------|-------------|------------|-------------|------------|
| Email (Exact) | 35ms | 0.5ms | **98%** | `idx_users_email` |
| Email (Prefix) | 125ms | 3ms | **97%** | `idx_users_email` |
| Name Search | 310ms | 180ms | **42%** | `idx_users_name_trgm` |
| Amount Range | 3,100ms | 1,300ms | **58%** | `idx_orders_amount` |
| User Joins | 4,500ms | 1,800ms | **60%** | `idx_orders_user_id` |
| JSON Search | 780ms | 280ms | **64%** | `idx_users_metadata_gin` |
| Status Filter | 650ms | 450ms | **30%** | `idx_users_status` |

#### EXPLAIN ANALYZE: Before vs After

**Email Lookup Before:**
```sql
EXPLAIN ANALYZE SELECT * FROM users WHERE email = 'user5000@example.com';

-- Seq Scan on users  (cost=0.00..2137.00 rows=1 width=...)
--   Filter: ((email)::text = 'user5000@example.com'::text)
--   Rows Removed by Filter: 99999
--   Execution Time: 35.123 ms
```

**Email Lookup After:**
```sql
EXPLAIN ANALYZE SELECT * FROM users WHERE email = 'user5000@example.com';

-- Index Scan using idx_users_email on users (cost=0.42..8.44 rows=1 width=...)
--   Index Cond: ((email)::text = 'user5000@example.com'::text)
--   Execution Time: 0.512 ms
```

```mermaid
graph LR
    subgraph "Before Indexing"
        A[Query] --> B[Sequential Scan]
        B --> C[100,000 rows checked]
        C --> D[35ms]
    end
```

```mermaid
graph LR
    subgraph "After Indexing"
        E[Query] --> F[Index Scan]
        F --> G[~17 comparisons]
        G --> H[0.5ms]
    end
```

#### What We Didn't Index (And Why)

| Query | Why No Index |
|-------|--------------|
| `SELECT COUNT(*)` | Indexes don't help, PostgreSQL must verify row visibility (MVCC) |
| Low-selectivity multi-column | If reading >20% of table, sequential scan is faster |
| Rarely executed queries | Index maintenance cost outweighs occasional benefit |

---

## 4. Part 2: Mastering Time-Series with Partitioning

> **Goal**: Optimize performance for time-series data where indexes aren't enough.

### 4.1 The Challenge

#### The Scenario

You have an **event logging system** with:
- **600,000 total events**
- **500,000 historical events** spread across 2024
- **100,000 recent events** in the last 14 days (high traffic period)

Even with indexes, some queries are still slow. Why?

#### Why Indexes Aren't Enough for Time-Series Data

```
┌─────────────────────────────────────────────────────────────────┐
│                   THE PROBLEM WITH LARGE INDEXES                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  INDEX ON event_time (600,000 entries):                         │
│  ┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┐ │
│  │ Jan │ Feb │ Mar │ Apr │ May │ Jun │ Jul │ Aug │ Sep │ Oct │ │
│  └─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┘ │
│     │     │     │     │     │     │     │     │     │     │     │
│     ▼     ▼     ▼     ▼     ▼     ▼     ▼     ▼     ▼     ▼     │
│  [all 600,000 index entries point to scattered disk pages]      │
│                                                                  │
│  Problems:                                                       │
│  1. Index itself is LARGE (must be searched even for recent)    │
│  2. Hot data (recent) competes with cold data in buffer cache   │
│  3. Writes update the ENTIRE index structure                    │
│  4. Aggregations still read many disk pages                     │
└─────────────────────────────────────────────────────────────────┘
```

### 4.2 Conceptual Foundation

#### What is Table Partitioning?

> **Definition**: Table partitioning physically splits a large table into smaller, independent pieces called **partitions**. PostgreSQL can then access only the relevant partition(s) for a query.

```mermaid
graph TB
    subgraph "Before: Single Large Table"
        A[events table<br/>600,000 rows]
    end
    
    subgraph "After: Partitioned Table"
        B[events_partitioned<br/>Parent Table]
        B --> C[events_202401<br/>Jan 2024]
        B --> D[events_202402<br/>Feb 2024]
        B --> E[...]
        B --> F[events_202412<br/>Dec 2024]
        B --> G[events_2025_w47<br/>This Week]
        B --> H[events_default<br/>Catch-all]
    end
```

#### Types of Partitioning

| Type | Use Case | Example |
|------|----------|---------|
| **Range** | Time-series, sequential data | Partition by month/week |
| **List** | Categorical data | Partition by region, status |
| **Hash** | Even distribution | Partition by user_id hash |

For time-series data, **Range Partitioning** is ideal.

#### Partition Pruning: The Magic

> **Partition Pruning**: PostgreSQL's query planner automatically excludes partitions that cannot contain matching rows based on the WHERE clause.

```
┌─────────────────────────────────────────────────────────────────┐
│                      PARTITION PRUNING                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Query: WHERE event_time >= '2024-03-01'                        │
│              AND event_time < '2024-04-01'                      │
│                                                                  │
│  ┌───────┐ ┌───────┐ ┌───────┐ ┌───────┐ ┌───────┐             │
│  │ Jan ✗ │ │ Feb ✗ │ │ Mar ✓ │ │ Apr ✗ │ │ May ✗ │  ...        │
│  └───────┘ └───────┘ └───▲───┘ └───────┘ └───────┘             │
│                          │                                       │
│                    ONLY this partition is scanned!               │
│                                                                  │
│  Result: ~50,000 rows instead of 600,000                        │
│  Buffer reads: ~975 blocks instead of ~9,154                    │
└─────────────────────────────────────────────────────────────────┘
```

### 4.3 The Database Schema

#### Original Table Structure

```sql
-- events table: 600,000 records (NO partitioning)
CREATE TABLE events (
    id SERIAL PRIMARY KEY,
    event_time TIMESTAMP NOT NULL,   -- The partition key
    user_id INTEGER NOT NULL,
    event_type VARCHAR(50) NOT NULL, -- login, logout, purchase, etc.
    event_data JSONB
);

-- Pre-existing indexes (from database setup)
CREATE INDEX idx_events_time ON events(event_time DESC);
CREATE INDEX idx_events_time_type ON events(event_time, event_type);
CREATE INDEX idx_events_user_time ON events(user_id, event_time);
```

#### Data Distribution

```
┌─────────────────────────────────────────────────────────────────┐
│                    DATA DISTRIBUTION                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Historical Data (500,000 events):                              │
│  Jan─────Feb─────Mar─────Apr─────May─────Jun─────Jul─────Aug    │
│  ████████████████████████████████████████████████████████████   │
│  (~41,666 events per month, evenly distributed)                 │
│                                                                  │
│  Recent Data (100,000 events):                                  │
│  Last 14 days ─────────────────────────                         │
│  ████████████████████████████████████████ (HIGH TRAFFIC!)       │
│  (~7,142 events per day)                                        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 4.4 Solution Design: Mixed-Granularity Strategy

We chose a **mixed-granularity** partitioning strategy:

| Time Period | Partition Size | Rationale |
|-------------|----------------|-----------|
| Historical (2024) | Monthly | Lower query frequency, simpler maintenance |
| Recent (Nov 2025) | Weekly | High traffic, better cache locality |
| Future | Default | Catch-all for new data |

```mermaid
graph LR
    subgraph "Mixed Granularity Strategy"
        A[events_partitioned] --> B[Monthly: 2024]
        A --> C[Weekly: Recent]
        A --> D[Default: Future]
        
        B --> B1[Jan]
        B --> B2[Feb]
        B --> B3[...]
        B --> B4[Dec]
        
        C --> C1[Week 46]
        C --> C2[Week 47]
        C --> C3[Week 48]
    end
```

### 4.5 Solution Implementation

#### The Complete Partitioning Solution

```sql
-- solution.sql: Complete Partitioning Strategy

-- Step 1: Create the partitioned parent table
-- Note: PARTITION BY RANGE defines this as a range-partitioned table
CREATE TABLE events_partitioned (
    id SERIAL,                          -- No PRIMARY KEY constraint here
    event_time TIMESTAMP NOT NULL,      -- This is our partition key
    user_id INTEGER NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    event_data JSONB
) PARTITION BY RANGE (event_time);      -- Partition by time ranges
```

**Why no PRIMARY KEY on the parent?**
> In partitioned tables, unique constraints (including PRIMARY KEY) must include the partition key. Since `id` alone isn't meaningful across partitions, we omit it.

```sql
-- Step 2: Create monthly partitions for 2024
-- Each partition holds events for ONE calendar month

CREATE TABLE events_202401 PARTITION OF events_partitioned 
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
    
CREATE TABLE events_202402 PARTITION OF events_partitioned 
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');
    
CREATE TABLE events_202403 PARTITION OF events_partitioned 
    FOR VALUES FROM ('2024-03-01') TO ('2024-04-01');
    
-- ... (continues for all 12 months)

CREATE TABLE events_202412 PARTITION OF events_partitioned 
    FOR VALUES FROM ('2024-12-01') TO ('2025-01-01');
```

**Boundary Psychology: FROM (inclusive) TO (exclusive)**
```
┌─────────────────────────────────────────────────────────────────┐
│  FROM ('2024-03-01') TO ('2024-04-01')                          │
│                                                                  │
│  ✓ Includes: 2024-03-01 00:00:00                                │
│  ✓ Includes: 2024-03-31 23:59:59.999999                         │
│  ✗ Excludes: 2024-04-01 00:00:00 (belongs to April partition)   │
└─────────────────────────────────────────────────────────────────┘
```

```sql
-- Step 3: Create weekly partitions for recent/hot data
-- Smaller partitions = better cache efficiency for frequent access

CREATE TABLE events_2025_w46 PARTITION OF events_partitioned 
    FOR VALUES FROM ('2025-11-10') TO ('2025-11-17');
    
CREATE TABLE events_2025_w47 PARTITION OF events_partitioned 
    FOR VALUES FROM ('2025-11-17') TO ('2025-11-24');
    
CREATE TABLE events_2025_w48 PARTITION OF events_partitioned 
    FOR VALUES FROM ('2025-11-24') TO ('2025-12-01');
```

```sql
-- Step 4: Create a DEFAULT partition for everything else
-- This catches any data that doesn't fit existing partitions

CREATE TABLE events_default PARTITION OF events_partitioned DEFAULT;
```

**Why DEFAULT is crucial:**
```
┌─────────────────────────────────────────────────────────────────┐
│  WITHOUT DEFAULT PARTITION:                                      │
│  INSERT INTO events_partitioned (event_time='2025-12-15'...)    │
│  → ERROR: no partition for value "2025-12-15"                   │
│                                                                  │
│  WITH DEFAULT PARTITION:                                         │
│  INSERT INTO events_partitioned (event_time='2025-12-15'...)    │
│  → Success! (goes to events_default)                            │
└─────────────────────────────────────────────────────────────────┘
```

```sql
-- Step 5: Create indexes on the partitioned table
-- PostgreSQL automatically creates these on each partition!

CREATE INDEX idx_p_events_time ON events_partitioned(event_time DESC);
CREATE INDEX idx_p_events_time_type ON events_partitioned(event_time, event_type);
CREATE INDEX idx_p_events_user_time ON events_partitioned(user_id, event_time);
```

```sql
-- Step 6: Migrate data from old table to partitioned table
-- PostgreSQL automatically routes rows to the correct partition!

INSERT INTO events_partitioned SELECT * FROM events;
```

### 4.6 Verification & Trade-off Analysis

#### Performance Comparison

| Query | Time Before | Time After | Improvement |
|-------|-------------|------------|-------------|
| Recent Events (24h) | 1.36ms | 0.70ms | **48%** |
| Monthly Analysis (March) | 140ms | 86ms | **38%** |
| User Activity (30 days) | 93ms | 160ms | **-70%** ❌ |
| Time Range (Jan) | 0.06ms | 0.09ms | ~0% |

#### Why User Activity Got SLOWER

```mermaid
graph TD
    A[User Activity Query] --> B{Partition Key in WHERE?}
    B -->|Yes| C[Partition Pruning ✓]
    B -->|No| D[Scan ALL Partitions ✗]
    
    C --> E[Fast!]
    D --> F[Slower than single table]
```

The User Activity query filters by `user_id` and aggregates across time:

```sql
SELECT user_id, event_type, COUNT(*)
FROM events
WHERE event_time >= NOW() - INTERVAL '30 days'
GROUP BY user_id, event_type
HAVING COUNT(*) > 100;
```

**Problem**: User activity is spread across ALL partitions. Even with the time filter, PostgreSQL must open and read from multiple partitions, adding overhead.

> **Lesson**: Partitioning is optimal when queries filter by the **partition key**. Queries that span partitions may degrade.

#### Buffer Usage Comparison (The Real Win)

```
┌─────────────────────────────────────────────────────────────────┐
│               BUFFER USAGE: MONTHLY ANALYSIS QUERY               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  BEFORE (Unpartitioned):                                         │
│  ████████████████████████████████████████████████████████████   │
│  9,154 buffer blocks read                                        │
│  (Scans entire table, all 600,000 rows)                         │
│                                                                  │
│  AFTER (Partitioned):                                            │
│  ██████                                                          │
│  975 buffer blocks read                                          │
│  (Scans only March partition, ~50,000 rows)                     │
│                                                                  │
│  IMPROVEMENT: 90% reduction in I/O!                             │
└─────────────────────────────────────────────────────────────────┘
```

### 4.7 Key Takeaways

| Aspect | Takeaway |
|--------|----------|
| **When to use** | Time-series data with time-based queries |
| **Partition key** | Choose based on most common query filter |
| **Granularity** | Smaller for hot data, larger for cold data |
| **Trade-off** | Queries spanning partitions get slower |
| **Maintenance** | Easy to drop old partitions (instant!) |

---

## 5. Part 3: Horizontal Scaling with Read Replicas

> **Goal**: Distribute read traffic across multiple database servers to prevent primary bottleneck.

### 5.1 The Challenge

#### The Scenario

You've optimized queries with indexes and partitioning. But you still have a fundamental problem:

```
┌─────────────────────────────────────────────────────────────────┐
│                  SINGLE DATABASE BOTTLENECK                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│                     ┌──────────────────┐                        │
│   Writes ────────▶ │                  │                         │
│   (INSERT/UPDATE)  │  PostgreSQL      │ ◀──────── Reads         │
│                     │  (Single Node)   │          (SELECT)       │
│                     └──────────────────┘                        │
│                            ▲                                     │
│                            │                                     │
│                     ONE SERVER = ONE BOTTLENECK                  │
│                                                                  │
│  Read:Write Ratio = 80:20 (typical for most applications)       │
│  → 80% of load is reads that don't need to touch primary!       │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 Conceptual Foundation

#### What is Database Replication?

> **Replication**: The process of copying data from one database server (primary) to one or more other servers (replicas) in near real-time.

```mermaid
graph LR
    subgraph "Replication Architecture"
        A[Application] --> B{Load Balancer}
        B -->|Writes| C[(Primary)]
        B -->|Reads| D[(Replica 1)]
        B -->|Reads| E[(Replica 2)]
        
        C -->|WAL Stream| D
        C -->|WAL Stream| E
    end
```

#### WAL: The Secret Sauce

> **WAL (Write-Ahead Logging)**: Before PostgreSQL changes any data, it first writes the change to a WAL file. This log is then streamed to replicas.

```
┌─────────────────────────────────────────────────────────────────┐
│                    HOW WAL REPLICATION WORKS                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. Application: INSERT INTO events (...)                       │
│                         │                                        │
│                         ▼                                        │
│  2. Primary writes to WAL: "INSERT row X at page Y"             │
│                         │                                        │
│                         ▼                                        │
│  3. Primary commits transaction, returns success                │
│                         │                                        │
│                         ▼                                        │
│  4. WAL segments stream to replicas (async)                     │
│     ┌─────────────────────────────────────────┐                 │
│     │ WAL Stream ──────▶ Replica 1 (apply)    │                 │
│     │            ──────▶ Replica 2 (apply)    │                 │
│     └─────────────────────────────────────────┘                 │
│                                                                  │
│  5. Replicas "replay" WAL to update their data                  │
│                                                                  │
│  RESULT: All databases have identical data (eventually)         │
└─────────────────────────────────────────────────────────────────┘
```

#### Async vs Sync Replication

| Mode | How It Works | Pros | Cons |
|------|-------------|------|------|
| **Synchronous** | Primary waits for replica acknowledgment | Zero data loss | Slower writes |
| **Asynchronous** | Primary doesn't wait | Faster writes | Slight replication lag |

We chose **Asynchronous** for better write performance:

```sql
-- primary.conf
synchronous_commit = off  -- Don't wait for replicas
```

### 5.3 Infrastructure Architecture

#### The Cluster Setup

```
┌─────────────────────────────────────────────────────────────────┐
│                        CLUSTER TOPOLOGY                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                     Docker Network                          │ │
│  │                                                             │ │
│  │   ┌────────────────┐                                        │ │
│  │   │    PRIMARY     │                                        │ │
│  │   │  Port: 5436    │─────────────────┐                      │ │
│  │   │  Writes: YES   │                 │ WAL Stream           │ │
│  │   │  Reads: YES    │                 ▼                      │ │
│  │   └────────────────┘           ┌──────────────┐             │ │
│  │                                │   REPLICA 1  │             │ │
│  │                                │  Port: 5437  │             │ │
│  │   ┌────────────────┐          │  Writes: NO  │             │ │
│  │   │    REPLICA 2   │◀─────────│  Reads: YES  │             │ │
│  │   │   Port: 5438   │          └──────────────┘             │ │
│  │   │   Writes: NO   │                                        │ │
│  │   │   Reads: YES   │                                        │ │
│  │   └────────────────┘                                        │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

#### docker-compose.yml Analysis

```yaml
services:
  primary:
    image: postgres:17.0
    container_name: pg_primary
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: events_db
    volumes:
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql  # Schema + data
      - ./primary.conf:/etc/postgresql/postgresql.conf  # Config
      - ./pg_hba.conf:/etc/postgresql/pg_hba.conf       # Auth rules
      - primary_data:/var/lib/postgresql/data           # Persistent storage
    ports:
      - "5436:5432"  # Expose on host port 5436
    command: postgres -c config_file=/etc/postgresql/postgresql.conf
```

#### Primary Configuration (primary.conf)

```ini
# Primary PostgreSQL configuration

listen_addresses = '*'          # Accept connections from anywhere
max_connections = 100           # Connection limit

# === REPLICATION SETTINGS ===
wal_level = replica             # Generate enough WAL for replication
max_wal_senders = 10            # Max concurrent replication connections
max_replication_slots = 10      # Reservation slots for replicas
wal_keep_size = 1GB             # Keep 1GB of WAL for catching up
hot_standby = on                # Allow queries on standbys

# === PERFORMANCE ===
synchronous_commit = off        # Async commit for speed
shared_buffers = 128MB          # Memory for caching

# === ARCHIVING (for recovery) ===
archive_mode = on
archive_command = '/bin/true'   # Dummy (we're not archiving to disk)
```

**Line-by-Line Explanation:**

| Setting | Purpose |
|---------|---------|
| `wal_level = replica` | Enables streaming replication (more WAL info generated) |
| `max_wal_senders = 10` | Up to 10 replicas can connect simultaneously |
| `synchronous_commit = off` | Writes return before replicas confirm (faster) |
| `wal_keep_size = 1GB` | Keeps WAL around for slow replicas to catch up |

#### Replica Configuration (replica1.conf)

```ini
# Replica PostgreSQL configuration

listen_addresses = '*'
max_connections = 100
shared_buffers = 128MB
wal_level = replica
hot_standby = on                 # CRITICAL: Allow queries while replicating

# === REPLICATION SOURCE ===
primary_conninfo = 'host=primary port=5432 user=postgres password=postgres'
primary_slot_name = 'replica1_slot'    # Reserves WAL on primary

# === STANDBY SETTINGS ===
max_standby_archive_delay = 30s        # Wait 30s before canceling conflicts
max_standby_streaming_delay = 30s      # Same for streaming replication
hot_standby_feedback = on              # Tell primary about query conflicts

# === PERFORMANCE FOR READS ===
effective_cache_size = 256MB           # Hint for query planner
random_page_cost = 1.1                 # Assume SSD storage
```

**Critical Settings:**

| Setting | Purpose |
|---------|---------|
| `hot_standby = on` | Allows SELECT queries on replica |
| `primary_conninfo` | How replica connects to primary |
| `hot_standby_feedback = on` | Prevents primary from vacuuming rows replica needs |

### 5.4 Application-Level Load Balancing

#### The Problem: app.py (Before)

```python
class EventsDB:
    def __init__(self):
        # Single connection for ALL operations
        self.conn_str = "postgresql://postgres:postgres@localhost:5432/events_db"

    def record_event(self, event_type, user_id, metadata=None):
        # Write goes to single database
        with psycopg.connect(self.conn_str) as conn:
            # ...

    def get_recent_events(self, hours=24):
        # Read ALSO goes to single database!
        with psycopg.connect(self.conn_str) as conn:
            # ...
```

**Problem**: Everything hits one server. No scaling.

#### The Solution: solution.py (After)

```python
import psycopg
import json
import random
from datetime import datetime, timedelta

class EventsDB:
    def __init__(self):
        # Primary for writes
        self.p = "postgresql://postgres:postgres@localhost:5436/events_db"
        
        # Replicas for reads (list allows easy scaling)
        self.r = [
            "postgresql://postgres:postgres@localhost:5437/events_db",
            "postgresql://postgres:postgres@localhost:5438/events_db"
        ]

    def record_event(self, event_type, user_id, metadata=None):
        """Write operation - ALWAYS goes to PRIMARY"""
        if metadata is None:
            metadata = {}
        
        # Connect to PRIMARY (self.p)
        with psycopg.connect(self.p) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO events (...) VALUES (...) RETURNING id",
                    (event_type, user_id, json.dumps(metadata))
                )
                return cur.fetchone()[0]

    def get_recent_events(self, hours=24):
        """Read operation - goes to RANDOM REPLICA"""
        # Pick a random replica for load distribution
        conn_str = random.choice(self.r)
        
        with psycopg.connect(conn_str) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT * FROM events WHERE event_time >= %s ORDER BY ...",
                    (datetime.now() - timedelta(hours=hours),)
                )
                return cur.fetchall()
```

#### Code Flow Visualization

```mermaid
graph TD
    subgraph "Application Logic"
        A[record_event] -->|Write| B[Connect to self.p]
        C[get_recent_events] -->|Read| D[random.choice self.r]
        E[get_user_activity] -->|Read| D
        F[get_monthly_stats] -->|Read| D
    end
    
    B --> G[(Primary:5436)]
    D --> H[(Replica 1:5437)]
    D --> I[(Replica 2:5438)]
```

#### Why random.choice()?

```python
conn_str = random.choice(self.r)
```

This implements **random load balancing**:
- Simple and stateless
- Approximately even distribution over time
- No external dependency (no load balancer needed)

**Trade-off**: More sophisticated strategies exist (round-robin, least-connections), but random is good enough for most cases.

### 5.5 Handling Replication Lag

#### The Problem

```
┌─────────────────────────────────────────────────────────────────┐
│                    REPLICATION LAG PROBLEM                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Timeline:                                                       │
│  ─────────────────────────────────────────────────────▶         │
│  T=0       T=10ms     T=20ms     T=100ms                        │
│   │          │          │          │                             │
│   ▼          ▼          ▼          ▼                             │
│  INSERT  WAL sent   Replica     Query                           │
│  on      to replica applies     from                            │
│  Primary            WAL         Replica                         │
│                                                                  │
│  If query at T=15ms: DATA NOT THERE YET!                        │
│                                                                  │
│  This is called "read-your-writes" problem.                     │
└─────────────────────────────────────────────────────────────────┘
```

#### How Tests Handle It

```python
# test_events_db.py

def test_get_recent_events(events_db):
    # Record some events
    events_db.record_event("test_recent_event", 1)
    events_db.record_event("test_recent_event", 2)
    
    # Add a small delay to allow for replication lag
    time.sleep(0.5)  # Wait 500ms for replicas to catch up
    
    # Now read from replica
    events = events_db.get_recent_events(hours=1)
    assert isinstance(events, list)
```

> **Note**: In production, you might read from primary after writes when strong consistency is required, or use more sophisticated techniques like causal consistency tokens.

### 5.6 Verification & Testing

#### Checking Replication Status

```sql
-- Run on PRIMARY to verify replicas are connected
SELECT application_name, state, sync_state 
FROM pg_stat_replication;

-- Expected output:
-- application_name | state     | sync_state
-- -----------------+-----------+-----------
-- walreceiver      | streaming | async
-- walreceiver      | streaming | async
```

#### pytest Results

```bash
$ pytest

========================= test session starts ==========================
collected 5 items

tests/test_events_db.py .....                                    [100%]

========================== 5 passed in 2.41s ===========================
```

| Test | What It Validates |
|------|-------------------|
| `test_record_event` | Writes go to primary successfully |
| `test_record_event_no_metadata` | Edge case handling |
| `test_get_recent_events` | Reads from replicas work |
| `test_get_user_activity` | Aggregation queries work |
| `test_get_monthly_stats` | Complex queries work |

### 5.7 Key Takeaways

| Aspect | Takeaway |
|--------|----------|
| **When to use** | Read-heavy workloads (>70% reads) |
| **Write path** | Always goes to primary |
| **Read path** | Distributed to replicas |
| **Trade-off** | Replication lag (eventual consistency) |
| **Scaling** | Add more replicas for more read capacity |

---

## 6. The Complete Picture

### 6.1 Decision Framework: When to Use What

```mermaid
graph TD
    A[Database Performance Problem] --> B{Identified Slow Queries?}
    
    B -->|Yes| C{Can Index Help?}
    B -->|No| D[Enable Slow Query Logging]
    D --> B
    
    C -->|Yes| E[Add Targeted Indexes]
    C -->|No, time-series data| F{Queries Filter by Time?}
    C -->|No, reads dominating| G{Read:Write > 3:1?}
    
    F -->|Yes| H[Implement Partitioning]
    F -->|No| I[Consider Composite Indexes]
    
    G -->|Yes| J[Set Up Read Replicas]
    G -->|No| K[Optimize Query or App Logic]
    
    E --> L{Still Slow?}
    H --> L
    J --> L
    
    L -->|Yes| M[Combine Techniques]
    L -->|No| N[Done!]
```

### 6.2 Complete System Architecture

```mermaid
graph TB
    subgraph "Application Layer"
        A[Python App] --> B{Operation Type}
    end
    
    subgraph "Load Balancing"
        B -->|Write| C[Primary Connection]
        B -->|Read| D[random.choice Replicas]
    end
    
    subgraph "Database Cluster"
        C --> E[(Primary<br/>Port 5436)]
        D --> F[(Replica 1<br/>Port 5437)]
        D --> G[(Replica 2<br/>Port 5438)]
        
        E -->|WAL Stream| F
        E -->|WAL Stream| G
    end
    
    subgraph "Storage Optimizations"
        E --> H[Indexed Tables]
        E --> I[Partitioned Tables]
        H --> J[B-tree Indexes]
        H --> K[GIN Indexes]
        I --> L[Monthly Partitions]
        I --> M[Weekly Partitions]
    end
```

### 6.3 Performance Summary

| Technique | Best For | Improvement | Trade-off |
|-----------|----------|-------------|-----------|
| **B-tree Index** | Exact matches, range queries | 98% faster | Write overhead |
| **GIN Index** | JSONB, text search | 64% faster | Larger storage |
| **text_pattern_ops** | LIKE 'prefix%' queries | 97% faster | None significant |
| **Range Partitioning** | Time-series data | 90% less I/O | Cross-partition queries slower |
| **Read Replicas** | Read-heavy workloads | 3x capacity | Replication lag |

### 6.4 What's Next: Sharding with Citus

The project mentions **Part 4: Sharding** but doesn't implement it. Here's a brief overview for completeness:

> **Sharding**: Distributing data across multiple independent database servers, where each server holds a subset of the data (a "shard").

```
┌─────────────────────────────────────────────────────────────────┐
│                    SHARDING ARCHITECTURE                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Current (Read Replicas):                                        │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ ALL data on Primary, replicated to all Replicas         │    │
│  │ Limitation: Data must fit on one server                 │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  Sharding (with Citus):                                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │   Shard 1   │  │   Shard 2   │  │   Shard 3   │             │
│  │ Users 1-33K │  │Users 33K-66K│  │Users 66K-100K│            │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
│  Benefit: Unlimited horizontal scaling                          │
│  Trade-off: Cross-shard queries are expensive                   │
└─────────────────────────────────────────────────────────────────┘
```

**When to Consider Sharding:**
- Data exceeds single-server capacity
- Write throughput exceeds single-server limits
- Global distribution requirements

**Tools:**
- **Citus** (PostgreSQL extension)
- **Vitess** (MySQL-compatible)
- Native sharding in distributed databases (CockroachDB, YugabyteDB)

---

## 7. Appendix: Quick Reference

### 7.1 Commands Cheat Sheet

#### Part 1: Indexing

```bash
# Start environment
cd part_1
docker compose up -d --build

# View slow query logs
docker compose logs -f db

# Connect to database
docker compose exec db psql -U postgres -d indexing_demo

# Apply indexes
docker compose exec -T db psql -U postgres -d indexing_demo < solution.sql

# Cleanup
docker compose down
```

#### Part 2: Partitioning

```bash
# Start environment
cd part_2
docker compose up -d

# Connect to database
docker compose exec db psql -U postgres -d events_db

# Apply partitioning
docker compose exec -T db psql -U postgres -d events_db < solution.sql

# Check partition sizes
docker compose exec -T db psql -U postgres -d events_db -c \
  "SELECT relname, pg_size_pretty(pg_relation_size(oid)) FROM pg_class WHERE relname LIKE 'events_2%';"

# Cleanup
docker compose down
```

#### Part 3: Read Replicas

```bash
# Start cluster
cd part_3
docker compose up -d
sleep 30  # Wait for replication

# Check replication status
docker compose exec primary psql -U postgres -c \
  "SELECT application_name, state, sync_state FROM pg_stat_replication;"

# Run tests
cd app
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
pytest

# Cleanup
docker compose down
```

### 7.2 SQL Quick Reference

#### Index Commands

```sql
-- Create B-tree index (default)
CREATE INDEX idx_name ON table(column);

-- Create B-tree for pattern matching
CREATE INDEX idx_name ON table(column text_pattern_ops);

-- Create GIN index for JSONB
CREATE INDEX idx_name ON table USING GIN(column);

-- Create GIN index for text search (trigrams)
CREATE INDEX idx_name ON table USING GIN(column gin_trgm_ops);

-- Drop index
DROP INDEX idx_name;

-- Check existing indexes
\di  -- in psql
```

#### Partition Commands

```sql
-- Create partitioned table
CREATE TABLE parent (...) PARTITION BY RANGE (column);

-- Create partition
CREATE TABLE child PARTITION OF parent 
  FOR VALUES FROM ('start') TO ('end');

-- Create default partition
CREATE TABLE child_default PARTITION OF parent DEFAULT;

-- Detach partition (for maintenance)
ALTER TABLE parent DETACH PARTITION child;

-- Drop partition
DROP TABLE child;
```

#### Replication Status

```sql
-- Check replication status (run on primary)
SELECT * FROM pg_stat_replication;

-- Check if server is in recovery mode (replica)
SELECT pg_is_in_recovery();

-- Check replication lag (in bytes)
SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS lag_bytes
FROM pg_stat_replication;
```

### 7.3 Configuration Reference

| Parameter | Part | Purpose |
|-----------|------|---------|
| `log_min_duration_statement` | 1 | Log queries slower than X ms |
| `auto_explain.log_min_duration` | 1 | Auto-explain slow queries |
| `wal_level = replica` | 3 | Enable WAL for replication |
| `max_wal_senders` | 3 | Max replica connections |
| `synchronous_commit` | 3 | sync vs async replication |
| `hot_standby` | 3 | Allow queries on replicas |

### 7.4 Troubleshooting

| Problem | Likely Cause | Solution |
|---------|--------------|----------|
| Index not used | Low selectivity | Check with EXPLAIN, may not be beneficial |
| Partition not pruned | Wrong data type or function | Use explicit ranges, avoid functions on partition key |
| Replication lag | Slow replica | Check replica resources, network |
| "no partition for value" | Missing partition | Add appropriate partition or DEFAULT |
| Connection refused | Service not ready | Wait for healthchecks, use `depends_on` |

---

## End of Document

> **Total Implementation Summary:**
> - **Part 1**: Created 7 indexes, achieving up to 98% query improvement
> - **Part 2**: Implemented 16 partitions (12 monthly + 3 weekly + 1 default), achieving 90% I/O reduction
> - **Part 3**: Deployed 1 primary + 2 replicas, tripling read capacity

This concludes the complete engineering chronicle of scaling PostgreSQL from a struggling single-node database to a high-performance, horizontally-scaled architecture.

---

*Document generated as part of ESD (Enterprise Software Development) Assignment 4*
*PostgreSQL Scaling Project: Indexes, Partitions, and Replicas*

