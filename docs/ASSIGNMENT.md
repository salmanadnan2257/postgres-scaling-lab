# Project 5: Scaling RDBMS

You are a traditional software development org which decided to run all your applications on RDBMS (Postgresql) because that is what you knew and what you were comfortable with. It is also very well understood technology and with plenty of documentation and community support. This has worked well for you so far.

But now you are starting to see some performance issues with the database. You have a dataset of users and their orders, and you are starting to see some queries that are taking longer than expected. Your CTO has heard NoSQL is infinitely scalable so you should use that instead of RDBMS. You being a veteran know that NoSQL is not always the best choice and you want to extract the best performance from RDBMS as you know that goes a long way.

You have some ideas, so you begin:

# Part 1: Identifying slow queries and speeding them up using indexes (4 points)

First step in your journey is to enable slow query logs, so you can find out which queries are taking longer than expected and then fix them.

Refer to documentation in [part_1/README.md](../part_1/README.md)

Run `docker-compose down` to kill part 1 containers before continuing.

# Part 2: Partitioning (3 points)

At this point, you have already sped up a bunch. But you noticed that you still have some queries that are taking longer than expected and indexes aren't helping, so you decide to partition one of the tables.

Refer to documentation in [part_2/README.md](../part_2/README.md)

Run `docker-compose down` to kill part 2 containers before continuing.

# Part 3: Read Replicas (3 points)

Partitions and indexes are great but you were still using only one server to handle reads and writes. You figured out that you can use read replicas to offload read load. You will now update the code to use read replicas.

Refer to documentation in [part_3/README.md](../part_3/README.md)

Run `docker-compose down` to kill part 3 containers.

# Part 4: Sharding

Just kidding, this is not what you will do in this project. But to go fully distributed you will use something like Citus extension of PostgreSql. That will let you have partial data on a single node so you will not have to fit all of your data into one server unlike what we did with read replicas above.

