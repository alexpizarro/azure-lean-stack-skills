---
name: managing-azure-sql-migrations
description: Manages versioned, idempotent Azure SQL migrations that run on every deployment via sqlcmd in GitHub Actions. Provides the migration-history tracking table, the guard-clause template every migration uses, and the workflow step that installs sqlcmd on ubuntu-24.04, manages the SQL firewall with trap cleanup, and runs all files in alphabetical order. Use when adding a new SQL migration, setting up the migration system on a new project, or fixing CI failures like "sqlcmd not found", "gpg cannot open /dev/tty", or "Multiple files found matching pattern *.sql".
---

# Managing Azure SQL Migrations

Idempotent, roll-forward SQL migrations run on every deploy via `sqlcmd`. The migration system uses a `__MigrationHistory` table for tracking, guard-clause migrations to make every run safe, and a workflow step that handles the operational quirks of running `sqlcmd` on ubuntu-24.04 in GitHub Actions.

## When to invoke

- Adding a new migration file
- Bootstrapping the migration system on a new project
- Fixing a CI failure related to SQL migrations

## File naming

```
infra/sql/migrations/
├── 000_migration_history.sql       # tracking table — always runs first
├── 001_create_items_table.sql      # initial schema (pre-tracking guard ok)
├── 002_add_user_id_to_items.sql    # guarded by __MigrationHistory
├── 003_seed_demo_data.sql          # also guarded
└── ...
```

Pattern: `{NNN}_{snake_case_description}.sql`. Zero-padded, alphabetical order = execution order.

## Guard clause template

Every migration from `002` onward MUST use this pattern:

```sql
IF NOT EXISTS (
    SELECT 1 FROM dbo.__MigrationHistory WHERE MigrationId = 'NNN_describe_change'
)
BEGIN
    -- DDL here (CREATE TABLE, ALTER TABLE, INSERT, MERGE, etc.)

    INSERT INTO dbo.__MigrationHistory (MigrationId) VALUES ('NNN_describe_change');
    PRINT 'Migration NNN_describe_change applied.';
END
ELSE
BEGIN
    PRINT 'Migration NNN_describe_change already applied — skipping.';
END
```

The exception is `001_create_items_table.sql`, which uses `IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Items')` because Items may have been deployed before tracking existed.

## The tracking table

`000_migration_history.sql` creates `__MigrationHistory`. Idempotent — safe to re-run:

```sql
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = '__MigrationHistory')
BEGIN
    CREATE TABLE dbo.__MigrationHistory (
        MigrationId NVARCHAR(200) NOT NULL PRIMARY KEY,
        AppliedAt   DATETIME2     NOT NULL DEFAULT GETUTCDATE()
    );
END
```

See [templates/000_migration_history.sql](templates/000_migration_history.sql) and [templates/001_create_items_table.sql](templates/001_create_items_table.sql).

## Rules

1. **File naming:** `{NNN}_{description}.sql` — zero-padded, snake_case.
2. **Never edit an applied migration** — add a new one instead.
3. **Seed data must be idempotent** — `IF NOT EXISTS` or `MERGE`.
4. **No rollback scripts** — roll forward only. Point-in-time restore is available (7-day retention on serverless).
5. **`000` always runs first** — creates the tracking table.

## Why not `azure/sql-action`

The GitHub action `azure/sql-action@v2.3` accepts **only one file**. Multi-file pushes fail with `Multiple files found matching pattern *.sql`. Use the `sqlcmd` bash step in [scripts/run-migrations.sh](scripts/run-migrations.sh) instead.

## The workflow step

The deploy workflows call [scripts/install-sqlcmd.sh](scripts/install-sqlcmd.sh) and [scripts/run-migrations.sh](scripts/run-migrations.sh). Both encode hard-won fixes:

| Fix | Why |
|-----|-----|
| `gpg --batch --yes --dearmor` | Without `--batch`, gpg tries to open `/dev/tty` and fails in headless CI |
| Pipe through `sudo tee` | Don't use `sudo gpg -o /path` — permission issues |
| Install `mssql-tools18` explicitly | Not pre-installed on ubuntu-24.04 (which `ubuntu-latest` now points to) |
| `sqlcmd -C` flag | Required with mssql-tools18 to trust Azure SQL TLS certificate |
| `trap ... EXIT` for firewall cleanup | Guarantees the runner's temporary firewall rule is removed even if a migration fails |

## Local development

To run migrations against a local SQL Server or LocalDB:

```bash
for f in $(ls infra/sql/migrations/*.sql | sort); do
  echo "Running: $f"
  sqlcmd -S localhost -d MyDb -E -i "$f"     # -E uses integrated auth
done
```

For Azure SQL from your dev box, add your IP to the firewall first:

```bash
MY_IP=$(curl -s https://api.ipify.org)
az sql server firewall-rule create --server "$SQL_SERVER_NAME" --resource-group "$RG" \
  --name "dev-$(whoami)" --start-ip-address "$MY_IP" --end-ip-address "$MY_IP"
```

## Composes with

- [scaffolding-azure-bicep-infrastructure](../scaffolding-azure-bicep-infrastructure/SKILL.md) — generates the SQL Bicep + initial migration files
- [configuring-azure-oidc-for-github-actions](../configuring-azure-oidc-for-github-actions/SKILL.md) — for the `SQL_ADMIN_PASSWORD_*` GitHub secrets the workflow uses
