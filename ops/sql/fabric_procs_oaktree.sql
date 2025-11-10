/* 
Oaktree IPS — Fabric-Only Stored Procedures
Author: Inspire11
Generated: 2025-11-10T14:42:25.499989 UTC

Notes:
- Designed for Microsoft Fabric Data Warehouse SQL endpoint.
- Avoids IDENTITY, enforced PK/UNIQUE, MERGE, and CREATE INDEX.
- Uses GUID keys and explicit idempotency via @RequestId.
- All writes are append-only except instance Status/ClosedUTC summary fields.
- Tables expected: Entity, EntityNote, ApprovalInstance, ApprovalAssignment, ApprovalAction, ApproverRule, ApprovalException, EntityAcl, RequestLog.
- Adjust NVARCHAR lengths to your standards if needed.
*/

/* ==========================================================================
   1) Notes (Comments)
   ========================================================================== */

CREATE OR ALTER PROCEDURE dbo.usp_Note_Add
  @EntityType          NVARCHAR(100),
  @BusinessKey         NVARCHAR(200),
  @NoteText            NVARCHAR(MAX),
  @TagsCsv             NVARCHAR(4000) = NULL,
  @VisibilityScope     NVARCHAR(32)   = N'Team', -- e.g., 'Private','Team','Org'
  @AttachmentUrl       NVARCHAR(2048) = NULL,
  @ActorUPN            NVARCHAR(320),
  @RequestId           UNIQUEIDENTIFIER
AS
BEGIN
  SET NOCOUNT ON;

  DECLARE @Now DATETIME2(7) = SYSUTCDATETIME();
  IF @RequestId IS NULL SET @RequestId = NEWID();

  -- Idempotency: if this RequestId already processed, return that row.
  IF EXISTS (SELECT 1 FROM dbo.EntityNote WHERE RequestId = @RequestId)
  BEGIN
    SELECT TOP(1)
      NoteId, EntityType, BusinessKey, CreatedUTC, CreatedByUPN
    FROM dbo.EntityNote WHERE RequestId = @RequestId;
    RETURN;
  END

  DECLARE @NoteId UNIQUEIDENTIFIER = NEWID();

  BEGIN TRY
    -- Best-effort request log
    IF NOT EXISTS (SELECT 1 FROM dbo.RequestLog WHERE RequestId = @RequestId)
    BEGIN
      INSERT INTO dbo.RequestLog(RequestId, RequestType, FirstSeenUTC, ActorUPN, EntityType, BusinessKey)
      VALUES(@RequestId, N'Note_Add', @Now, @ActorUPN, @EntityType, @BusinessKey);
    END

    INSERT INTO dbo.EntityNote
    (
      NoteId, EntityType, BusinessKey, NoteText, TagsCsv, VisibilityScope,
      AttachmentUrl, CreatedByUPN, CreatedUTC, RequestId
    )
    VALUES
    (
      @NoteId, @EntityType, @BusinessKey, @NoteText, @TagsCsv, @VisibilityScope,
      @AttachmentUrl, @ActorUPN, @Now, @RequestId
    );

    SELECT @NoteId AS NoteId, @Now AS CreatedUTC;
  END TRY
  BEGIN CATCH
    -- If a race created the row, return it; else bubble up
    IF EXISTS (SELECT 1 FROM dbo.EntityNote WHERE RequestId = @RequestId)
      SELECT TOP(1) NoteId, CreatedUTC FROM dbo.EntityNote WHERE RequestId = @RequestId;
    ELSE
      THROW;
  END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Note_ListByEntity
  @EntityType  NVARCHAR(100),
  @BusinessKey NVARCHAR(200),
  @TopN        INT = 50
AS
BEGIN
  SET NOCOUNT ON;
  SELECT TOP (@TopN)
      NoteId, EntityType, BusinessKey, NoteText, TagsCsv, VisibilityScope,
      AttachmentUrl, CreatedByUPN, CreatedUTC
  FROM dbo.EntityNote
  WHERE EntityType = @EntityType AND BusinessKey = @BusinessKey
  ORDER BY CreatedUTC DESC;
