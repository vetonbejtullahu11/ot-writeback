/*
    Use this script to grant the Fabric (or other caller) managed identity
    access to the OT writeback database. Run it with Azure AD admin rights
    (sqlcmd -G / SSMS AAD connection) and replace the placeholder principal
    below with the actual identity name (e.g., FabricWarehouseWriter).
*/

DECLARE @AccessPrincipal sysname = N'<SET_IDENTITY_NAME>';

IF @AccessPrincipal = N'<SET_IDENTITY_NAME>'
    THROW 70050, 'Update @AccessPrincipal with the Fabric managed identity name before running this script.', 1;

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @AccessPrincipal)
BEGIN
    DECLARE @CreateUserSql NVARCHAR(MAX) =
        N'CREATE USER ' + QUOTENAME(@AccessPrincipal) + N' FROM EXTERNAL PROVIDER;';
    EXEC (@CreateUserSql);
END;

DECLARE @Sql NVARCHAR(MAX);

SET @Sql = N'GRANT EXECUTE ON dbo.usp_Approval_Start TO ' + QUOTENAME(@AccessPrincipal) + N';';
EXEC (@Sql);

SET @Sql = N'GRANT EXECUTE ON dbo.usp_Approval_Recalculate TO ' + QUOTENAME(@AccessPrincipal) + N';';
EXEC (@Sql);

SET @Sql = N'GRANT EXECUTE ON dbo.usp_Approval_Action TO ' + QUOTENAME(@AccessPrincipal) + N';';
EXEC (@Sql);

SET @Sql = N'GRANT EXECUTE ON dbo.usp_BulkInsert_EntityNote TO ' + QUOTENAME(@AccessPrincipal) + N';';
EXEC (@Sql);

SET @Sql = N'GRANT SELECT ON dbo.vEntityNote_ByEntity TO ' + QUOTENAME(@AccessPrincipal) + N';';
EXEC (@Sql);

SET @Sql = N'GRANT SELECT ON dbo.vApprovalStatus TO ' + QUOTENAME(@AccessPrincipal) + N';';
EXEC (@Sql);
