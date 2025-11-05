/*
    Wrapper script to deploy the OT Writeback database schema.
    Usage (sqlcmd):
        sqlcmd -S <server>.database.windows.net -d ot-writeback-dev-db -U <user> -P <password> -i ops/sql/deploy.sql

    The script is idempotent and can be executed repeatedly.
*/

:r schema.sql
