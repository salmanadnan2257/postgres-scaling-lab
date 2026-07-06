-- Enable pg_trgm extension for text search capabilities
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Create tables without any indexes initially
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255),
    full_name VARCHAR(255),
    status VARCHAR(20),
    metadata JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER,
    amount DECIMAL(10,2),
    status VARCHAR(20),
    items JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert sample data
INSERT INTO users (email, full_name, status, metadata)
SELECT 
    'user' || n || '@example.com',
    'User ' || n,
    CASE WHEN n % 100 = 0 THEN 'inactive' ELSE 'active' END,
    jsonb_build_object(
        'last_login', NOW() - (n || ' days')::INTERVAL,
        'preferences', jsonb_build_object(
            'theme', (ARRAY['light', 'dark'])[1 + (n % 2)],
            'language', (ARRAY['en', 'es', 'fr'])[1 + (n % 3)]
        )
    )
FROM generate_series(1, 100000) n;

-- Insert orders (multiple orders per user)
INSERT INTO orders (user_id, amount, status, items)
SELECT 
    (random() * 100000)::int + 1 as user_id,
    (random() * 1000)::decimal(10,2) as amount,
    (ARRAY['pending', 'completed', 'cancelled'])[1 + (n % 3)] as status,
    jsonb_build_object(
        'products', jsonb_build_array(
            jsonb_build_object('id', n, 'name', 'Product ' || n, 'quantity', (random() * 5)::int + 1),
            jsonb_build_object('id', n+1, 'name', 'Product ' || (n+1), 'quantity', (random() * 3)::int + 1)
        )
    )
FROM generate_series(1, 500000) n;
