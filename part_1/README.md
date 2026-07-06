

# Part 1: Identifying slow queries

As a first step, you have decided to use PostgreSQL's slow query logging to identify and optimize problematic queries.

In part 1, you will learn about PostgreSQL indexing strategies by analyzing and optimizing query performance in a real-world scenario. You'll work with a dataset of users and their orders, using PostgreSQL's slow query logging to identify and optimize problematic queries.

## Setup

### Docker Services

The project uses two Docker services:

1. PostgreSQL Database (`db`):
   - Configured with slow query logging (>5ms)
   - Auto-explain module enabled for execution plans
   - pg_trgm extension for text search support
   - Sample data loaded on startup (100k users, 500k orders)s)

2. Load Tester:
   - Simulates real application traffic
   - Mixes slow queries with fast queries
   - Runs continuously with random delays
   - Waits for database to be ready before starting

### Getting Started

1. Make sure you have Docker and Docker Compose installed
2. Run the services:
   ```bash
   docker-compose up --build
   ```
3. The database is pre-configured with slow query logging enabled:
   - Queries taking longer than 5ms are logged
   - Execution plans are automatically logged for slow queries
   - Buffer usage and timing information is included

## Project Tasks

### 1. Analyze Production Load

We've provided a load testing binary that simulates real-world application traffic. It runs a mix of queries against the database, some of which are inefficient and need optimization.

1. Start the database and load tester:
   ```bash
   docker-compose up -d --build
   ```
   
   This will:
   - Start PostgreSQL with slow query logging enabled
   - Build and run the load tester that simulates application traffic

2. Monitor PostgreSQL logs to identify slow queries:
   ```bash
   docker-compose logs -f db
   ```

3. Analyze the postgres container logs to:
   - Identify queries consistently taking longer than 5ms
   - Study their execution plans in the logs
   - Note which operations are causing high costs
   - Look for patterns in slow queries (e.g., specific tables or operations)

Its recommended you run the load tester for a while (5 minutes should be enough) to get enough data to analyze. After it has run for a while, copy all db logs to a file:

```bash
docker-compose logs db > db_logs.txt
# Optionally, copy load tester logs
docker-compose logs load_tester > load_tester_logs.txt
```

### 2. Doing Query Analysis

In logs, look for queries that consistently take longer than 5ms. Study their execution plans and note which operations are causing high costs. Look for patterns in slow queries (e.g., specific tables or operations).

You can connect to the database using following command:

```bash
docker-compose exec db psql -U postgres -d indexing_demo
```

Once in database, you can run queries and study their execution plans. You can also run `EXPLAIN ANALYZE` to get detailed execution plans.

Example:

Initial stage:

```sql
EXPLAIN ANALYZE SELECT * FROM users WHERE email = 'user5000@example.com';
```

Now create index:

```sql
CREATE INDEX idx_users_email ON users (email);
```

Check EXPLAIN output again:

```sql
EXPLAIN ANALYZE SELECT * FROM users WHERE email = 'user5000@example.com';
```

### 2. Query Analysis and Optimization

Your task is to:

1. From the slow query logs:
   - Identify queries that consistently perform poorly
   - Extract and analyze their execution plans
   - Document initial performance metrics in `INDEXING_ANSWERS.md`
   - Determine which queries would benefit from indexing

2. For each identified slow query:
   - Create appropriate indexes where beneficial, put queries in `solution.sql`
   - Verify improvement by monitoring logs or just running EXPLAIN ANALYZE directly on database
   - Calculate the performance improvement percentage
   - Put improved stats in `INDEXING_ANSWERS.md`

3. Important metrics to track from logs:
   - Query execution time
   - Scan types being used
   - Buffer usage and I/O statistics
   - Number of rows processed
   - Performance improvement after indexing

### Important Considerations

- Focus on queries that consistently appear in slow query logs
- Consider the real-world impact of each index
- Analyze query patterns in production load
- Balance index benefits against maintenance overhead
- Look for opportunities to use specialized indexes (GIN, GiST)
- Consider if some queries are naturally slow and can't be optimized

### Submission

Complete the following files:

1. `INDEXING_ANSWERS.md`: Document your analysis:
   - List of identified slow queries from logs
   - Performance metrics before and after indexing
   - Explanation of each created index
   - Analysis of queries you chose not to optimize
   - Overall impact on system performance

2. `solution.sql`: Include:
   - CREATE INDEX statements with detailed comments
   - Before/after EXPLAIN ANALYZE output
   - Performance improvement calculations

## Tips for Log Analysis

### Common Query Patterns

When analyzing logs, look for these common patterns that might need indexing:

1. Exact Match Lookups:
   - Looking up users by email
   - Finding orders by specific IDs
   - Pattern: `WHERE column = value`
   - Consider: B-tree indexes

2. Prefix Pattern Matching:
   - Email pattern searches
   - Starts-with conditions
   - Pattern: `WHERE column LIKE 'prefix%'`
   - Consider: B-tree indexes can help

3. Range Scans:
   - Order amount ranges
   - Date ranges
   - Pattern: `WHERE column BETWEEN x AND y`
   - Consider: B-tree indexes

4. Join Operations:
   - Users and their orders
   - Aggregations with joins
   - Pattern: Multiple table joins with grouping
   - Consider: Indexes on join columns

5. JSON Field Searches:
   - User preferences lookup
   - Nested JSON conditions
   - Pattern: `column->path->>'field' = value`
   - Consider: GIN indexes for JSON

6. Full Text Search:
   - Name searches
   - Pattern: `column LIKE '%value%'`
   - Consider: GIN indexes with pg_trgm

7. Low Selectivity Columns:
   - Status checks
   - Boolean flags
   - Pattern: Column with few unique values
   - Consider: Might not need indexing

### Analysis Tips

- Look for queries that consistently appear in slow query logs
- Group similar queries to identify patterns
- Note which operations cause high buffer usage
- Consider if some queries are naturally slow
- Watch for complex conditions that might need compound indexes

## Database Configuration

The PostgreSQL instance is configured with:
- `log_min_duration_statement = 5ms`
- `auto_explain.log_min_duration = 5ms`
- `auto_explain.log_analyze = true`
- `auto_explain.log_buffers = true`
- `auto_explain.log_timing = true`

This low threshold helps identify even slightly slow queries that might become problematic at scale. In real world, you may enable slow query logs for queries taking longer than a few seconds.

Monitor the logs while running the load tester:
```bash
docker-compose logs -f db
```

## Verification

After you have completed the analysis and optimization, you can verify the results by running the load tester again and monitoring the logs. This time you should see much fewer slow queries in the logs.