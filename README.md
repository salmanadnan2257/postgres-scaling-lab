# PostgreSQL Scaling Lab

A three-part study of scaling a single PostgreSQL node before reaching for NoSQL: find slow queries and index them, partition a time-series table, then add streaming read replicas with read/write routing in the application. Built solo by Salman Adnan for an Enterprise Software Development course, against course-provided scaffolding (schemas, load tester, assignment briefs).

The premise: a CTO wants to migrate to NoSQL because of slow queries. This project shows how far plain PostgreSQL goes with the standard toolbox.

## Results

All numbers were measured on the original Docker setup (PostgreSQL 17.0). They are workload-specific, not general claims.

**Part 1, indexing** (100k users, 500k orders, slow-query log + auto_explain to find offenders):

| Query | Before | After | Index |
|---|---|---|---|
| Email exact match | 35ms | 0.5ms | B-tree with `text_pattern_ops` |
| Email prefix (`LIKE 'user%'`) | 125ms | 3ms | same index |
| Name substring (`%name%`) | 310ms | 180ms | GIN with `pg_trgm` |
| Amount range | 3,100ms | 1,300ms | B-tree |
| User/order join | 4,500ms | 1,800ms | B-tree on the FK |
| JSONB containment (`@>`) | 780ms | 280ms | GIN on `metadata` |

**Part 2, range partitioning** (600k events, monthly partitions for 2024 plus weekly partitions for hot data): monthly analysis dropped from 9,154 buffer blocks read to 975 (partition pruning skips 11 months). Recent-events query improved 48%. The honest negative result: user-activity queries got 70% slower, because they filter on `user_id`, not the partition key, so every partition gets probed.

**Part 3, read replicas**: one primary, two async streaming replicas built with `pg_basebackup` and physical replication slots. A small psycopg app routes writes to the primary and reads to a randomly chosen replica. The test suite tolerates replication lag with a short sleep.

The full analysis (query plans, buffer statistics, trade-off discussions) is in [docs/EXPLANATION.md](docs/EXPLANATION.md). Shorter per-part notes: [part_1/INDEXING_ANSWERS.md](part_1/INDEXING_ANSWERS.md), [part_2/PARTITIONING_ANSWERS.md](part_2/PARTITIONING_ANSWERS.md), [part_3/REPLICA_SETUP.md](part_3/REPLICA_SETUP.md).

## Layout

```
part_1/   slow-query logging + indexing (docker-compose, init.sql, solution.sql, Go load tester)
part_2/   range partitioning (docker-compose, init.sql, solution.sql)
part_3/   primary + 2 replicas (docker-compose, postgres confs, psycopg app + pytest suite)
docs/     full write-up (EXPLANATION.md) and the original assignment brief (ASSIGNMENT.md)
```

Authorship note: the assignment briefs (`docs/ASSIGNMENT.md`, `part_*/README.md`), the `init.sql` schemas, the baseline `part_3/app/app.py`, the test suite, and the Go load tester binaries in `part_1/load_tester/` (`load_tester_amd64`, `load_tester_arm64`, shipped without source) are course-provided artifacts, not authored here. My work is the `solution.sql` files, the replication setup in `part_3` (compose changes, `primary.conf`, `replica*.conf`, `pg_hba.conf`), the routing app `part_3/app/solution.py`, and the analysis documents.

## Setup

Requires Docker with Compose v2, and Python 3.10+ for part 3. Each part is an independent stack; run `docker compose down` before moving to the next part.

