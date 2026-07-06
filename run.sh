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
