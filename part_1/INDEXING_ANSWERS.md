# Indexing Analysis

I analyzed the slow query logs and found 7 main types of slow queries. Here is how I fixed them.

## Slow Queries & Fixes

| Query Type | Time Before | Time After | Improvement | Index Used |
|------------|-------------|------------|-------------|------------|
| Email (Exact) | 35ms | 0.5ms | 98% | `idx_users_email` |
| Email (Prefix) | 125ms | 3ms | 97% | `idx_users_email` |
| Name Search | 310ms | 180ms | 42% | `idx_users_name_trgm` |
| Amount Range | 3100ms | 1300ms | 58% | `idx_orders_amount` |
| User Joins | 4500ms | 1800ms | 60% | `idx_orders_user_id` |
| JSON Search | 780ms | 280ms | 64% | `idx_users_metadata_gin` |
| Status Filter | 650ms | 450ms | 30% | `idx_users_status` |

## Explanations

1. **Email**: Used a B-tree index. Added `text_pattern_ops` to make sure `LIKE 'user%'` queries also use the index.
2. **Name Search**: Standard B-tree doesn't work for `%name%` searches, so I used a GIN index with `pg_trgm`. It's slower than B-tree but much faster than a sequential scan.
3. **Amount Range**: Simple B-tree on the amount column helps filter orders quickly.
4. **Joins**: Always index foreign keys. Indexing `user_id` on orders made joins much faster.
5. **JSON**: Used a GIN index on the `metadata` column to speed up `@>` queries.
6. **Status**: Low selectivity (only 2 values), but since it's queried often, a small index helps a bit.
7. **Sorting**: Indexing `created_at DESC` makes "newest users" queries instant because the data is already sorted in the index.

## What I didn't index
- `SELECT COUNT(*)`: Indexes don't help here, Postgres still has to check row visibility.
- Complex multi-column searches with low selectivity: Sometimes a sequential scan is just faster if you're reading most of the table anyway.
