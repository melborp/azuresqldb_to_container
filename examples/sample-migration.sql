-- Sample Migration Script
-- This is an example migration script that might be used during container build

-- Create a new table for application metadata
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'ApplicationMetadata')
BEGIN
    CREATE TABLE ApplicationMetadata (
        Id int IDENTITY(1,1) PRIMARY KEY,
        [Key] nvarchar(100) NOT NULL UNIQUE,
        [Value] nvarchar(500) NOT NULL,
        CreatedDate datetime2 DEFAULT GETUTCDATE(),
        ModifiedDate datetime2 DEFAULT GETUTCDATE()
    );
    
    PRINT 'Created ApplicationMetadata table';
END
ELSE
BEGIN
    PRINT 'ApplicationMetadata table already exists';
END

-- Insert migration metadata
IF NOT EXISTS (SELECT * FROM ApplicationMetadata WHERE [Key] = 'MigrationVersion')
BEGIN
    INSERT INTO ApplicationMetadata ([Key], [Value]) 
    VALUES ('MigrationVersion', '1.0.0');
    
    PRINT 'Inserted migration version metadata';
END

-- Add indexes for performance
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_ApplicationMetadata_Key')
BEGIN
    CREATE INDEX IX_ApplicationMetadata_Key ON ApplicationMetadata ([Key]);
    PRINT 'Created index on ApplicationMetadata.Key';
END

PRINT 'Sample migration script completed successfully';
