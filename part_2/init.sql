-- Create a regular table for system events (no partitioning)
CREATE TABLE events (
    id SERIAL PRIMARY KEY,
    event_time TIMESTAMP NOT NULL,
    user_id INTEGER NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    event_data JSONB
);

-- Create indexes to support our query patterns
-- Index for recent events (Query 1) and time-based queries
CREATE INDEX idx_events_time ON events(event_time DESC);

-- Index for monthly analysis and event type distribution (Query 2)
CREATE INDEX idx_events_time_type ON events(event_time, event_type);

-- Index for user activity analysis (Query 3 & 4)
CREATE INDEX idx_events_user_time ON events(user_id, event_time);

-- Generate one year of historical events (500,000 records)
INSERT INTO events (event_time, user_id, event_type, event_data)
SELECT 
    -- Distribute events across the year (2024)
    timestamp '2024-01-01 00:00:00' +
    ((random() * 358)::integer || ' days')::interval +  -- First 358 days of year
    ((random() * 24)::integer || ' hours')::interval +
    ((random() * 60)::integer || ' minutes')::interval as event_time,
    -- Generate user IDs (1-10000)
    (random() * 10000)::int + 1 as user_id,
    -- Event types matching our test queries
    (ARRAY['login', 'logout', 'purchase', 'view_item', 'add_to_cart'])[1 + (n % 5)] as event_type,
    -- Sample JSON data
    jsonb_build_object(
        'ip_address', '192.168.' || (n % 255)::text || '.' || ((n * 7) % 255)::text,
        'user_agent', 'Mozilla/5.0',
        'status', CASE WHEN random() < 0.9 THEN 'success' ELSE 'failure' END
    ) as event_data
FROM generate_series(1, 500000) n;

-- Add recent events with higher frequency (100,000 records in last 14 days)
INSERT INTO events (event_time, user_id, event_type, event_data)
SELECT 
    -- Last 14 days with higher frequency
    NOW() - ((random() * 14)::integer || ' days')::interval + 
    ((random() * 24)::integer || ' hours')::interval + 
    ((random() * 60)::integer || ' minutes')::interval as event_time,
    -- Same user ID range for consistency
    (random() * 10000)::int + 1 as user_id,
    -- Same event types as above
    (ARRAY['login', 'logout', 'purchase', 'view_item', 'add_to_cart'])[1 + (n % 5)] as event_type,
    -- Consistent JSON structure
    jsonb_build_object(
        'ip_address', '192.168.' || (n % 255)::text || '.' || ((n * 7) % 255)::text,
        'user_agent', 'Mozilla/5.0',
        'status', CASE WHEN random() < 0.9 THEN 'success' ELSE 'failure' END
    ) as event_data
FROM generate_series(1, 100000) n;
