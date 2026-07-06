import psycopg
import json
import os
from datetime import datetime, timedelta

class EventsDB:
    def __init__(self):
        # Single connection for all operations
        self.conn_str = os.environ.get(
            "DATABASE_URL",
            "postgresql://postgres:postgres@localhost:5432/events_db"
        )

    def record_event(self, event_type: str, user_id: int, metadata: dict = None):
        """Write operation - records a new event"""
        if metadata is None:
            metadata = {}
        
        with psycopg.connect(self.conn_str) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO events (event_type, user_id, metadata) VALUES (%s, %s, %s) RETURNING id",
                    (event_type, user_id, json.dumps(metadata))
                )
                return cur.fetchone()[0]

    def get_recent_events(self, hours: int = 24):
        """Read operation - gets events from last N hours"""
        with psycopg.connect(self.conn_str) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT * FROM events WHERE event_time >= %s ORDER BY event_time DESC",
                    (datetime.now() - timedelta(hours=hours),)
                )
                return cur.fetchall()

    def get_user_activity(self, user_id: int):
        """Read operation - gets all events for a specific user"""
        with psycopg.connect(self.conn_str) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT event_type, COUNT(*) FROM events WHERE user_id = %s GROUP BY event_type",
                    (user_id,)
                )
                return cur.fetchall()

    def get_monthly_stats(self):
        """Read operation - gets event counts by type for current month"""
        with psycopg.connect(self.conn_str) as conn:
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
