SET NOCOUNT ON;

PRINT '--- Smoke Test: EntityNote idempotent insert ---';
DECLARE @NoteRequest UNIQUEIDENTIFIER = NEWID();

DECLARE @FirstNote TABLE
(
    EntityNoteId BIGINT,
    EntityId INT,
    EntityExternalReference NVARCHAR(100),
    NoteType NVARCHAR(50),
    NoteText NVARCHAR(MAX),
    CreatedBy NVARCHAR(256),
    CreatedUtc DATETIME2(3),
    RequestId UNIQUEIDENTIFIER
);

DECLARE @NoteText NVARCHAR(MAX) = N'Smoke test note created at ' + CONVERT(NVARCHAR(30), SYSUTCDATETIME(), 126);

INSERT INTO @FirstNote
EXEC dbo.usp_EntityNote_Write
    @RequestId = @NoteRequest,
    @EntityExternalReference = N'ACCT-1001',
    @NoteType = N'General',
    @NoteText = @NoteText,
    @CreatedBy = N'smoke@test.local';

DECLARE @NoteId BIGINT = (SELECT TOP 1 EntityNoteId FROM @FirstNote);

IF @NoteId IS NULL
    THROW 51000, 'EntityNote insert failed.', 1;

DECLARE @SecondNote TABLE
(
    EntityNoteId BIGINT,
    EntityId INT,
    EntityExternalReference NVARCHAR(100),
    NoteType NVARCHAR(50),
    NoteText NVARCHAR(MAX),
    CreatedBy NVARCHAR(256),
    CreatedUtc DATETIME2(3),
    RequestId UNIQUEIDENTIFIER
);

INSERT INTO @SecondNote
EXEC dbo.usp_EntityNote_Write
    @RequestId = @NoteRequest,
    @EntityExternalReference = N'ACCT-1001',
    @NoteType = N'General',
    @NoteText = N'Smoke test duplicate note',
    @CreatedBy = N'smoke@test.local';

DECLARE @NoteIdRepeat BIGINT = (SELECT TOP 1 EntityNoteId FROM @SecondNote);

IF @NoteId <> @NoteIdRepeat
    THROW 51001, 'EntityNote idempotency check failed (duplicate note created).', 1;

PRINT 'EntityNote idempotency check passed.';

PRINT '--- Smoke Test: Approval workflow happy path ---';

DECLARE @ApprovalStart UNIQUEIDENTIFIER = NEWID();
DECLARE @Approval TABLE
(
    ApprovalInstanceId BIGINT,
    EntityExternalReference NVARCHAR(100),
    ApprovalType NVARCHAR(50),
    Status NVARCHAR(30),
    RequestedBy NVARCHAR(256),
    RequestedUtc DATETIME2(3),
    LastStatusUtc DATETIME2(3),
    RequestId UNIQUEIDENTIFIER
);

INSERT INTO @Approval
EXEC dbo.usp_Approval_Start
    @RequestId = @ApprovalStart,
    @EntityExternalReference = N'OPP-2001',
    @ApprovalType = N'Writeback',
    @RequestedBy = N'smoke@test.local';

DECLARE @ApprovalInstanceId BIGINT = (SELECT TOP 1 ApprovalInstanceId FROM @Approval);

IF @ApprovalInstanceId IS NULL
    THROW 52000, 'Approval start failed.', 1;

DECLARE @ApprovalActionRequest UNIQUEIDENTIFIER = NEWID();
DECLARE @ApprovalAction TABLE
(
    ApprovalActionId BIGINT,
    ApprovalInstanceId BIGINT,
    ActionName NVARCHAR(30),
    ActionBy NVARCHAR(256),
    ActionUtc DATETIME2(3),
    Comment NVARCHAR(1024),
    RequestId UNIQUEIDENTIFIER
);

INSERT INTO @ApprovalAction
EXEC dbo.usp_Approval_Action
    @RequestId = @ApprovalActionRequest,
    @ApprovalInstanceId = @ApprovalInstanceId,
    @ActionName = N'Approved',
    @ActionBy = N'smoke-approver@test.local',
    @Comment = N'Smoke approval executed.';

IF NOT EXISTS (SELECT 1 FROM @ApprovalAction WHERE ApprovalInstanceId = @ApprovalInstanceId)
    THROW 52001, 'Approval action failed.', 1;

SELECT
    StatusSnapshot = 'After Approval Action',
    v.*
FROM dbo.vApprovalStatus v
WHERE v.ApprovalInstanceId = @ApprovalInstanceId;

PRINT 'Smoke tests completed successfully.';
