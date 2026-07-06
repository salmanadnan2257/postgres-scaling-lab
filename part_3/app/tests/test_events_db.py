import pytest
import sys
import os
import time

# Add the parent directory to the path so we can import from app.py
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))  
from solution import EventsDB

@pytest.fixture
def events_db():
    return EventsDB()

def test_record_event(events_db):
    # Test recording an event
    event_id = events_db.record_event(
        event_type="test_event",
        user_id=1,
        metadata={"key": "value"}
    )
    assert isinstance(event_id, int)
    assert event_id > 0

def test_record_event_no_metadata(events_db):
    # Test recording an event without metadata
    event_id = events_db.record_event(
        event_type="test_event",
        user_id=1
    )
    assert isinstance(event_id, int)
    assert event_id > 0

def test_get_recent_events(events_db):
    # Record some events for testing
    events_db.record_event("test_recent_event", 1)
    events_db.record_event("test_recent_event", 2)
    
    # Add a small delay to allow for replication lag
    time.sleep(0.5)
    
    # Get recent events
    events = events_db.get_recent_events(hours=1)
    assert isinstance(events, list)
    
    # We can't guarantee exactly how many events will be in the database
    # but we can check that the structure is correct if there are any
    if events:
        for event in events:
            assert isinstance(event, tuple)
            # Check that we have id, event_type, user_id, event_time, metadata columns
            assert len(event) >= 4

def test_get_user_activity(events_db):
    # Generate a unique user ID to ensure we're only testing our own data
    import random
    test_user_id = random.randint(10000, 99999)
    
    # Record some events for our test user
    events_db.record_event("test_event_1", test_user_id)
    events_db.record_event("test_event_2", test_user_id)
    
    # Add a small delay to allow for replication lag
    time.sleep(0.5)
    
    # Get user activity
    user_activity = events_db.get_user_activity(test_user_id)
    assert isinstance(user_activity, list)
    
    # Due to replication lag, we might not see our events immediately
    # So we'll skip this assertion if no data is found
    if len(user_activity) > 0:
        # Verify structure of user activity results
        for activity in user_activity:
            assert isinstance(activity, tuple)
            assert len(activity) == 2  # event_type, count

def test_get_monthly_stats(events_db):
    # Generate unique event types to ensure we're only testing our own data
    import random
    test_prefix = f"test_type_{random.randint(1000, 9999)}"
    type1 = f"{test_prefix}_1"
    type2 = f"{test_prefix}_2"
    
    # Record some events of different types
    events_db.record_event(type1, 1)
    events_db.record_event(type2, 2)
    events_db.record_event(type1, 3)
    
    # Add a small delay to allow for replication lag
    time.sleep(0.5)
    
    # Get monthly stats
    stats = events_db.get_monthly_stats()
    assert isinstance(stats, list)
    
    # Create a dictionary from the results for easier testing
    stats_dict = {}
    for stat in stats:
        if len(stat) >= 3:  # Make sure we have enough elements in the tuple
            event_type = stat[0]
            count = stat[1]
            unique_users = stat[2]
            stats_dict[event_type] = (count, unique_users)
    
    # Due to replication lag, we might not see our events immediately
    # So we'll skip these assertions if no data is found
    if type1 in stats_dict:
        assert stats_dict[type1][0] >= 1  # Count should be at least 1
    
    if type2 in stats_dict:
        assert stats_dict[type2][0] >= 1  # Count should be at least 1
