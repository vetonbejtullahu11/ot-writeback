SET NOCOUNT ON;

DECLARE @CleanupNote UNIQUEIDENTIFIER = NULL;
DECLARE @CleanupInstance BIGINT = NULL;
DECLARE @InsertedRuleId BIGINT = NULL;
DECLARE @InsertedRule BIT = 0;
DECLARE @HasError BIT = 0;
DECLARE @ErrorMessage NVARCHAR(4000) = NULL;
DECLARE @ErrorSeverity INT = 0;
DECLARE @ErrorState INT = 0;

BEGIN TRY
    -----------------------------------------------------------------------
    -- EntityNote idempotency and audit insert
    -----------------------------------------------------------------------
    PRINT '--- Smoke Test: EntityNote RequestId idempotency ---';

    DECLARE @NoteEntityType VARCHAR(64) = 'SmokeEntity';
    DECLARE @NoteBusinessKey VARCHAR(128) = CONCAT('SMOKE-', CONVERT(VARCHAR(36), NEWID()));
    DECLARE @NoteRequest UNIQUEIDENTIFIER = NEWID();

    INSERT dbo.EntityNote
        (EntityType, BusinessKey, NoteText, TagsCsv, CreatedByUPN, CreatedByDisplay,
         CreatedIPAddress, ClientReportName, VisibilityScope, RequestId, SourceSystem, CorrelationId)
    VALUES
        (@NoteEntityType, @NoteBusinessKey, N'Smoke test note',
         N'audit,smoke', 'smoke@test.local', N'Smoke Tester',
         '127.0.0.1', N'Smoke Harness', 'Team', @NoteRequest, 'SmokeScript', @NoteRequest);

    SET @CleanupNote = @NoteRequest;

    BEGIN TRY
        INSERT dbo.EntityNote
            (EntityType, BusinessKey, NoteText, CreatedByUPN, VisibilityScope, RequestId, SourceSystem)
        VALUES
            (@NoteEntityType, @NoteBusinessKey, N'Should fail', 'smoke@test.local', 'Team', @NoteRequest, 'SmokeScript');

        -- If we get here, uniqueness didn''t fire
        THROW 61000, 'EntityNote idempotency check failed (duplicate RequestId inserted).', 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() NOT IN (2601, 2627)
            THROW;
        PRINT 'Duplicate RequestId rejected as expected.';
    END CATCH;

    IF NOT EXISTS (SELECT 1 FROM dbo.EntityNote WHERE RequestId = @NoteRequest)
        THROW 61001, 'Smoke note missing after insert.', 1;

    -----------------------------------------------------------------------
    -- Approval workflow happy path
    -----------------------------------------------------------------------
    PRINT '--- Smoke Test: Approval workflow happy path ---';

    DECLARE @ApprovalEntityType VARCHAR(64) = 'SmokeApproval';
    DECLARE @ApprovalStage VARCHAR(64) = 'Submit';
    DECLARE @BusinessKey VARCHAR(128) = CONCAT('SMOKE-', CONVERT(VARCHAR(36), NEWID()));
    DECLARE @ApproverUPN VARCHAR(256) = 'approver.smoke@test.local';

    IF NOT EXISTS (
        SELECT 1 FROM dbo.ApproverRule
        WHERE EntityType = @ApprovalEntityType
          AND StageCode = @ApprovalStage
          AND ApproverScope = 'User'
          AND ApproverRef = @ApproverUPN
    )
    BEGIN
        INSERT dbo.ApproverRule (EntityType, StageCode, ApproverScope, ApproverRef, RequireMode, Priority)
        VALUES (@ApprovalEntityType, @ApprovalStage, 'User', @ApproverUPN, 'All', 10);
        SET @InsertedRuleId = SCOPE_IDENTITY();
        SET @InsertedRule = 1;
    END

    DECLARE @StartOutput TABLE (InstanceID BIGINT);

    INSERT INTO @StartOutput
    EXEC dbo.usp_Approval_Start
        @EntityType = @ApprovalEntityType,
        @BusinessKey = @BusinessKey,
        @RequestedByUPN = 'requestor.smoke@test.local',
        @StageCode = @ApprovalStage;

    SELECT TOP 1 @CleanupInstance = InstanceID FROM @StartOutput;

    IF @CleanupInstance IS NULL
        THROW 62000, 'Approval start failed to return an InstanceID.', 1;

    IF NOT EXISTS (
        SELECT 1 FROM dbo.ApprovalAssignment
        WHERE InstanceID = @CleanupInstance AND ApproverRef = @ApproverUPN
    )
        THROW 62001, 'Approval assignments not generated for smoke approver.', 1;

    EXEC dbo.usp_Approval_Action
        @InstanceID = @CleanupInstance,
        @ActorUPN = @ApproverUPN,
        @ActionType = 'Approve',
        @Comment = N'Smoke approval executed.',
        @RequestId = NEWID(),
        @SourceSystem = 'SmokeScript';

    IF NOT EXISTS (
        SELECT 1 FROM dbo.ApprovalInstance
        WHERE InstanceID = @CleanupInstance AND Status = 'Approved'
    )
        THROW 62002, 'Approval instance did not reach Approved status.', 1;

    PRINT 'Approval workflow run succeeded.';

END TRY
BEGIN CATCH
    SET @HasError = 1;
    SELECT
        @ErrorMessage = ERROR_MESSAGE(),
        @ErrorSeverity = ERROR_SEVERITY(),
        @ErrorState = ERROR_STATE();
END CATCH;

-- Cleanup artifacts so repeated runs stay idempotent
IF @CleanupInstance IS NOT NULL
BEGIN
    DELETE FROM dbo.ApprovalInstance WHERE InstanceID = @CleanupInstance;
END

IF @InsertedRule = 1 AND @InsertedRuleId IS NOT NULL
    DELETE FROM dbo.ApproverRule WHERE RuleID = @InsertedRuleId;

IF @CleanupNote IS NOT NULL
    DELETE FROM dbo.EntityNote WHERE RequestId = @CleanupNote;

IF @HasError = 1
BEGIN
    RAISERROR (ISNULL(@ErrorMessage, 'Smoke test failure.'), ISNULL(NULLIF(@ErrorSeverity, 0), 16), ISNULL(NULLIF(@ErrorState, 0), 1));
END
ELSE
BEGIN
    PRINT 'Smoke tests completed successfully.';
END
