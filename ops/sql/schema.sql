SET NOCOUNT ON;
GO

/* =============================================================================
   Database Schema for OT Writeback Dev Environment
   - Tables: EntityType, Entity, EntityNote, EntityAcl, ApprovalInstance, ApprovalAction
   - Supporting objects: indexes, stored procedures, views, security grants
   Idempotent by design so the script can be re-applied safely.
============================================================================= */

-------------------------------------------------------------------------------
-- Core reference tables
-------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.EntityType', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.EntityType
    (
        EntityTypeId INT IDENTITY(1, 1) NOT NULL CONSTRAINT PK_EntityType PRIMARY KEY,
        Name         NVARCHAR(100) NOT NULL,
        Description  NVARCHAR(256) NULL,
        CONSTRAINT UQ_EntityType_Name UNIQUE (Name)
    );
END;
GO

IF OBJECT_ID(N'dbo.Entity', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Entity
    (
        EntityId          INT IDENTITY(1, 1) NOT NULL CONSTRAINT PK_Entity PRIMARY KEY,
        EntityTypeId      INT NOT NULL CONSTRAINT FK_Entity_EntityType REFERENCES dbo.EntityType(EntityTypeId),
        ExternalReference NVARCHAR(100) NOT NULL,
        DisplayName       NVARCHAR(200) NOT NULL,
        CreatedUtc        DATETIME2(3) NOT NULL CONSTRAINT DF_Entity_CreatedUtc DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT UQ_Entity_ExternalReference UNIQUE (ExternalReference)
    );
END;
GO

-------------------------------------------------------------------------------
-- Notes
-------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.EntityNote', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.EntityNote
    (
        EntityNoteId BIGINT IDENTITY(1, 1) NOT NULL CONSTRAINT PK_EntityNote PRIMARY KEY,
        EntityId     INT NOT NULL CONSTRAINT FK_EntityNote_Entity REFERENCES dbo.Entity(EntityId),
        NoteType     NVARCHAR(50) NOT NULL,
        NoteText     NVARCHAR(MAX) NOT NULL,
        CreatedBy    NVARCHAR(256) NOT NULL,
        CreatedUtc   DATETIME2(3) NOT NULL CONSTRAINT DF_EntityNote_CreatedUtc DEFAULT (SYSUTCDATETIME()),
        RequestId    UNIQUEIDENTIFIER NOT NULL,
        CONSTRAINT UQ_EntityNote_Request UNIQUE (RequestId)
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_EntityNote_EntityId' AND object_id = OBJECT_ID(N'dbo.EntityNote'))
BEGIN
    CREATE INDEX IX_EntityNote_EntityId ON dbo.EntityNote(EntityId);
END;
GO

-------------------------------------------------------------------------------
-- Access Control
-------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.EntityAcl', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.EntityAcl
    (
        EntityAclId        INT IDENTITY(1, 1) NOT NULL CONSTRAINT PK_EntityAcl PRIMARY KEY,
        EntityId           INT NOT NULL CONSTRAINT FK_EntityAcl_Entity REFERENCES dbo.Entity(EntityId),
        PrincipalObjectId  UNIQUEIDENTIFIER NOT NULL,
        PrincipalType      NVARCHAR(50) NOT NULL, -- e.g. User, Group, App
        CanWrite           BIT NOT NULL CONSTRAINT DF_EntityAcl_CanWrite DEFAULT (0),
        CanApprove         BIT NOT NULL CONSTRAINT DF_EntityAcl_CanApprove DEFAULT (0),
        CreatedUtc         DATETIME2(3) NOT NULL CONSTRAINT DF_EntityAcl_CreatedUtc DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT UQ_EntityAcl_Principal UNIQUE (EntityId, PrincipalObjectId)
    );
END;
GO

-------------------------------------------------------------------------------
-- Approvals
-------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.ApprovalInstance', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ApprovalInstance
    (
        ApprovalInstanceId BIGINT IDENTITY(1, 1) NOT NULL CONSTRAINT PK_ApprovalInstance PRIMARY KEY,
        EntityId           INT NOT NULL CONSTRAINT FK_ApprovalInstance_Entity REFERENCES dbo.Entity(EntityId),
        ApprovalType       NVARCHAR(50) NOT NULL,
        Status             NVARCHAR(30) NOT NULL,
        RequestedBy        NVARCHAR(256) NOT NULL,
        RequestedUtc       DATETIME2(3) NOT NULL CONSTRAINT DF_ApprovalInstance_RequestedUtc DEFAULT (SYSUTCDATETIME()),
        LastStatusUtc      DATETIME2(3) NULL,
        RequestId          UNIQUEIDENTIFIER NOT NULL,
        CONSTRAINT UQ_ApprovalInstance_Request UNIQUE (RequestId)
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ApprovalInstance_Entity' AND object_id = OBJECT_ID(N'dbo.ApprovalInstance'))
BEGIN
    CREATE INDEX IX_ApprovalInstance_Entity ON dbo.ApprovalInstance(EntityId);
END;
GO

IF OBJECT_ID(N'dbo.ApprovalAction', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ApprovalAction
    (
        ApprovalActionId   BIGINT IDENTITY(1, 1) NOT NULL CONSTRAINT PK_ApprovalAction PRIMARY KEY,
        ApprovalInstanceId BIGINT NOT NULL CONSTRAINT FK_ApprovalAction_Instance REFERENCES dbo.ApprovalInstance(ApprovalInstanceId),
        ActionName         NVARCHAR(30) NOT NULL,
        ActionBy           NVARCHAR(256) NOT NULL,
        ActionUtc          DATETIME2(3) NOT NULL CONSTRAINT DF_ApprovalAction_ActionUtc DEFAULT (SYSUTCDATETIME()),
        Comment            NVARCHAR(1024) NULL,
        RequestId          UNIQUEIDENTIFIER NOT NULL,
        CONSTRAINT UQ_ApprovalAction_Request UNIQUE (RequestId)
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ApprovalAction_Instance' AND object_id = OBJECT_ID(N'dbo.ApprovalAction'))
BEGIN
    CREATE INDEX IX_ApprovalAction_Instance ON dbo.ApprovalAction(ApprovalInstanceId);
END;
GO

-------------------------------------------------------------------------------
-- Seed data
-------------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.EntityType WHERE Name = N'Account')
INSERT INTO dbo.EntityType (Name, Description)
VALUES (N'Account', N'Customer account record');

IF NOT EXISTS (SELECT 1 FROM dbo.EntityType WHERE Name = N'Opportunity')
INSERT INTO dbo.EntityType (Name, Description)
VALUES (N'Opportunity', N'Opportunity or deal record');
GO

DECLARE @AccountTypeId INT = (SELECT TOP 1 EntityTypeId FROM dbo.EntityType WHERE Name = N'Account');
DECLARE @OpportunityTypeId INT = (SELECT TOP 1 EntityTypeId FROM dbo.EntityType WHERE Name = N'Opportunity');

IF NOT EXISTS (SELECT 1 FROM dbo.Entity WHERE ExternalReference = N'ACCT-1001')
INSERT INTO dbo.Entity (EntityTypeId, ExternalReference, DisplayName)
VALUES (@AccountTypeId, N'ACCT-1001', N'Fabrikam Retail Account');

IF NOT EXISTS (SELECT 1 FROM dbo.Entity WHERE ExternalReference = N'OPP-2001')
INSERT INTO dbo.Entity (EntityTypeId, ExternalReference, DisplayName)
VALUES (@OpportunityTypeId, N'OPP-2001', N'Contoso Expansion Opportunity');
GO

DECLARE @AccountEntityId INT = (SELECT TOP 1 EntityId FROM dbo.Entity WHERE ExternalReference = N'ACCT-1001');
DECLARE @OpportunityEntityId INT = (SELECT TOP 1 EntityId FROM dbo.Entity WHERE ExternalReference = N'OPP-2001');

IF NOT EXISTS (SELECT 1 FROM dbo.EntityAcl WHERE EntityId = @AccountEntityId AND PrincipalObjectId = '00000000-0000-0000-0000-000000000111')
INSERT INTO dbo.EntityAcl (EntityId, PrincipalObjectId, PrincipalType, CanWrite, CanApprove)
VALUES (@AccountEntityId, '00000000-0000-0000-0000-000000000111', N'User', 1, 1);

IF NOT EXISTS (SELECT 1 FROM dbo.EntityAcl WHERE EntityId = @OpportunityEntityId AND PrincipalObjectId = '00000000-0000-0000-0000-000000000222')
INSERT INTO dbo.EntityAcl (EntityId, PrincipalObjectId, PrincipalType, CanWrite, CanApprove)
VALUES (@OpportunityEntityId, '00000000-0000-0000-0000-000000000222', N'User', 1, 0);
GO

-------------------------------------------------------------------------------
-- Stored procedures
-------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.usp_EntityNote_Write
    @RequestId UNIQUEIDENTIFIER,
    @EntityExternalReference NVARCHAR(100),
    @NoteType NVARCHAR(50),
    @NoteText NVARCHAR(MAX),
    @CreatedBy NVARCHAR(256)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @EntityId INT;

    SELECT @EntityId = EntityId
    FROM dbo.Entity
    WHERE ExternalReference = @EntityExternalReference;

    IF @EntityId IS NULL
    BEGIN
        THROW 50001, 'Entity not found for supplied reference.', 1;
    END;

    DECLARE @ExistingNoteId BIGINT;

    SELECT @ExistingNoteId = EntityNoteId
    FROM dbo.EntityNote
    WHERE RequestId = @RequestId;

    IF @ExistingNoteId IS NOT NULL
    BEGIN
        SELECT
            EntityNoteId = @ExistingNoteId,
            EntityId,
            EntityExternalReference = @EntityExternalReference,
            NoteType,
            NoteText,
            CreatedBy,
            CreatedUtc,
            RequestId
        FROM dbo.EntityNote
        WHERE EntityNoteId = @ExistingNoteId;

        RETURN;
    END;

    INSERT INTO dbo.EntityNote (EntityId, NoteType, NoteText, CreatedBy, RequestId)
    VALUES (@EntityId, @NoteType, @NoteText, @CreatedBy, @RequestId);

    DECLARE @NewNoteId BIGINT = SCOPE_IDENTITY();

    SELECT
        EntityNoteId = @NewNoteId,
        EntityId     = @EntityId,
        EntityExternalReference = @EntityExternalReference,
        NoteType,
        NoteText,
        CreatedBy,
        CreatedUtc,
        RequestId
    FROM dbo.EntityNote
    WHERE EntityNoteId = @NewNoteId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Approval_Start
    @RequestId UNIQUEIDENTIFIER,
    @EntityExternalReference NVARCHAR(100),
    @ApprovalType NVARCHAR(50),
    @RequestedBy NVARCHAR(256)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @EntityId INT;

    SELECT @EntityId = EntityId
    FROM dbo.Entity
    WHERE ExternalReference = @EntityExternalReference;

    IF @EntityId IS NULL
    BEGIN
        THROW 50002, 'Entity not found for supplied reference.', 1;
    END;

    DECLARE @ExistingInstanceId BIGINT;

    SELECT @ExistingInstanceId = ApprovalInstanceId
    FROM dbo.ApprovalInstance
    WHERE RequestId = @RequestId;

    IF @ExistingInstanceId IS NULL
    BEGIN
        INSERT INTO dbo.ApprovalInstance (EntityId, ApprovalType, Status, RequestedBy, LastStatusUtc, RequestId)
        VALUES (@EntityId, @ApprovalType, N'Pending', @RequestedBy, SYSUTCDATETIME(), @RequestId);

        SET @ExistingInstanceId = SCOPE_IDENTITY();
    END;

    SELECT
        ApprovalInstanceId = @ExistingInstanceId,
        EntityExternalReference = @EntityExternalReference,
        ApprovalType,
        Status,
        RequestedBy,
        RequestedUtc,
        LastStatusUtc,
        RequestId
    FROM dbo.ApprovalInstance
    WHERE ApprovalInstanceId = @ExistingInstanceId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Approval_Action
    @RequestId UNIQUEIDENTIFIER,
    @ApprovalInstanceId BIGINT,
    @ActionName NVARCHAR(30),
    @ActionBy NVARCHAR(256),
    @Comment NVARCHAR(1024) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.ApprovalInstance WHERE ApprovalInstanceId = @ApprovalInstanceId)
    BEGIN
        THROW 50003, 'Approval instance not found.', 1;
    END;

    DECLARE @ExistingActionId BIGINT;

    SELECT @ExistingActionId = ApprovalActionId
    FROM dbo.ApprovalAction
    WHERE RequestId = @RequestId;

    IF @ExistingActionId IS NULL
    BEGIN
        INSERT INTO dbo.ApprovalAction (ApprovalInstanceId, ActionName, ActionBy, Comment, RequestId)
        VALUES (@ApprovalInstanceId, @ActionName, @ActionBy, @Comment, @RequestId);

        SET @ExistingActionId = SCOPE_IDENTITY();

        UPDATE dbo.ApprovalInstance
        SET Status = @ActionName,
            LastStatusUtc = SYSUTCDATETIME()
        WHERE ApprovalInstanceId = @ApprovalInstanceId;
    END;

    SELECT
        ApprovalActionId = @ExistingActionId,
        ApprovalInstanceId,
        ActionName,
        ActionBy,
        ActionUtc,
        Comment,
        RequestId
    FROM dbo.ApprovalAction
    WHERE ApprovalActionId = @ExistingActionId;
END;
GO

-------------------------------------------------------------------------------
-- Views
-------------------------------------------------------------------------------
CREATE OR ALTER VIEW dbo.vApprovalStatus
AS
    SELECT
        ai.ApprovalInstanceId,
        ai.EntityId,
        e.ExternalReference AS EntityExternalReference,
        ai.ApprovalType,
        ai.Status,
        ai.RequestedBy,
        ai.RequestedUtc,
        ai.LastStatusUtc,
        lastAction.ActionName AS LastActionName,
        lastAction.ActionBy AS LastActionBy,
        lastAction.ActionUtc AS LastActionUtc
    FROM dbo.ApprovalInstance ai
    INNER JOIN dbo.Entity e ON e.EntityId = ai.EntityId
    OUTER APPLY
    (
        SELECT TOP (1)
            aa.ActionName,
            aa.ActionBy,
            aa.ActionUtc
        FROM dbo.ApprovalAction aa
        WHERE aa.ApprovalInstanceId = ai.ApprovalInstanceId
        ORDER BY aa.ActionUtc DESC, aa.ApprovalActionId DESC
    ) lastAction;
GO

-- Security grants for the Logic App managed identity are handled separately in
-- ops/sql/grant_logicapp.sql, since creating an EXTERNAL PROVIDER user requires
-- connecting with an Azure AD administrator.