END
GO

/* ==========================================================================
   2) Approvals (Instances, Assignments, Actions)
   ========================================================================== */

CREATE OR ALTER PROCEDURE dbo.usp_Approval_Start
  @EntityType     NVARCHAR(100),
  @BusinessKey    NVARCHAR(200),
  @StageCode      NVARCHAR(64)  = N'Submit',
  @RuleKey        NVARCHAR(128) = N'default',
  @ApprovalMode   NVARCHAR(16)  = N'All',     -- 'All' | 'Any' | 'Quorum'
  @Threshold      INT           = NULL,       -- required if ApprovalMode='Quorum'
  @RequestedByUPN NVARCHAR(320),
  @ForceNew       BIT           = 0,          -- if 1, creates a new instance even if one is open
  @RequestId      UNIQUEIDENTIFIER
AS
BEGIN
  SET NOCOUNT ON;

  DECLARE @Now DATETIME2(7) = SYSUTCDATETIME();
  IF @RequestId IS NULL SET @RequestId = NEWID();

  -- Idempotency by RequestId
  IF EXISTS (SELECT 1 FROM dbo.ApprovalInstance WHERE RequestId = @RequestId)
  BEGIN
    SELECT TOP(1) InstanceId, Status, StageCode, ApprovalMode, Threshold, CreatedUTC
    FROM dbo.ApprovalInstance WHERE RequestId = @RequestId;
    RETURN;
  END

  -- Reuse existing open instance unless forced
  IF @ForceNew = 0
  BEGIN
    IF EXISTS (SELECT 1 FROM dbo.ApprovalInstance 
               WHERE EntityType=@EntityType AND BusinessKey=@BusinessKey 
                 AND StageCode=@StageCode AND Status = N'InProgress')
    BEGIN
      SELECT TOP(1) InstanceId, Status, StageCode, ApprovalMode, Threshold, CreatedUTC
      FROM dbo.ApprovalInstance
      WHERE EntityType=@EntityType AND BusinessKey=@BusinessKey 
        AND StageCode=@StageCode AND Status = N'InProgress'
      ORDER BY CreatedUTC DESC;
      RETURN;
    END
  END

  DECLARE @InstanceId UNIQUEIDENTIFIER = NEWID();

  BEGIN TRY
    BEGIN TRAN;

    -- Request log
    IF NOT EXISTS (SELECT 1 FROM dbo.RequestLog WHERE RequestId = @RequestId)
    BEGIN
      INSERT INTO dbo.RequestLog(RequestId, RequestType, FirstSeenUTC, ActorUPN, EntityType, BusinessKey)
      VALUES(@RequestId, N'Approval_Start', @Now, @RequestedByUPN, @EntityType, @BusinessKey);
    END

    -- Create instance
    INSERT INTO dbo.ApprovalInstance
    (
      InstanceId, EntityType, BusinessKey, StageCode, Status,
      ApprovalMode, Threshold, RequestedByUPN, RequestedUTC, RequestId
    )
    VALUES
    (
      @InstanceId, @EntityType, @BusinessKey, @StageCode, N'InProgress',
      @ApprovalMode, @Threshold, @RequestedByUPN, @Now, @RequestId
    );

    /* Expand assignments from rules + exceptions (adds/waives).
       ApproverRule: RuleKey, Stage, ApproverUPN, Required (bit)
       ApprovalException (active): EntityType, BusinessKey, Stage, ExceptionKind ('Add'|'Waive'), ApproverUPN
    */
    ;WITH base AS (
      SELECT LOWER(ApproverUPN) AS ApproverUPN, CAST(ISNULL(Required,1) AS BIT) AS Required
      FROM dbo.ApproverRule
      WHERE RuleKey = @RuleKey AND Stage = @StageCode
    ),
    adds AS (
      SELECT LOWER(ApproverUPN) AS ApproverUPN, CAST(1 AS BIT) AS Required
      FROM dbo.ApprovalException
      WHERE EntityType=@EntityType AND BusinessKey=@BusinessKey AND Stage=@StageCode
        AND ExceptionKind = N'Add'
        AND (EffectiveFromUTC IS NULL OR EffectiveFromUTC <= @Now)
        AND (EffectiveToUTC   IS NULL OR EffectiveToUTC   >= @Now)
    ),
    waived AS (
      SELECT LOWER(ApproverUPN) AS ApproverUPN
      FROM dbo.ApprovalException
      WHERE EntityType=@EntityType AND BusinessKey=@BusinessKey AND Stage=@StageCode
        AND ExceptionKind = N'Waive'
        AND (EffectiveFromUTC IS NULL OR EffectiveFromUTC <= @Now)
        AND (EffectiveToUTC   IS NULL OR EffectiveToUTC   >= @Now)
    ),
    unioned AS (
      SELECT ApproverUPN, Required FROM base
      UNION ALL
      SELECT ApproverUPN, Required FROM adds
    ),
    final AS (
      SELECT ApproverUPN, MAX(CASE WHEN Required=1 THEN 1 ELSE 0 END) AS Required
      FROM unioned
      WHERE ApproverUPN NOT IN (SELECT ApproverUPN FROM waived)
      GROUP BY ApproverUPN
    )
    INSERT INTO dbo.ApprovalAssignment(AssignmentId, InstanceId, ApproverUPN, Stage, Required, CreatedUTC)
    SELECT NEWID(), @InstanceId, f.ApproverUPN, @StageCode, f.Required, @Now
    FROM final f;

    COMMIT TRAN;

    SELECT @InstanceId AS InstanceId, N'InProgress' AS Status, @StageCode AS StageCode,
           @ApprovalMode AS ApprovalMode, @Threshold AS Threshold, @Now AS CreatedUTC;
  END TRY
  BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRAN;
    -- If idempotent duplicate snuck in, return it
    IF EXISTS (SELECT 1 FROM dbo.ApprovalInstance WHERE RequestId = @RequestId)
      SELECT TOP(1) InstanceId, Status, StageCode, ApprovalMode, Threshold, CreatedUTC
      FROM dbo.ApprovalInstance WHERE RequestId = @RequestId;
    ELSE
      THROW;
  END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Approval_Action
  @InstanceId   UNIQUEIDENTIFIER,
  @ActionType   NVARCHAR(16),   -- 'Approve' | 'Reject' | 'Comment'
  @Comment      NVARCHAR(2000) = NULL,
  @ActorUPN     NVARCHAR(320),
  @RequestId    UNIQUEIDENTIFIER
