# Replica Setup

I set up one primary database and two read replicas.

- **Primary (5436)**: Handles all writes (`INSERT`, `UPDATE`).
- **Replicas (5437, 5438)**: Handle all reads (`SELECT`).

In the Python app, I use `random.choice()` to pick a replica for reading. This spreads the load evenly. I also added a small sleep in tests to handle replication lag.
