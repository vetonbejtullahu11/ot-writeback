# Database migrations with Alembic

The `ops/alembic` folder hosts the migration tooling for the OT writeback SQL
schema. Alembic executes migrations directly against Azure SQL / SQL Server via
SQLAlchemy so each change to `ops/sql/schema.sql` should be captured as either a
new migration file or an update to the initial revision (until prod is cut).

## Prerequisites

1. Python 3.10+
2. The ODBC Driver 18 for SQL Server (or another driver that matches your
   connection string)
3. Install dependencies:
   ```bash
   python -m venv .venv
   source .venv/bin/activate
   pip install -r ops/alembic/requirements.txt
   ```
4. Provide a database URL via `DATABASE_URL`. Example for SQL auth:
   ```bash
   export DATABASE_URL="mssql+pyodbc://sqladminuser:<PASSWORD>@ot-writeback-dev-sql.database.windows.net/ot-writeback-dev-db?driver=ODBC+Driver+18+for+SQL+Server&Encrypt=yes&TrustServerCertificate=no"
   ```
   The URL can point to any environment (dev/test/prod) as long as the account
   has rights to run migrations.

## Common commands

Apply the latest schema:
```bash
alembic upgrade head
```

Generate a new revision (after editing `ops/sql/schema.sql`):
```bash
alembic revision -m "add new approval exception" --autogenerate
```
(Autogenerate currently has no models, so edit the generated file manually.)

Downgrades are intentionally unsupported. If you need to revert, create a new
migration that restores the previous state.