AS
BEGIN
  SET NOCOUNT ON;

  DECLARE @Now DATETIME2(7) = SYSUTCDATETIME();
  IF @RequestId IS NULL SET @RequestId = NEWID();

  -- Return existing action if same RequestId
  IF EXISTS (SELECT 1 FROM dbo.ApprovalAction WHERE RequestId = @RequestId)
  BEGIN
    SELECT TOP(1) a.ActionId, a.ActionUTC, i.Status AS StatusAfter
    FROM dbo.ApprovalAction a
    JOIN dbo.ApprovalInstance i ON i.InstanceId = a.InstanceId
    WHERE a.RequestId = @RequestId;
    RETURN;
  END

  DECLARE @ActionId UNIQUEIDENTIFIER = NEWID();

  BEGIN TRY
    BEGIN TRAN;

    INSERT INTO dbo.ApprovalAction(ActionId, InstanceId, ActorUPN, ActionType, Comment, ActionUTC, RequestId)
    VALUES(@ActionId, @InstanceId, @ActorUPN, @ActionType, @Comment, @Now, @RequestId);

    -- Compute status
    DECLARE @Mode NVARCHAR(16), @Threshold INT, @Status NVARCHAR(32);
    SELECT @Mode = ApprovalMode, @Threshold = Threshold, @Status = Status
    FROM dbo.ApprovalInstance WHERE InstanceId = @InstanceId;

    -- Tally
    DECLARE @Assigned INT =
      (SELECT COUNT(DISTINCT ApproverUPN) FROM dbo.ApprovalAssignment WHERE InstanceId = @InstanceId);

    DECLARE @Approved INT =
      (SELECT COUNT(DISTINCT ActorUPN) FROM dbo.ApprovalAction 
       WHERE InstanceId = @InstanceId AND ActionType = N'Approve');

    DECLARE @Rejected INT =
      (SELECT COUNT(1) FROM dbo.ApprovalAction 
       WHERE InstanceId = @InstanceId AND ActionType = N'Reject');

    DECLARE @StatusAfter NVARCHAR(32) = N'InProgress';

    IF @Rejected > 0
      SET @StatusAfter = N'Rejected';
    ELSE IF @Mode = N'All' AND @Assigned > 0 AND @Approved >= @Assigned
      SET @StatusAfter = N'Approved';
    ELSE IF @Mode = N'Any' AND @Approved >= 1
      SET @StatusAfter = N'Approved';
    ELSE IF @Mode = N'Quorum' AND @Threshold IS NOT NULL AND @Approved >= @Threshold
      SET @StatusAfter = N'Approved';
    ELSE
      SET @StatusAfter = N'InProgress';

    -- Update instance summary (optional convenience; source of truth is actions/assignments)
    UPDATE dbo.ApprovalInstance
      SET Status = @StatusAfter,
          ClosedUTC = CASE WHEN @StatusAfter IN (N'Approved', N'Rejected') THEN @Now ELSE NULL END
    WHERE InstanceId = @InstanceId;

    COMMIT TRAN;

    SELECT @ActionId AS ActionId, @Now AS ActionUTC, @StatusAfter AS StatusAfter, 
           @Approved AS ApprovedCount, @Assigned AS AssignedCount, @Rejected AS RejectedCount;
  END TRY
  BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRAN;
    IF EXISTS (SELECT 1 FROM dbo.ApprovalAction WHERE RequestId = @RequestId)
    BEGIN
      SELECT TOP(1) a.ActionId, a.ActionUTC, i.Status AS StatusAfter
      FROM dbo.ApprovalAction a
      JOIN dbo.ApprovalInstance i ON i.InstanceId = a.InstanceId
      WHERE a.RequestId = @RequestId;
    END
    ELSE
      THROW;
  END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Approval_GetStatus
  @InstanceId UNIQUEIDENTIFIER
