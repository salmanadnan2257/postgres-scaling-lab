# Part 2: PostgreSQL Partitioning - Time Series Data

This part focuses on analyzing and implementing table partitioning for time-series data. You'll work with a large events dataset and determine when partitioning provides better performance than traditional indexing.

## Learning Objectives

1. Understand scenarios where partitioning outperforms indexing
2. Learn to implement and maintain table partitioning
3. Master partition pruning concepts and benefits
4. Analyze query patterns to justify partitioning decisions

## Setup

The environment includes:
- PostgreSQL 17.0 with slow query logging enabled
- Events table with 600,000 records:
  - 500,000 events spread across last year
  - 100,000 events in the last 7 days (simulating higher recent activity)
- Comprehensive query logging and execution plan analysis

```bash
# Start PostgreSQL
docker-compose up -d

# Connect to database
psql -h localhost -U postgres -d events_db
Password: postgres
```

## Overview

In this part, you'll learn how partitioning improves performance for time-series data beyond what traditional indexes can achieve. You'll work with an `events` table containing:

- 500,000 historical events (spread across first 358 days of 2024)
- 100,000 recent events (last 7 days, simulating high traffic)
- User IDs from 1-10,000 with consistent distribution
- Event types: login, logout, purchase, view_item, add_to_cart
- Simple JSON metadata (ip_address, user_agent, status)

The table comes with pre-created indexes:
1. `idx_events_time (event_time DESC)` - for recent data access
2. `idx_events_time_type (event_time, event_type)` - for monthly analysis
3. `idx_events_user_time (user_id, event_time)` - for user activity queries

## Task Structure

You'll analyze specific query patterns and implement partitioning to improve their performance. The table already has indexes, but you'll discover why partitioning provides additional benefits:

1. Recent Data Access:
   ```sql
   -- Query 1: Last 24 hours of events
   SELECT * FROM events 
   WHERE event_time >= NOW() - INTERVAL '24 hours'
   ORDER BY event_time DESC LIMIT 100;
   ```
   Why indexing isn't enough:
   - Even with an index on (event_time), PostgreSQL must maintain index entries for the entire year
   - Recent data access competes with historical data in the buffer cache
   - Index becomes larger than necessary, affecting lookup performance
   - Write-heavy recent data causes constant index updates

   Why partitioning helps:
   - Automatic pruning eliminates old partitions
   - Recent data stays in its own buffer cache
   - Smaller, more focused indexes per partition
   - Write operations only affect recent partition

2. Historical Analysis:
   ```sql
   -- Query 2: Monthly event type distribution
   SELECT date_trunc('day', event_time) as day,
          event_type,
          COUNT(*) as count
   FROM events
   WHERE event_time >= '2024-03-01' 
     AND event_time < '2024-04-01'
   GROUP BY 1, 2
   ORDER BY 1;
   ```
   Why indexing isn't enough:
   - Aggregation requires scanning all matching rows
   - Index on (event_time, event_type) still reads unnecessary data pages
   - Buffer cache fills with data from unrelated months
   - Group BY operation memory usage affected by total table size

   Why partitioning helps:
   - Only scans relevant monthly partition
   - Better buffer cache utilization
   - Reduced memory pressure for aggregations
   - Partition-level statistics improve planning

3. User Activity Analysis:
   ```sql
   -- Query 3: Active users in last 30 days
   SELECT user_id, 
          event_type,
          COUNT(*) as event_count
   FROM events
   WHERE event_time >= NOW() - INTERVAL '30 days'
   GROUP BY 1, 2
   HAVING COUNT(*) > 100;
   ```
   Why partitioning helps:
   - Scans only recent partitions
   - More efficient memory usage
   - Better cache locality
   - Reduced index overhead

4. Time Range Scans:
   ```sql
   -- Query 4: Single user's January activity
   SELECT *
   FROM events
   WHERE user_id = 12345
     AND event_time BETWEEN '2024-01-01' AND '2024-01-31'
   ORDER BY event_time;
   ```
   Why partitioning helps:
   - Direct access to relevant month
   - Smaller, partition-local indexes
   - Better cache efficiency
   - Reduced maintenance overhead

## Task Steps

### Step 1: Analyze Current Performance

1. Run these queries and document their performance:
```sql
-- Recent events query
SELECT * FROM events 
WHERE event_time >= NOW() - INTERVAL '24 hours'
ORDER BY event_time DESC LIMIT 100;

-- Historical analysis
SELECT date_trunc('day', event_time) as day,
       event_type,
       COUNT(*) as count
FROM events
WHERE event_time >= '2024-03-01' 
  AND event_time < '2024-04-01'
GROUP BY 1, 2
ORDER BY 1;

-- User activity periods
SELECT user_id, 
       event_type,
       COUNT(*) as event_count
FROM events
WHERE event_time >= NOW() - INTERVAL '30 days'
GROUP BY 1, 2
HAVING COUNT(*) > 100;

-- Time range scan
SELECT *
FROM events
WHERE user_id = 12345
  AND event_time BETWEEN '2024-01-01' AND '2024-01-31'
ORDER BY event_time;
```

2. Document pre-partition EXPLAIN ANALYZE results in the table given [PARTITIONING_ANSWERS.md](PARTITIONING_ANSWERS.md)

### Step 2: Partitioning Details

Implement a mixed-granularity partitioning strategy:

1. Historical Data (2024):
   - Monthly partitions (events_202401 through events_202412)
   - Matches natural reporting periods
   - Lower maintenance overhead for older data

2. Recent Data:
   - Weekly partitions for last 2 weeks
   - Better write performance for high-volume data
   - More efficient buffer cache usage

3. Future Data:
   - Default partition for automatic event capture
   - Enables automated partition maintenance
   - Simplifies system operations

Put the partitioning queries in [solution.sql](solution.sql)


### Step 3: Compare Performance

1. Re-run the test queries with partitioned table now.
2. Document post-partition EXPLAIN ANALYZE results in the table given [PARTITIONING_ANSWERS.md](PARTITIONING_ANSWERS.md)
