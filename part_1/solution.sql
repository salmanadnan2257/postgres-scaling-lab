-- Indexing Solution

-- 1. Exact match and prefix search
CREATE INDEX idx_users_email ON users(email text_pattern_ops);

-- 2. Full-text search
CREATE INDEX idx_users_name_trgm ON users USING GIN(full_name gin_trgm_ops);

-- 3. Range queries
CREATE INDEX idx_orders_amount ON orders(amount);

-- 4. Foreign keys
CREATE INDEX idx_orders_user_id ON orders(user_id);

-- 5. JSON metadata
CREATE INDEX idx_users_metadata_gin ON users USING GIN(metadata);

-- 6. Status filtering
CREATE INDEX idx_users_status ON users(status);

-- 7. Sorting
CREATE INDEX idx_users_created_desc ON users(created_at DESC);
