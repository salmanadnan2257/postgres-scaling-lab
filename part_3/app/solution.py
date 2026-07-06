import psycopg
import json
import os
import random
from datetime import datetime, timedelta

class EventsDB:
    def __init__(self):
        # Primary (writes). Defaults match the docker-compose stack in part_3.
        self.p = os.environ.get(
            "PRIMARY_DSN",
            "postgresql://postgres:postgres@localhost:5436/events_db"
        )
        # Replicas (reads), comma-separated DSNs
        self.r = os.environ.get(
            "REPLICA_DSNS",
            "postgresql://postgres:postgres@localhost:5437/events_db,"
            "postgresql://postgres:postgres@localhost:5438/events_db"
        ).split(",")

    def record_event(self, event_type, user_id, metadata=None):
        if metadata is None:
            metadata = {}
        
        with psycopg.connect(self.p) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO events (event_type, user_id, metadata) VALUES (%s, %s, %s) RETURNING id",
                    (event_type, user_id, json.dumps(metadata))
                )
                return cur.fetchone()[0]

    def get_recent_events(self, hours=24):
        # Read from random replica
        conn_str = random.choice(self.r)
        
        with psycopg.connect(conn_str) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT * FROM events WHERE event_time >= %s ORDER BY event_time DESC",
                    (datetime.now() - timedelta(hours=hours),)
                )
                return cur.fetchall()

    def get_user_activity(self, user_id):
        conn_str = random.choice(self.r)
        
        with psycopg.connect(conn_str) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT event_type, COUNT(*) FROM events WHERE user_id = %s GROUP BY event_type",
                    (user_id,)
                )
                return cur.fetchall()

    def get_monthly_stats(self):
        conn_str = random.choice(self.r)
        
        with psycopg.connect(conn_str) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """SELECT 
                        event_type, 
                        COUNT(*) as count,
                        COUNT(DISTINCT user_id) as unique_users
                    FROM events 
                    WHERE date_trunc('month', event_time) = date_trunc('month', CURRENT_TIMESTAMP)
                    GROUP BY event_type"""
                )
                return cur.fetchall()
