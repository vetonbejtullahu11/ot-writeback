/*
 Run this script using an Azure AD admin connection (sqlcmd -G) after the
 Logic App managed identity has been granted access to the SQL server.
*/

DECLARE @LogicAppUser NVARCHAR(128) = N'ot-writeback-dev-la';

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @LogicAppUser)
BEGIN
    DECLARE @CreateUserSql NVARCHAR(MAX) =
        N'CREATE USER [' + @LogicAppUser + N'] FROM EXTERNAL PROVIDER;';
    EXEC (@CreateUserSql);
END;

GRANT EXECUTE ON dbo.usp_EntityNote_Write TO [ot-writeback-dev-la];
GRANT EXECUTE ON dbo.usp_Approval_Start TO [ot-writeback-dev-la];
GRANT EXECUTE ON dbo.usp_Approval_Action TO [ot-writeback-dev-la];
GRANT SELECT ON dbo.vApprovalStatus TO [ot-writeback-dev-la];
