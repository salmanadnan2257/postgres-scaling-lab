# Partitioning Analysis

I implemented range partitioning on `event_time` to speed up queries.

## Performance Comparison

| Query | Time Before | Time After | Improvement |
|-------|-------------|------------|-------------|
| Recent Events | 1.36ms | 0.70ms | 48% |
| Monthly Analysis | 140ms | 86ms | 38% |
| User Activity | 93ms | 160ms | -70% |
| Time Range | 0.06ms | 0.09ms | ~0% |

## Why these results?

1. **Recent Events & Monthly Analysis**: These got much faster because of **Partition Pruning**. Postgres only had to look at 1 or 2 partitions instead of the whole table.
2. **User Activity**: This got slower. Since user activity is spread across all time, Postgres had to check multiple partitions, which adds overhead. Partitioning isn't great for queries that don't filter by the partition key.
3. **Time Range**: Both were instant, so the difference is negligible.

## Strategy
- **Monthly Partitions (2024)**: Good for historical data that isn't queried often.
- **Weekly Partitions (Nov 2025)**: Smaller partitions for recent, "hot" data. This keeps indexes smaller and faster.
- **Default Partition**: Catches any data outside these ranges so inserts don't fail.
