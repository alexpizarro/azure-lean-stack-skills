-- setup-mi-db-user.sql
-- Grants the Function App's system-assigned managed identity a least-privilege SQL user.
--
-- RUN THIS CONNECTED AS THE SQL SERVER'S ENTRA ADMIN. A SQL login CANNOT create an
-- external-provider user — you must connect as an Entra principal that is the server's
-- Entra admin (e.g. `sqlcmd -G ...` interactively, or the mssql access-token path in
-- scripts/create-mi-db-user.cjs). The MI's Entra display name == the Function App name.
--
-- Idempotent: safe to run repeatedly.
--
-- Replace the token REPLACE_WITH_FUNCTION_APP_NAME (in the DECLARE below) with the
-- Function App name.
--
-- GOTCHA — the guard is SPLIT ON PURPOSE. A naive global find/replace of the token
-- REPLACE_WITH_FUNCTION_APP_NAME would otherwise rewrite BOTH the DECLARE value AND the
-- guard's literal, making the guard compare the real name to itself and always throw.
-- The guard literal below is split as N'REPLACE_' + N'WITH_FUNCTION_APP_NAME' so a
-- full-token replace cannot touch it.

DECLARE @miName sysname = N'REPLACE_WITH_FUNCTION_APP_NAME';
-- Least privilege: reader + writer only. Set to 1 ONLY if the app itself runs DDL at
-- runtime. The deploy-time migration runner uses sqladmin, so the default is 0.
DECLARE @grantDdl bit = 0;

IF @miName = N'REPLACE_' + N'WITH_FUNCTION_APP_NAME'
    THROW 50000, N'Replace REPLACE_WITH_FUNCTION_APP_NAME with the Function App name before running.', 1;

-- Create the MI user (guarded)
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @miName)
    EXEC (N'CREATE USER ' + QUOTENAME(@miName) + N' FROM EXTERNAL PROVIDER;');

-- Least-privilege roles (each guarded — idempotent)
IF IS_ROLEMEMBER('db_datareader', @miName) = 0
    EXEC (N'ALTER ROLE db_datareader ADD MEMBER ' + QUOTENAME(@miName) + N';');
IF IS_ROLEMEMBER('db_datawriter', @miName) = 0
    EXEC (N'ALTER ROLE db_datawriter ADD MEMBER ' + QUOTENAME(@miName) + N';');
IF @grantDdl = 1 AND IS_ROLEMEMBER('db_ddladmin', @miName) = 0
    EXEC (N'ALTER ROLE db_ddladmin ADD MEMBER ' + QUOTENAME(@miName) + N';');