AS
BEGIN
  SET NOCOUNT ON;

  DECLARE @Mode NVARCHAR(16), @Threshold INT, @Status NVARCHAR(32), @Stage NVARCHAR(64), @RequestedUTC DATETIME2(7);
  SELECT @Mode = ApprovalMode, @Threshold = Threshold, @Status = Status, @Stage = StageCode, @RequestedUTC = RequestedUTC
  FROM dbo.ApprovalInstance WHERE InstanceId = @InstanceId;

  SELECT TOP(1)
      i.InstanceId, i.EntityType, i.BusinessKey, i.StageCode, i.Status,
      i.ApprovalMode, i.Threshold, i.RequestedByUPN, i.RequestedUTC, i.ClosedUTC,
      (SELECT COUNT(DISTINCT ApproverUPN) FROM dbo.ApprovalAssignment WHERE InstanceId = i.InstanceId) AS AssignedCount,
      (SELECT COUNT(DISTINCT ActorUPN) FROM dbo.ApprovalAction WHERE InstanceId = i.InstanceId AND ActionType = N'Approve') AS ApprovedCount,
      (SELECT COUNT(1) FROM dbo.ApprovalAction WHERE InstanceId = i.InstanceId AND ActionType = N'Reject') AS RejectedEvents
  FROM dbo.ApprovalInstance i
  WHERE i.InstanceId = @InstanceId;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Approval_StatusForEntity
  @EntityType  NVARCHAR(100),
  @BusinessKey NVARCHAR(200)