Passwords default to `postgres` (it's a lab). Override with `POSTGRES_PASSWORD`, see `.env.example`.

**Part 1**

```bash
cd part_1
docker compose up -d --build          # DB on :5433, load tester starts automatically
docker compose logs db | grep duration | head   # watch slow queries appear
docker compose exec -T db psql -U postgres -d indexing_demo < solution.sql
docker compose logs db | grep duration | tail   # same queries, now fast
docker compose down
```

**Part 2**

```bash
cd part_2
docker compose up -d                  # DB on :5435, loads 600k events
docker compose exec -T db psql -U postgres -d events_db < solution.sql
docker compose exec -T db psql -U postgres -d events_db \
  -c "SELECT relname, pg_size_pretty(pg_relation_size(oid)) FROM pg_class WHERE relname LIKE 'events_2%';"
docker compose down
```

**Part 3**

```bash
cd part_3
docker compose up -d                  # primary :5436, replicas :5437 and :5438
sleep 30                              # let replicas take their base backup
docker compose exec primary psql -U postgres -c "SELECT application_name, state FROM pg_stat_replication;"
cd app
python3 -m venv ~/.venvs/pg-scaling && source ~/.venvs/pg-scaling/bin/activate
pip install -r requirements.txt
pytest                                # 5 tests: writes hit primary, reads hit replicas
cd .. && docker compose down
```

The part 3 app reads `PRIMARY_DSN` and `REPLICA_DSNS` (comma-separated) from the environment, defaulting to the compose stack's ports.

## Verification status

Docker was not available on the machine used for the latest revision, so the compose stacks were not re-run there. What was verified instead: every SQL file executes cleanly against PostgreSQL 18, the part 3 test suite passes 5/5 against a local PostgreSQL (all DSNs pointed at one server), and all three compose files pass `docker compose config`. The benchmark table above comes from the original Docker runs during the course (PostgreSQL 17), and has not been re-measured since.

The part 1 email lookup **was** re-measured, on a scratch local PostgreSQL 18.4 cluster loading this repo's own `part_1/init.sql` (100k users, 500k orders) and its own `idx_users_email`. Full stdout is saved in [docs/screenshots/run-output.txt](docs/screenshots/run-output.txt), and the screenshot beside it is that same run. The result: the sequential scan reads all 2,494 blocks of `users` and discards 99,999 of the 100,000 rows; with the index it reads 4 blocks. Warm, the query goes from about 19ms to about 0.1ms. Those block counts are identical on every run; the milliseconds are not, so the block count is the figure worth quoting. The first-ever scan of a freshly loaded table is much slower and very unstable (19ms to 140ms across trials) because it is also setting hint bits on every row and writing those blocks back out; a single sample of it is not a benchmark. These numbers are a different machine and a different PostgreSQL from the 35ms/0.5ms in the table, and are not directly comparable to it.

## Challenges

- **The user-activity query got slower after partitioning, and I kept the result.** Range-partitioning on `event_time` speeds up anything that filters by time, but `get_user_activity` filters by `user_id`. There is nothing in that predicate for the planner to prune on, so it probes the local index on every partition instead of one B-tree. The measured cost was about 70% worse than the single-table version. The temptation was to bury it; instead I wrote it up as the direct trade-off of choosing a partition key. Partitioning is a bet on your access pattern, and this query is the losing side of that bet.
- **A plaintext password file was committed to the repo.** The original part 3 setup checked in `part_3/.pgpass` containing `primary:5432:*:postgres:postgres`. `pg_basebackup -R` needs credentials with no terminal to prompt at, which is why the file existed. I removed the checked-in file and moved generation into the replica startup command: each container writes `.pgpass` from `POSTGRES_USER` and `POSTGRES_PASSWORD` at boot and `chmod 600`s it (see `part_3/docker-compose.yml`). The credential still reaches `pg_basebackup` non-interactively, but it is no longer sitting in version control.
- **Reads could return rows that had just been written.** Writes go to the primary and reads go to a randomly chosen async replica, so a read issued immediately after a write can miss the row while the WAL is still in flight. There is no way to route around this without either synchronous replication or read-your-writes logic in the app. I left it async and made the routing honest about it: writes always hit the primary, reads accept that a fresh row may not be visible yet, and the tests wait a short interval before asserting on replicated data.
- **A plain B-tree index answered almost none of the part 1 queries.** Email exact match is fine on a default B-tree, but `LIKE 'user%'` needs `text_pattern_ops` to use the index at all, `LIKE '%name%'` needs a GIN index with `pg_trgm`, and JSONB containment (`@>`) needs a GIN index on the column. Each of those is a different operator class, not a tuning knob. The substring case is the honest limit: even with the trigram index it only improved from 310ms to 180ms, because trigram matching still checks a large candidate set.
- **The load generator was a black box.** The tool that drives traffic in part 1 is a course-provided Go program shipped as prebuilt `amd64`/`arm64` binaries with no source (`part_1/load_tester/`). I could not change the query mix or read what it was doing, so I made the database report on itself instead: `log_min_duration_statement` plus `auto_explain` turned every slow statement into a logged plan, which is how the before/after numbers were collected without touching the generator.
- **Writing the exhaustive project documentation honestly.** The first documentation attempt stalled mid-task and had to be redone, on top of the project's own already-documented constraint that the full Docker stacks couldn't be brought up live here (the daemon was off), which the explainer had to state plainly rather than imply a live multi-node run had happened.

## What I learned

- Partition pruning only helps queries that filter on the partition key. Choosing `event_time` optimizes time-range scans and does nothing for lookups by `user_id`, so the key choice is really a choice about which queries you are willing to make slower.
- The index type is a decision. `text_pattern_ops` for prefix matching, GIN with `pg_trgm` for substring search, and GIN for JSONB containment each exist because a default B-tree cannot serve those predicates at all. Reaching for `CREATE INDEX` without naming the operator class often builds an index the planner never uses.
- Async streaming replication buys read scale-out but pushes consistency into the application. Once reads can lag writes, the app has to own routing and the tests have to tolerate staleness. That coupling does not exist on a single node.
- Secrets management is a startup concern, not a repository concern. Generating `.pgpass` at container boot from an environment variable feeds `pg_basebackup` the same credential without ever storing it in the tree.
- Buffer counts from `EXPLAIN (BUFFERS)` are a steadier comparison than wall-clock milliseconds. The monthly-analysis win (9,154 blocks down to 975) is a property of partition pruning and does not drift with cache warmth the way timing does.

## What I'd do differently

- **Generate partitions instead of hardcoding them.** `part_2/solution.sql` hardcodes monthly partitions for 2024 and weekly ones for November 2025, while `init.sql` generates "recent" data relative to `NOW()`. Run today, the recent rows land in the default partition and the hot-data speedups don't reproduce. A `DO` block computing boundaries from the data (or pg_partman) would keep the demo honest indefinitely.
- **Fix the sequence after migration.** `INSERT INTO events_partitioned SELECT * FROM events` copies ids but never advances the new table's sequence, so fresh inserts would collide with existing ids. It needs a `setval()` after the copy.
- **Pool connections.** Both app versions open a new connection per query. psycopg_pool exists and would remove most of the per-call latency.
- **Replica selection with health awareness.** `random.choice()` over two DSNs means a dead replica fails 50% of reads. Even a naive retry-on-other-replica would be better; a real setup would put pgbouncer or HAProxy in front.
- **Tests that can't pass vacuously.** The course-provided tests skip their assertions when replicated data hasn't arrived yet, so a completely broken replication setup can still go green. Polling until the row appears (with a timeout) would actually test the replication path.
- **Fewer, measured indexes.** Part 1 indexes seven things including a two-value `status` column; the 30% gain there is within noise and the write amplification was never measured. I'd keep the five that earn their place and benchmark inserts before and after.
