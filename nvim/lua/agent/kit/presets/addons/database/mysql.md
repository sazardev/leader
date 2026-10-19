<!-- name: MySQL -->
<!-- desc: MySQL 8 / MariaDB with utf8mb4, InnoDB, versioned migrations and a real database in tests -->
<!-- for: server backend fullstack selfhosted php ruby !mobile -->

## Stack

| Database | MySQL 8 (InnoDB, `utf8mb4`, `DATABASE_URL`, versioned migrations) | Widely hosted and well known; fine for classic relational workloads |

## Project layout

```
migrations/                    numbered, forward-only SQL migrations
compose.yaml                   local `mysql` service with a named volume and a healthcheck
```

## Conventions

- Connection string only from `DATABASE_URL`; one pool per process.
- Every database and table uses `utf8mb4` with `utf8mb4_0900_ai_ci` (or the project's chosen collation); never the legacy `utf8`.
- InnoDB only; foreign keys declared, indexes on every foreign key and frequent filter.
- Time stored in UTC (`DATETIME` or `TIMESTAMP`), money as `DECIMAL` or integer cents.
- Statements use bound parameters; `sql_mode` stays strict.

## Commands

| Database up | `docker compose up -d mysql` |
| Shell | `mysql -h 127.0.0.1 -u root -p` |

## Testing

- Integration tests run against a real MySQL container with the real migrations, never SQLite as a stand-in.

## Rules for agents

- Never concatenate user input into SQL.
- Never edit an applied migration; add a new one.
- Long `ALTER TABLE` on big tables needs an online-DDL plan; say so before writing it.
