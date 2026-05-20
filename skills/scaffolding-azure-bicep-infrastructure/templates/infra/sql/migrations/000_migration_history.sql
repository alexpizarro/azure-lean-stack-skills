-- Migration 000: Create migration history tracking table
-- This must be the first migration (000 prefix) — all subsequent migrations
-- log their completion here to prevent re-execution on future deployments.
-- Safe to run multiple times (idempotent).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables WHERE name = '__MigrationHistory' AND schema_id = SCHEMA_ID('dbo')
)
BEGIN
    CREATE TABLE dbo.__MigrationHistory (
        MigrationId  NVARCHAR(150) NOT NULL,
        AppliedAt    DATETIME2     NOT NULL CONSTRAINT DF_MigrationHistory_AppliedAt DEFAULT GETUTCDATE(),
        CONSTRAINT PK_MigrationHistory PRIMARY KEY CLUSTERED (MigrationId ASC)
    );

    PRINT 'Created table dbo.__MigrationHistory';
END
ELSE
BEGIN
    PRINT 'Table dbo.__MigrationHistory already exists — skipping.';
END
