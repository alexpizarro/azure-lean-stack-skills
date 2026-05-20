-- Migration 001: Create Items table
-- Safe to run multiple times (idempotent)

IF NOT EXISTS (
    SELECT * FROM sysobjects WHERE name = 'Items' AND xtype = 'U'
)
BEGIN
    CREATE TABLE dbo.Items (
        Id        INT            IDENTITY(1,1) NOT NULL,
        Name      NVARCHAR(255)  NOT NULL,
        CreatedAt DATETIME2      NOT NULL DEFAULT GETUTCDATE(),
        CONSTRAINT PK_Items PRIMARY KEY CLUSTERED (Id ASC)
    );

    PRINT 'Created table dbo.Items';
END
ELSE
BEGIN
    PRINT 'Table dbo.Items already exists — skipping.';
END
