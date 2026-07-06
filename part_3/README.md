# Part 3: PostgreSQL Read Replicas and Load Distribution

In this part, you will implement and analyze a PostgreSQL read replica setup with a Python application that demonstrates read/write splitting patterns.

### Phase 1: Setup and Understanding

1. Start by examining the infrastructure:
   ```bash
   # Review the configuration files
   cat primary.conf   # Note write optimization settings
   cat replica.conf   # Note read optimization settings
   cat init.sql       # Study the schema and test data
   ```

2. Start the PostgreSQL cluster:
   ```bash
   # Start all containers
   docker-compose up -d
   
   # Wait for replicas to sync (about 30 seconds)
   sleep 30
   
   # Verify replication status
   docker-compose exec primary psql -U postgres -c \
     "SELECT application_name, state, sync_state FROM pg_stat_replication;"
   ```
   It should look like this:
   
   ```
   application_name | client_addr |   state   | sync_state 
   ------------------+-------------+-----------+------------
   walreceiver      | 172.29.0.3  | streaming | async
   walreceiver      | 172.29.0.4  | streaming | async
   ```

   If you connect to the primary database and create some records or tables, they should now be visible in the replicas.

3. Set up your Python environment:
   ```bash
   # Create and activate virtual environment
   python3 -m venv venv
   source venv/bin/activate
   
   # Install dependencies
   cd app
   pip install -r requirements.txt
   ```

4. Run the base implementation:
   ```bash
   # Run app.py to understand the current behavior
   python3 app.py
   ```

### Phase 2: Implementation

1. Study the base implementation in `app.py`:
   - Event tracking system model:
     * `events` table with status tracking
     * Mixed read/write workload
     * Basic health monitoring


2. Create your enhanced version in `solution.py`.

3. Run the tests:

```bash
cd app
source .venv/bin/activate
pytest
```

All 5 tests should pass. If you have a slow system and you comment out `time.sleep` calls in tests, you will see failures due to the replication lag. If you change `from solution import EventsDB` to `from app import EventsDB`, you will see no failures even without sleep since all operations go to the same database instance.

4. Document what you did in `REPLICA_SETUP.md`.


## Advanced Scenarios

In a real scenario, read replicas may come and go, and you may need to handle such cases. You may also need to handle the case where the primary database goes down and add back-offs and retries. You may also need to handle the case where the read replicas are not in sync with the primary database. Sometimes you want to read from primary database since lag is too high and reading consistent data after write is crucial.

This simple application also creates connections as it pleases, a real application would use some library to maintain connection pools. Postgres has connection pooling solutions like PG Bouncer that you can use.