AS
BEGIN
  SET NOCOUNT ON;

  DECLARE @InstanceId UNIQUEIDENTIFIER =
    (SELECT TOP(1) InstanceId FROM dbo.ApprovalInstance
     WHERE EntityType=@EntityType AND BusinessKey=@BusinessKey
     ORDER BY RequestedUTC DESC);

  IF @InstanceId IS NULL
  BEGIN
    SELECT CAST(NULL AS UNIQUEIDENTIFIER) AS InstanceId, N'None' AS Status, NULL AS RequestedUTC;
    RETURN;
  END

  EXEC dbo.usp_Approval_GetStatus @InstanceId=@InstanceId;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Approval_Recalculate
  @InstanceId UNIQUEIDENTIFIER,
  @RuleKey    NVARCHAR(128),
  @NowUTC     DATETIME2(7) = NULL
AS
BEGIN
  SET NOCOUNT ON;
  IF @NowUTC IS NULL SET @NowUTC = SYSUTCDATETIME();

  DECLARE @EntityType NVARCHAR(100), @BusinessKey NVARCHAR(200), @Stage NVARCHAR(64);
  SELECT @EntityType = EntityType, @BusinessKey = BusinessKey, @Stage = StageCode
  FROM dbo.ApprovalInstance WHERE InstanceId = @InstanceId;

  ;WITH base AS (
    SELECT LOWER(ApproverUPN) AS ApproverUPN, CAST(ISNULL(Required,1) AS BIT) AS Required
    FROM dbo.ApproverRule
    WHERE RuleKey = @RuleKey AND Stage = @Stage
  ),
  adds AS (
    SELECT LOWER(ApproverUPN) AS ApproverUPN, CAST(1 AS BIT) AS Required
    FROM dbo.ApprovalException
    WHERE EntityType=@EntityType AND BusinessKey=@BusinessKey AND Stage=@Stage
      AND ExceptionKind = N'Add'
      AND (EffectiveFromUTC IS NULL OR EffectiveFromUTC <= @NowUTC)
      AND (EffectiveToUTC   IS NULL OR EffectiveToUTC   >= @NowUTC)
  ),
  waived AS (
    SELECT LOWER(ApproverUPN) AS ApproverUPN
    FROM dbo.ApprovalException
    WHERE EntityType=@EntityType AND BusinessKey=@BusinessKey AND Stage=@Stage
      AND ExceptionKind = N'Waive'
      AND (EffectiveFromUTC IS NULL OR EffectiveFromUTC <= @NowUTC)
      AND (EffectiveToUTC   IS NULL OR EffectiveToUTC   >= @NowUTC)
  ),
  unioned AS (
    SELECT ApproverUPN, Required FROM base
    UNION ALL
    SELECT ApproverUPN, Required FROM adds
  ),
  final AS (
    SELECT ApproverUPN, MAX(CASE WHEN Required=1 THEN 1 ELSE 0 END) AS Required
    FROM unioned
    WHERE ApproverUPN NOT IN (SELECT ApproverUPN FROM waived)
    GROUP BY ApproverUPN
  )
  INSERT INTO dbo.ApprovalAssignment(AssignmentId, InstanceId, ApproverUPN, Stage, Required, CreatedUTC)
  SELECT NEWID(), @InstanceId, f.ApproverUPN, @Stage, f.Required, @NowUTC
  FROM final f
  WHERE NOT EXISTS (
    SELECT 1 FROM dbo.ApprovalAssignment a
    WHERE a.InstanceId = @InstanceId AND a.ApproverUPN = f.ApproverUPN
  );
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_ApprovalException_Add
  @EntityType   NVARCHAR(100),
  @BusinessKey  NVARCHAR(200),
  @Stage        NVARCHAR(64),
  @ExceptionKind NVARCHAR(16),     -- 'Add' | 'Waive'
  @ApproverUPN  NVARCHAR(320),
  @EffectiveFromUTC DATETIME2(7) = NULL,
  @EffectiveToUTC   DATETIME2(7) = NULL,
  @EnteredByUPN NVARCHAR(320),
  @RequestId    UNIQUEIDENTIFIER
AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @Now DATETIME2(7) = SYSUTCDATETIME();
  IF @RequestId IS NULL SET @RequestId = NEWID();

  IF EXISTS (SELECT 1 FROM dbo.ApprovalException WHERE RequestId = @RequestId)
  BEGIN
    SELECT TOP(1) ExceptionId, EntityType, BusinessKey, Stage, ExceptionKind, ApproverUPN, EffectiveFromUTC, EffectiveToUTC
    FROM dbo.ApprovalException WHERE RequestId = @RequestId;
    RETURN;
  END

  DECLARE @ExceptionId UNIQUEIDENTIFIER = NEWID();

  INSERT INTO dbo.ApprovalException
  (ExceptionId, EntityType, BusinessKey, Stage, ExceptionKind, ApproverUPN,
   EffectiveFromUTC, EffectiveToUTC, EnteredByUPN, EnteredUTC, RequestId)
  VALUES
  (@ExceptionId, @EntityType, @BusinessKey, @Stage, @ExceptionKind, @ApproverUPN,
   @EffectiveFromUTC, @EffectiveToUTC, @EnteredByUPN, @Now, @RequestId);

  SELECT @ExceptionId AS ExceptionId;
END
GO

/* ==========================================================================
   3) Access Control (interim RLS helpers)
   ========================================================================== */

CREATE OR ALTER PROCEDURE dbo.usp_Acl_Upsert
  @EntityType   NVARCHAR(100),
  @BusinessKey  NVARCHAR(200),
  @PrincipalUPN NVARCHAR(320),
  @CanView      BIT,
  @CanComment   BIT = 0,
  @CanApprove   BIT = 0,
  @RequestId    UNIQUEIDENTIFIER = NULL
AS
BEGIN
  SET NOCOUNT ON;

  IF EXISTS (SELECT 1 FROM dbo.EntityAcl WHERE EntityType=@EntityType AND BusinessKey=@BusinessKey AND PrincipalUPN=@PrincipalUPN)
  BEGIN
    UPDATE dbo.EntityAcl
      SET CanView=@CanView, CanComment=@CanComment, CanApprove=@CanApprove
    WHERE EntityType=@EntityType AND BusinessKey=@BusinessKey AND PrincipalUPN=@PrincipalUPN;
  END
  ELSE
  BEGIN
    INSERT INTO dbo.EntityAcl(EntityType, BusinessKey, PrincipalUPN, CanView, CanComment, CanApprove)
    VALUES(@EntityType, @BusinessKey, @PrincipalUPN, @CanView, @CanComment, @CanApprove);
  END

  SELECT @EntityType AS EntityType, @BusinessKey AS BusinessKey, @PrincipalUPN AS PrincipalUPN;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Acl_Delete
  @EntityType   NVARCHAR(100),
  @BusinessKey  NVARCHAR(200),
  @PrincipalUPN NVARCHAR(320)
AS
BEGIN
  SET NOCOUNT ON;
  DELETE FROM dbo.EntityAcl
  WHERE EntityType=@EntityType AND BusinessKey=@BusinessKey AND PrincipalUPN=@PrincipalUPN;
  SELECT @@ROWCOUNT AS RowsDeleted;
END
GO

/* ==========================================================================
   4) Operations
   ========================================================================== */

CREATE OR ALTER PROCEDURE dbo.usp_RequestLog_Prune
  @OlderThanDays INT = 90
AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @Cut DATETIME2(7) = DATEADD(DAY, -@OlderThanDays, SYSUTCDATETIME());
  DELETE FROM dbo.RequestLog WHERE FirstSeenUTC < @Cut;
  SELECT @@ROWCOUNT AS RowsDeleted, @Cut AS CutoffUTC;
END
GO
