-- Partitioning Solution

-- 1. Create the parent table
CREATE TABLE events_partitioned (
    id SERIAL,
    event_time TIMESTAMP NOT NULL,
    user_id INTEGER NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    event_data JSONB
) PARTITION BY RANGE (event_time);

-- 2. Create partitions
-- Monthly for 2024
CREATE TABLE events_202401 PARTITION OF events_partitioned FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
CREATE TABLE events_202402 PARTITION OF events_partitioned FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');
CREATE TABLE events_202403 PARTITION OF events_partitioned FOR VALUES FROM ('2024-03-01') TO ('2024-04-01');
CREATE TABLE events_202404 PARTITION OF events_partitioned FOR VALUES FROM ('2024-04-01') TO ('2024-05-01');
CREATE TABLE events_202405 PARTITION OF events_partitioned FOR VALUES FROM ('2024-05-01') TO ('2024-06-01');
CREATE TABLE events_202406 PARTITION OF events_partitioned FOR VALUES FROM ('2024-06-01') TO ('2024-07-01');
CREATE TABLE events_202407 PARTITION OF events_partitioned FOR VALUES FROM ('2024-07-01') TO ('2024-08-01');
CREATE TABLE events_202408 PARTITION OF events_partitioned FOR VALUES FROM ('2024-08-01') TO ('2024-09-01');
CREATE TABLE events_202409 PARTITION OF events_partitioned FOR VALUES FROM ('2024-09-01') TO ('2024-10-01');
CREATE TABLE events_202410 PARTITION OF events_partitioned FOR VALUES FROM ('2024-10-01') TO ('2024-11-01');
CREATE TABLE events_202411 PARTITION OF events_partitioned FOR VALUES FROM ('2024-11-01') TO ('2024-12-01');
CREATE TABLE events_202412 PARTITION OF events_partitioned FOR VALUES FROM ('2024-12-01') TO ('2025-01-01');

-- Weekly for Nov 2025 (Recent data)
CREATE TABLE events_2025_w46 PARTITION OF events_partitioned FOR VALUES FROM ('2025-11-10') TO ('2025-11-17');
CREATE TABLE events_2025_w47 PARTITION OF events_partitioned FOR VALUES FROM ('2025-11-17') TO ('2025-11-24');
CREATE TABLE events_2025_w48 PARTITION OF events_partitioned FOR VALUES FROM ('2025-11-24') TO ('2025-12-01');

-- Default for everything else
CREATE TABLE events_default PARTITION OF events_partitioned DEFAULT;

-- 3. Indexes
CREATE INDEX idx_p_events_time ON events_partitioned(event_time DESC);
CREATE INDEX idx_p_events_time_type ON events_partitioned(event_time, event_type);
CREATE INDEX idx_p_events_user_time ON events_partitioned(user_id, event_time);

-- 4. Move data
INSERT INTO events_partitioned SELECT * FROM events;