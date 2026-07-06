-- Create replication slots for each replica
SELECT * FROM pg_create_physical_replication_slot('replica1_slot');
SELECT * FROM pg_create_physical_replication_slot('replica2_slot');

-- Create events table
CREATE TABLE events (
    id SERIAL PRIMARY KEY,
    event_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    event_type VARCHAR(50) NOT NULL,
    user_id INTEGER NOT NULL,
    metadata JSONB DEFAULT '{}'::jsonb
);

-- Insert some test data
INSERT INTO events (event_type, user_id, metadata)
SELECT
    CASE (random() * 4)::int
        WHEN 0 THEN 'login'
        WHEN 1 THEN 'logout'
        WHEN 2 THEN 'purchase'
        WHEN 3 THEN 'view_item'
        ELSE 'add_to_cart'
    END as event_type,
    (random() * 999 + 1)::int as user_id,
    jsonb_build_object(
        'ip', concat('192.168.1.', (random() * 255)::int)::text,
        'user_agent', 'Mozilla/5.0',
        'device_type', CASE (random() * 2)::int
            WHEN 0 THEN 'mobile'
            WHEN 1 THEN 'desktop'
            ELSE 'tablet'
        END
    ) as metadata
FROM generate_series(1, 1000);

-- Create indexes
CREATE INDEX idx_events_time ON events(event_time DESC);
CREATE INDEX idx_events_user_time ON events(user_id, event_time);